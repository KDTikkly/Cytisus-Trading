import Darwin
import Foundation

protocol ReadOnlyProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        cancellationRequested: () -> Bool
    ) throws -> CLIProcessResult
}

final class LongbridgeProcessRunner: ReadOnlyProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        cancellationRequested: () -> Bool = { false }
    ) throws -> CLIProcessResult {
        guard timeout > 0 else {
            throw ProcessRunnerError.invalidTimeout
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        let standardOutput = BoundedDataCapture(limit: outputLimit)
        let standardError = BoundedDataCapture(limit: outputLimit)
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            standardOutput.drain(standardOutputPipe.fileHandleForReading)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            standardError.drain(standardErrorPipe.fileHandleForReading)
            readers.leave()
        }

        let startedAt = Date()
        try process.run()
        let deadline = startedAt.addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        while process.isRunning {
            if cancellationRequested() {
                cancelled = true
                terminate(process)
                break
            }
            if Date() >= deadline {
                timedOut = true
                terminate(process)
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        process.waitUntilExit()
        standardOutputPipe.fileHandleForWriting.closeFile()
        standardErrorPipe.fileHandleForWriting.closeFile()
        readers.wait()

        return CLIProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: standardOutput.stringValue,
            standardError: standardError.stringValue,
            timedOut: timedOut,
            cancelled: cancelled,
            outputTruncated: standardOutput.truncated || standardError.truncated,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(0.25)
        while process.isRunning && Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}

enum ProcessRunnerError: Error {
    case invalidTimeout
}

private final class BoundedDataCapture: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private(set) var truncated = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 8192)
            if chunk.isEmpty {
                break
            }
            lock.lock()
            let remaining = max(0, limit - data.count)
            if remaining > 0 {
                data.append(contentsOf: chunk.prefix(remaining))
            }
            if chunk.count > remaining {
                truncated = true
            }
            lock.unlock()
        }
    }
}

enum SensitiveDataRedactor {
    private static let redacted = "[REDACTED]"

    static func redact(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let jsonRedacted = redactJSON(value) ?? value
        let patterns = [
            "(?i)\\bBearer\\s+[A-Za-z0-9._~+/=-]+",
            "(?i)\\b(token|secret|password|authorization|authorization_code|account_number|api_key|apikey|apiKey|x-api-key)\\s*[:=]\\s*[^\\s,;]+"
        ]
        return patterns.reduce(jsonRedacted) { current, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return current
            }
            let range = NSRange(current.startIndex..., in: current)
            return expression.stringByReplacingMatches(
                in: current,
                range: range,
                withTemplate: redacted
            )
        }
    }

    private static func redactJSON(_ value: String) -> String? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let output = try? JSONSerialization.data(
                withJSONObject: redactObject(object),
                options: [.sortedKeys]
              ) else {
            return nil
        }
        return String(data: output, encoding: .utf8)
    }

    private static func redactObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary {
                result[key] = isSensitiveKey(key)
                    ? redacted
                    : redactObject(child)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(redactObject)
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.replacingOccurrences(of: "-", with: "_").lowercased()
        return normalized.contains("token") ||
            normalized.contains("secret") ||
            normalized.contains("password") ||
            normalized.contains("credential") ||
            normalized.contains("api_key") ||
            normalized == "apikey" ||
            [
                "authorization",
                "authorization_code",
                "oauth",
                "account_id",
                "account_number",
                "full_account_number"
            ].contains(normalized)
    }
}

enum CapabilityAwareCommandFactory {
    static func build(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        operation: LongbridgeOperation,
        values: [String: String] = [:]
    ) throws -> CLICommand {
        guard let template = capabilities.commands.first(where: {
            $0.operation == operation
        }) else {
            throw LongbridgeAdapterError.unsupportedOperation(operation)
        }

        let arguments = try template.arguments.map { argument in
            var result = argument
            for (key, value) in values {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      value.count <= 256,
                      !value.hasPrefix("-"),
                      value.unicodeScalars.allSatisfy({
                          !CharacterSet.controlCharacters.contains($0)
                      }) else {
                    throw LongbridgeAdapterError.invalidArgumentValue
                }
                result = result.replacingOccurrences(of: "{\(key)}", with: value)
            }
            guard !result.contains("{"), !result.contains("}") else {
                throw LongbridgeAdapterError.missingArgumentValue(operation)
            }
            return result
        }

        return CLICommand(
            executableURL: executableURL,
            arguments: arguments,
            category: .readOnlyData,
            operation: operation
        )
    }
}

enum LongbridgeAdapterError: Error {
    case unsupportedOperation(LongbridgeOperation)
    case missingArgumentValue(LongbridgeOperation)
    case invalidArgumentValue
    case invalidJSON(LongbridgeOperation)
    case processFailed(LongbridgeOperation)
}

protocol LongbridgeCLIAdapting {
    func resolveExecutable(configuredPath: String) -> URL?
    func inspect(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeInspection
    func executeReadOnly(
        command: CLICommand,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) throws -> CLIProcessResult
}

final class LongbridgeCLIAdapter: LongbridgeCLIAdapting {
    private let runner: ReadOnlyProcessRunning
    private let outputLimit = 1024 * 1024

    init(runner: ReadOnlyProcessRunning) {
        self.runner = runner
    }

    func resolveExecutable(configuredPath: String) -> URL? {
        let fileManager = FileManager.default
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let url = URL(fileURLWithPath: trimmed).standardizedFileURL
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("longbridge")
            if fileManager.isExecutableFile(atPath: url.path) {
                return url.standardizedFileURL
            }
        }
        return nil
    }

    func inspect(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) -> LongbridgeInspection {
        guard let executableURL = resolveExecutable(configuredPath: configuredPath) else {
            return LongbridgeInspection(
                state: .missing,
                executableURL: nil,
                cliVersion: "Unavailable",
                checkedAt: Date(),
                dataPermissions: [],
                message: "Longbridge CLI was not found. Fixture mode remains available.",
                capabilities: nil
            )
        }

        do {
            let versionResult = try runner.run(
                executableURL: executableURL,
                arguments: ["--version"],
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )
            guard versionResult.succeeded else {
                return failedInspection(
                    executableURL: executableURL,
                    version: "Unavailable",
                    result: versionResult,
                    message: "CLI version inspection failed."
                )
            }
            let version = firstBoundedLine(versionResult.standardOutput)
            let helpResult = try runner.run(
                executableURL: executableURL,
                arguments: ["--help"],
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )
            guard helpResult.succeeded else {
                return failedInspection(
                    executableURL: executableURL,
                    version: version,
                    result: helpResult,
                    message: "CLI help inspection failed."
                )
            }

            let templates = try discoverTemplates(
                executableURL: executableURL,
                rootHelp: helpResult.standardOutput,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            let permissions = dataPermissions(templates)
            var capabilities = LongbridgeCapabilities(
                schemaVersion: 1,
                fixtureMode: false,
                cliVersion: version,
                sourceVersion: "\(version)|cytisus-adapter-1.1.1",
                statusState: .degraded,
                supportsJSON: !jsonArguments(helpResult.standardOutput).isEmpty,
                commands: templates,
                dataPermissions: permissions,
                discoveredAt: Date(),
                liveExecutionAvailable: false,
                message: "Capabilities were derived from local CLI help."
            )
            guard templates.contains(where: { $0.operation == .status }),
                  templates.contains(where: { $0.operation == .connectivity }) else {
                return LongbridgeInspection(
                    state: .degraded,
                    executableURL: executableURL,
                    cliVersion: version,
                    checkedAt: Date(),
                    dataPermissions: permissions,
                    message: "Required read-only status or connectivity capability is unavailable.",
                    capabilities: capabilities
                )
            }

            let statusCommand = try CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .status
            )
            let statusResult = try executeReadOnly(
                command: statusCommand,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            if !statusResult.succeeded {
                let output = SensitiveDataRedactor.redact(
                    statusResult.standardOutput + statusResult.standardError
                )
                let state: LongbridgeStatusState = looksUnauthenticated(output)
                    ? .unauthenticated
                    : .degraded
                capabilities.statusState = state
                return LongbridgeInspection(
                    state: state,
                    executableURL: executableURL,
                    cliVersion: version,
                    checkedAt: Date(),
                    dataPermissions: permissions,
                    message: state == .unauthenticated
                        ? "Complete authorization through Longbridge CLI."
                        : "The local CLI status check failed.",
                    capabilities: capabilities
                )
            }
            if statusSaysUnauthenticated(statusResult.standardOutput) {
                capabilities.statusState = .unauthenticated
                return LongbridgeInspection(
                    state: .unauthenticated,
                    executableURL: executableURL,
                    cliVersion: version,
                    checkedAt: Date(),
                    dataPermissions: permissions,
                    message: "Complete authorization through Longbridge CLI.",
                    capabilities: capabilities
                )
            }

            let connectivityCommand = try CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .connectivity
            )
            let connectivityResult = try executeReadOnly(
                command: connectivityCommand,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            let state: LongbridgeStatusState = connectivityResult.succeeded
                ? .ready
                : .degraded
            capabilities.statusState = state
            return LongbridgeInspection(
                state: state,
                executableURL: executableURL,
                cliVersion: version,
                checkedAt: Date(),
                dataPermissions: permissions,
                message: state == .ready
                    ? "The local CLI is ready for advertised read-only data calls."
                    : "The local CLI connectivity check failed.",
                capabilities: capabilities
            )
        } catch {
            return LongbridgeInspection(
                state: .degraded,
                executableURL: executableURL,
                cliVersion: "Unavailable",
                checkedAt: Date(),
                dataPermissions: [],
                message: "The local CLI capability check failed safely.",
                capabilities: nil
            )
        }
    }

    func executeReadOnly(
        command: CLICommand,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) throws -> CLIProcessResult {
        guard command.category == .readOnlyData else {
            throw LongbridgeAdapterError.unsupportedOperation(command.operation)
        }
        return try runner.run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            timeout: timeout,
            outputLimit: outputLimit,
            cancellationRequested: cancellationRequested
        )
    }

    private func discoverTemplates(
        executableURL: URL,
        rootHelp: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) throws -> [CLICommandTemplate] {
        var templates: [CLICommandTemplate] = []
        let rootJSON = jsonArguments(rootHelp)
        if containsWord(rootHelp, "status"), !rootJSON.isEmpty {
            templates.append(
                CLICommandTemplate(
                    operation: .status,
                    arguments: ["status"] + rootJSON
                )
            )
        }
        let connectivity = containsWord(rootHelp, "doctor")
            ? "doctor"
            : containsWord(rootHelp, "check") ? "check" : nil
        if let connectivity, !rootJSON.isEmpty {
            templates.append(
                CLICommandTemplate(
                    operation: .connectivity,
                    arguments: [connectivity] + rootJSON
                )
            )
        }
        guard containsWord(rootHelp, "market") else { return templates }

        let marketHelpResult = try runner.run(
            executableURL: executableURL,
            arguments: ["market", "--help"],
            timeout: timeout,
            outputLimit: outputLimit,
            cancellationRequested: cancellationRequested
        )
        guard marketHelpResult.succeeded else { return templates }
        let marketHelp = marketHelpResult.standardOutput
        let marketJSON = jsonArguments(marketHelp)
        addMarketTemplate(
            to: &templates,
            help: marketHelp,
            json: marketJSON,
            command: "bars",
            operation: .historicalBars,
            arguments: [
                "--symbol", "{symbol}",
                "--interval", "{interval}",
                "--start", "{start}",
                "--end", "{end}"
            ]
        )
        addMarketTemplate(
            to: &templates,
            help: marketHelp,
            json: marketJSON,
            command: "snapshot",
            operation: .currentSnapshot,
            arguments: ["--symbol", "{symbol}"]
        )
        addMarketTemplate(
            to: &templates,
            help: marketHelp,
            json: marketJSON,
            command: "status",
            operation: .marketStatus,
            arguments: ["--market", "{market}"]
        )
        addMarketTemplate(
            to: &templates,
            help: marketHelp,
            json: marketJSON,
            command: "securities",
            operation: .securityList,
            arguments: ["--market", "{market}"]
        )

        if containsWord(rootHelp, "account") {
            let accountHelp = try runner.run(
                executableURL: executableURL,
                arguments: ["account", "--help"],
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )
            let accountJSON = jsonArguments(accountHelp.standardOutput)
            if accountHelp.succeeded,
               containsWord(accountHelp.standardOutput, "positions"),
               !accountJSON.isEmpty {
                templates.append(
                    CLICommandTemplate(
                        operation: .brokerPositions,
                        arguments: ["account", "positions"] + accountJSON
                    )
                )
            }
        }
        return templates
    }

    private func addMarketTemplate(
        to templates: inout [CLICommandTemplate],
        help: String,
        json: [String],
        command: String,
        operation: LongbridgeOperation,
        arguments: [String]
    ) {
        let flags = arguments.filter { $0.hasPrefix("--") }
        guard containsWord(help, command),
              !json.isEmpty,
              flags.allSatisfy({
                  help.localizedCaseInsensitiveContains($0)
              }) else {
            return
        }
        templates.append(
            CLICommandTemplate(
                operation: operation,
                arguments: ["market", command] + arguments + json
            )
        )
    }

    private func jsonArguments(_ help: String) -> [String] {
        if help.localizedCaseInsensitiveContains("--output"),
           help.localizedCaseInsensitiveContains("json") {
            return ["--output", "json"]
        }
        if help.localizedCaseInsensitiveContains("--json") {
            return ["--json"]
        }
        return []
    }

    private func containsWord(_ value: String, _ word: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: "(?i)(^|\\s)\(NSRegularExpression.escapedPattern(for: word))(\\s|$)"
        ) else {
            return false
        }
        return expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
    }

    private func dataPermissions(_ templates: [CLICommandTemplate]) -> [String] {
        let mapping: [(LongbridgeOperation, String)] = [
            (.historicalBars, "historical_bars"),
            (.currentSnapshot, "current_snapshot"),
            (.marketStatus, "market_status"),
            (.securityList, "security_list"),
            (.brokerPositions, "position_snapshot")
        ]
        return mapping.compactMap { operation, permission in
            templates.contains(where: { $0.operation == operation })
                ? permission
                : nil
        }
    }

    private func failedInspection(
        executableURL: URL,
        version: String,
        result: CLIProcessResult,
        message: String
    ) -> LongbridgeInspection {
        LongbridgeInspection(
            state: .degraded,
            executableURL: executableURL,
            cliVersion: version,
            checkedAt: Date(),
            dataPermissions: [],
            message: result.timedOut ? "\(message) The process timed out." : message,
            capabilities: nil
        )
    }

    private func firstBoundedLine(_ value: String) -> String {
        let line = value
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "Unknown"
        return String(SensitiveDataRedactor.redact(line).prefix(128))
    }

    private func looksUnauthenticated(_ value: String) -> Bool {
        [
            "unauthenticated",
            "not authorized",
            "login required",
            "authorize"
        ].contains { value.localizedCaseInsensitiveContains($0) }
    }

    private func statusSaysUnauthenticated(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return looksUnauthenticated(SensitiveDataRedactor.redact(value))
        }
        return findFalseAuthenticated(object)
    }

    private func findFalseAuthenticated(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if key.lowercased() == "authenticated",
                   let authenticated = child as? Bool,
                   !authenticated {
                    return true
                }
                if findFalseAuthenticated(child) {
                    return true
                }
            }
        }
        if let array = value as? [Any] {
            return array.contains(where: findFalseAuthenticated)
        }
        return false
    }
}
