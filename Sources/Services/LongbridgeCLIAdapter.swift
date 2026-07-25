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

protocol StreamingProcessRunning {
    func runStreaming(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        cancellationRequested: () -> Bool,
        progress: @escaping (String) -> Void
    ) throws -> CLIProcessResult
}

final class LongbridgeProcessRunner:
    ReadOnlyProcessRunning,
    StreamingProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        cancellationRequested: () -> Bool = { false }
    ) throws -> CLIProcessResult {
        try runCore(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout,
            outputLimit: outputLimit,
            cancellationRequested: cancellationRequested,
            progress: nil
        )
    }

    func runStreaming(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        cancellationRequested: () -> Bool,
        progress: @escaping (String) -> Void
    ) throws -> CLIProcessResult {
        try runCore(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout,
            outputLimit: outputLimit,
            cancellationRequested: cancellationRequested,
            progress: progress
        )
    }

    private func runCore(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        cancellationRequested: () -> Bool,
        progress: ((String) -> Void)?
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
            standardOutput.drain(
                standardOutputPipe.fileHandleForReading,
                progress: progress
            )
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            standardError.drain(
                standardErrorPipe.fileHandleForReading,
                progress: progress
            )
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

    func drain(
        _ handle: FileHandle,
        progress: ((String) -> Void)? = nil
    ) {
        while true {
            let chunk = handle.readData(ofLength: 8192)
            if chunk.isEmpty {
                break
            }
            if let text = String(data: chunk, encoding: .utf8) {
                progress?(text)
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
            let url = URL(fileURLWithPath: trimmed)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var candidates = path.split(separator: ":").map(String.init).map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("longbridge")
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/longbridge"),
            URL(fileURLWithPath: "/usr/local/bin/longbridge"),
            URL(fileURLWithPath: "/usr/bin/longbridge")
        ])
        for candidate in candidates {
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
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
            _ = try runner.run(
                executableURL: executableURL,
                arguments: ["--help"],
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )

            let templates = try discoverTemplates(
                executableURL: executableURL,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            let permissions = dataPermissions(templates)
            var capabilities = LongbridgeCapabilities(
                schemaVersion: 1,
                fixtureMode: false,
                cliVersion: version,
                sourceVersion: "\(version)|cytisus-adapter-1.1.3",
                statusState: .degraded,
                supportsJSON: !templates.isEmpty,
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
                ? .readyUnknownChannel
                : .degraded
            capabilities.statusState = state
            return LongbridgeInspection(
                state: state,
                executableURL: executableURL,
                cliVersion: version,
                checkedAt: Date(),
                dataPermissions: permissions,
                message: state == .readyUnknownChannel
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
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) throws -> [CLICommandTemplate] {
        var templates: [CLICommandTemplate] = []
        let specifications: [(
            LongbridgeOperation,
            [String],
            [String],
            [String]
        )] = [
            (
                .status,
                ["auth", "status", "--help"],
                ["auth", "status", "--format", "json"],
                ["--format"]
            ),
            (
                .connectivity,
                ["check", "--help"],
                ["check", "--format", "json"],
                ["--format"]
            ),
            (
                .currentSnapshot,
                ["quote", "--help"],
                ["quote", "{symbol}", "--format", "json"],
                ["--format"]
            ),
            (
                .historicalBars,
                ["kline", "history", "--help"],
                [
                    "kline", "history", "{symbol}",
                    "--start", "{start}", "--end", "{end}",
                    "--format", "json"
                ],
                ["--start", "--end", "--format"]
            ),
            (
                .securityList,
                ["security-list", "--help"],
                ["security-list", "{market}", "--format", "json"],
                ["--format"]
            ),
            (
                .brokerPositions,
                ["positions", "--help"],
                ["positions", "--format", "json"],
                ["--format"]
            )
        ]
        for (operation, helpArguments, arguments, requiredFlags) in specifications {
            let result = try runner.run(
                executableURL: executableURL,
                arguments: helpArguments,
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )
            if result.succeeded,
               requiredFlags.allSatisfy({
                   result.standardOutput.localizedCaseInsensitiveContains($0)
               }) {
                templates.append(
                    CLICommandTemplate(
                        operation: operation,
                        arguments: arguments
                    )
                )
            }
        }
        return templates
    }

    private func dataPermissions(_ templates: [CLICommandTemplate]) -> [String] {
        let mapping: [(LongbridgeOperation, String)] = [
            (.historicalBars, "historical_bars"),
            (.currentSnapshot, "current_snapshot"),
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
