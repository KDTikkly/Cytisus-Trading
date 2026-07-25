import Foundation

protocol LongbridgeAuthenticationServicing: AnyObject {
    var progressHandler: ((LongbridgeAuthenticationProgress) -> Void)? {
        get
        set
    }
    var hasAuthorizationCodeInMemory: Bool { get }

    func check(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState

    func signIn(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState

    func signInWithAuthorizationCode(
        configuredPath: String,
        authorizationCode: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState

    func signOut(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState

    func update(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState
}

enum LongbridgeMaintenanceCommandFactory {
    static func build(
        executableURL: URL,
        operation: LongbridgeMaintenanceOperation,
        authorizationCode: String? = nil
    ) throws -> LongbridgeMaintenanceCommand {
        let category: CLICallCategory
        let arguments: [String]
        switch operation {
        case .version:
            category = .maintenance
            arguments = ["--version"]
        case .rootHelp:
            category = .maintenance
            arguments = ["--help"]
        case .authHelp:
            category = .authentication
            arguments = ["auth", "--help"]
        case .deviceLogin:
            category = .authentication
            arguments = ["auth", "login"]
        case .authorizationCodeLogin:
            category = .authentication
            arguments = [
                "auth", "login", "--auth-code",
                try validateAuthorizationCode(authorizationCode)
            ]
        case .authStatus:
            category = .authentication
            arguments = ["auth", "status", "--format", "json"]
        case .logout:
            category = .authentication
            arguments = ["auth", "logout"]
        case .connectivityCheck:
            category = .readOnlyData
            arguments = ["check", "--format", "json"]
        case .update:
            category = .maintenance
            arguments = ["update"]
        }
        return LongbridgeMaintenanceCommand(
            executableURL: executableURL,
            arguments: arguments,
            category: category,
            operation: operation
        )
    }

    private static func validateAuthorizationCode(_ value: String?) throws -> String {
        let code = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (4...256).contains(code.count),
              !code.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw LongbridgeAdapterError.invalidArgumentValue
        }
        return code
    }
}

final class LongbridgeAuthenticationService: LongbridgeAuthenticationServicing {
    private let adapter: LongbridgeCLIAdapting
    private let runner: ReadOnlyProcessRunning
    private let store: LongbridgeConnectionStore
    private let auditStore: AuditEventStore
    private let outputLimit = 256 * 1024
    private var authorizationCodeBytes: [UInt8]?
    private var lastStatus: LongbridgeStatusState = .missing
    var progressHandler: ((LongbridgeAuthenticationProgress) -> Void)?

    init(
        adapter: LongbridgeCLIAdapting,
        runner: ReadOnlyProcessRunning,
        store: LongbridgeConnectionStore,
        auditStore: AuditEventStore
    ) {
        self.adapter = adapter
        self.runner = runner
        self.store = store
        self.auditStore = auditStore
    }

    var hasAuthorizationCodeInMemory: Bool {
        authorizationCodeBytes != nil
    }

    func check(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) -> LongbridgeConnectionState {
        let inspection = adapter.inspect(
            configuredPath: configuredPath,
            timeout: timeout,
            cancellationRequested: cancellationRequested
        )
        guard inspection.state != .missing,
              let executableURL = inspection.executableURL,
              let capabilities = inspection.capabilities else {
            return fromInspection(inspection)
        }
        guard let version = semanticVersion(inspection.cliVersion),
              version >= 20_000 else {
            return complete(
                inspection: inspection,
                status: .updateRequired,
                connectivityReady: false,
                environment: "Unknown",
                channel: "Unknown",
                permissions: [],
                failureCategory: "Version",
                message: "Longbridge CLI 0.20.0 or later is required to classify Paper accounts."
            )
        }

        do {
            let statusCommand = try CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .status
            )
            let statusResult = try adapter.executeReadOnly(
                command: statusCommand,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            guard statusResult.succeeded else {
                let safe = SensitiveDataRedactor.redact(
                    statusResult.standardOutput + statusResult.standardError
                )
                let unauthenticated = looksUnauthenticated(safe)
                return complete(
                    inspection: inspection,
                    status: unauthenticated ? .unauthenticated : .degraded,
                    connectivityReady: false,
                    environment: "Unknown",
                    channel: "Unknown",
                    permissions: [],
                    failureCategory: unauthenticated
                        ? "Authentication" : "StatusCheck",
                    message: unauthenticated
                        ? "Sign in through Longbridge Terminal."
                        : "Longbridge authentication status could not be checked."
                )
            }

            let facts = try LongbridgeAuthStatusParser.parse(statusResult.standardOutput)
            if facts.refreshPending {
                return complete(
                    inspection: inspection,
                    status: .refreshPending,
                    connectivityReady: false,
                    environment: facts.environment,
                    channel: facts.channel,
                    permissions: facts.permissions,
                    failureCategory: "Authentication",
                    message: "Longbridge authentication refresh is pending."
                )
            }
            if facts.expired {
                return complete(
                    inspection: inspection,
                    status: .expired,
                    connectivityReady: false,
                    environment: facts.environment,
                    channel: facts.channel,
                    permissions: facts.permissions,
                    failureCategory: "Authentication",
                    message: "Longbridge authentication has expired. Sign in again."
                )
            }
            guard facts.authenticated else {
                return complete(
                    inspection: inspection,
                    status: .unauthenticated,
                    connectivityReady: false,
                    environment: facts.environment,
                    channel: facts.channel,
                    permissions: facts.permissions,
                    failureCategory: "Authentication",
                    message: "Sign in through Longbridge Terminal."
                )
            }

            let checkCommand = try CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .connectivity
            )
            let checkResult = try adapter.executeReadOnly(
                command: checkCommand,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            guard checkResult.succeeded else {
                return complete(
                    inspection: inspection,
                    status: .degraded,
                    connectivityReady: false,
                    environment: facts.environment,
                    channel: facts.channel,
                    permissions: facts.permissions,
                    failureCategory: "Connectivity",
                    message: "Longbridge authentication is valid, but connectivity is degraded."
                )
            }

            let state = classifyChannel(facts.channel)
            return complete(
                inspection: inspection,
                status: state,
                connectivityReady: true,
                environment: facts.environment,
                channel: facts.channel,
                permissions: facts.permissions,
                failureCategory: "",
                message: state == .readyPaper
                    ? "Longbridge Paper is ready. Local Paper remains independent."
                    : state == .readyLive
                        ? "A Longbridge Live account is connected. Live submission remains unavailable."
                        : "The Longbridge account channel is not recognized. Longbridge Paper is blocked."
            )
        } catch {
            return failed(
                executableURL: executableURL,
                failureCategory: "Capability",
                message: "Longbridge authentication inspection failed safely."
            )
        }
    }

    func signIn(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) -> LongbridgeConnectionState {
        runLogin(
            configuredPath: configuredPath,
            operation: .deviceLogin,
            authorizationCode: nil,
            timeout: timeout,
            cancellationRequested: cancellationRequested
        )
    }

    func signInWithAuthorizationCode(
        configuredPath: String,
        authorizationCode: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) -> LongbridgeConnectionState {
        authorizationCodeBytes = Array(authorizationCode.utf8)
        defer {
            if authorizationCodeBytes != nil {
                for index in authorizationCodeBytes!.indices {
                    authorizationCodeBytes![index] = 0
                }
                authorizationCodeBytes = nil
            }
        }
        let code = authorizationCodeBytes.flatMap {
            String(bytes: $0, encoding: .utf8)
        } ?? ""
        return runLogin(
            configuredPath: configuredPath,
            operation: .authorizationCodeLogin,
            authorizationCode: code,
            timeout: timeout,
            cancellationRequested: cancellationRequested
        )
    }

    func signOut(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) -> LongbridgeConnectionState {
        let state = runMaintenance(
            configuredPath: configuredPath,
            operation: .logout,
            timeout: timeout,
            cancellationRequested: cancellationRequested
        )
        return state.status == .degraded
            ? state
            : check(
                configuredPath: configuredPath,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
    }

    func update(
        configuredPath: String,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool = { false }
    ) -> LongbridgeConnectionState {
        let state = runMaintenance(
            configuredPath: configuredPath,
            operation: .update,
            timeout: timeout,
            cancellationRequested: cancellationRequested
        )
        return state.status == .degraded
            ? state
            : check(
                configuredPath: configuredPath,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
    }

    private func runLogin(
        configuredPath: String,
        operation: LongbridgeMaintenanceOperation,
        authorizationCode: String?,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState {
        guard let executableURL = adapter.resolveExecutable(
            configuredPath: configuredPath
        ) else {
            return missing()
        }
        do {
            let authHelpCommand = try LongbridgeMaintenanceCommandFactory.build(
                executableURL: executableURL,
                operation: .authHelp
            )
            let authHelp = try runner.run(
                executableURL: executableURL,
                arguments: authHelpCommand.arguments,
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )
            guard authHelp.succeeded,
                  authHelp.standardOutput.localizedCaseInsensitiveContains(
                      "login"
                  ) else {
                return failed(
                    executableURL: executableURL,
                    failureCategory: "Capability",
                    message: "The installed Longbridge CLI does not advertise the required login capability."
                )
            }
            let command = try LongbridgeMaintenanceCommandFactory.build(
                executableURL: executableURL,
                operation: operation,
                authorizationCode: authorizationCode
            )
            let result: CLIProcessResult
            if let streamingRunner = runner as? StreamingProcessRunning {
                result = try streamingRunner.runStreaming(
                    executableURL: command.executableURL,
                    arguments: command.arguments,
                    timeout: timeout,
                    outputLimit: outputLimit,
                    cancellationRequested: cancellationRequested,
                    progress: { [weak self] output in
                        guard let self else { return }
                        let progress = self.parseLoginProgress(output)
                        if !progress.authorizationURL.isEmpty ||
                            !progress.shortCode.isEmpty {
                            self.progressHandler?(progress)
                        }
                    }
                )
            } else {
                result = try runner.run(
                    executableURL: command.executableURL,
                    arguments: command.arguments,
                    timeout: timeout,
                    outputLimit: outputLimit,
                    cancellationRequested: cancellationRequested
                )
            }
            appendAudit(
                action: operation.rawValue,
                result: result.succeeded ? .completed : .failed,
                processResult: result
            )
            guard result.succeeded else {
                return failed(
                    executableURL: executableURL,
                    failureCategory: result.cancelled
                        ? "Cancelled" : result.timedOut ? "Timeout" : "Authentication",
                    message: result.cancelled
                        ? "Longbridge sign-in was cancelled."
                        : result.timedOut
                            ? "Longbridge sign-in timed out."
                            : "Longbridge sign-in failed safely."
                )
            }
            let progress = parseLoginProgress(
                result.standardOutput + "\n" + result.standardError
            )
            let state = check(
                configuredPath: configuredPath,
                timeout: timeout,
                cancellationRequested: cancellationRequested
            )
            return LongbridgeConnectionState(
                status: state.status,
                executableURL: state.executableURL,
                cliVersion: state.cliVersion,
                connectivityReady: state.connectivityReady,
                accountEnvironment: state.accountEnvironment,
                accountChannel: state.accountChannel,
                permissionsSummary: state.permissionsSummary,
                checkedAt: state.checkedAt,
                failureCategory: state.failureCategory,
                message: state.message,
                authorizationURL: progress.authorizationURL,
                shortCode: progress.shortCode
            )
        } catch {
            return failed(
                executableURL: executableURL,
                failureCategory: "Authentication",
                message: "Longbridge sign-in failed safely."
            )
        }
    }

    private func runMaintenance(
        configuredPath: String,
        operation: LongbridgeMaintenanceOperation,
        timeout: TimeInterval,
        cancellationRequested: () -> Bool
    ) -> LongbridgeConnectionState {
        guard let executableURL = adapter.resolveExecutable(
            configuredPath: configuredPath
        ) else {
            return missing()
        }
        do {
            let command = try LongbridgeMaintenanceCommandFactory.build(
                executableURL: executableURL,
                operation: operation
            )
            let result = try runner.run(
                executableURL: command.executableURL,
                arguments: command.arguments,
                timeout: timeout,
                outputLimit: outputLimit,
                cancellationRequested: cancellationRequested
            )
            appendAudit(
                action: operation.rawValue,
                result: result.succeeded ? .completed : .failed,
                processResult: result
            )
            return result.succeeded
                ? LongbridgeConnectionState(
                    status: .installed,
                    executableURL: executableURL,
                    cliVersion: "Checking",
                    connectivityReady: false,
                    accountEnvironment: "Unknown",
                    accountChannel: "Unknown",
                    permissionsSummary: [],
                    checkedAt: Date(),
                    failureCategory: "",
                    message: "Longbridge maintenance operation completed.",
                    authorizationURL: "",
                    shortCode: ""
                )
                : failed(
                    executableURL: executableURL,
                    failureCategory: result.timedOut ? "Timeout" : "Maintenance",
                    message: "Longbridge maintenance operation failed safely."
                )
        } catch {
            return failed(
                executableURL: executableURL,
                failureCategory: "Maintenance",
                message: "Longbridge maintenance operation failed safely."
            )
        }
    }

    private func complete(
        inspection: LongbridgeInspection,
        status: LongbridgeStatusState,
        connectivityReady: Bool,
        environment: String,
        channel: String,
        permissions: [String],
        failureCategory: String,
        message: String
    ) -> LongbridgeConnectionState {
        let metadata = LongbridgeConnectionMetadata(
            accountEnvironment: normalized(environment),
            accountChannel: normalized(channel),
            statusCheckedAt: Date(),
            cliVersion: inspection.cliVersion,
            permissionsSummary: Array(
                Set(permissions.map(normalized).filter { $0 != "Unknown" })
            ).sorted().prefix(32).map { $0 }
        )
        try? store.saveLongbridgeConnection(metadata)
        let previousStatus = lastStatus
        lastStatus = status
        appendAudit(
            action: "ConnectionStateChecked",
            result: [.readyPaper, .readyLive, .readyUnknownChannel].contains(status)
                ? .completed : .rejected,
            status: status,
            previousStatus: previousStatus,
            metadata: metadata
        )
        return LongbridgeConnectionState(
            status: status,
            executableURL: inspection.executableURL,
            cliVersion: inspection.cliVersion,
            connectivityReady: connectivityReady,
            accountEnvironment: metadata.accountEnvironment,
            accountChannel: metadata.accountChannel,
            permissionsSummary: metadata.permissionsSummary,
            checkedAt: metadata.statusCheckedAt,
            failureCategory: failureCategory,
            message: message,
            authorizationURL: "",
            shortCode: ""
        )
    }

    private func fromInspection(
        _ inspection: LongbridgeInspection
    ) -> LongbridgeConnectionState {
        LongbridgeConnectionState(
            status: inspection.state,
            executableURL: inspection.executableURL,
            cliVersion: inspection.cliVersion,
            connectivityReady: false,
            accountEnvironment: "Unknown",
            accountChannel: "Unknown",
            permissionsSummary: inspection.dataPermissions,
            checkedAt: inspection.checkedAt,
            failureCategory: inspection.state == .missing
                ? "Discovery" : "Capability",
            message: inspection.message,
            authorizationURL: "",
            shortCode: ""
        )
    }

    private func missing() -> LongbridgeConnectionState {
        LongbridgeConnectionState(
            status: .missing,
            executableURL: nil,
            cliVersion: "Unavailable",
            connectivityReady: false,
            accountEnvironment: "Unknown",
            accountChannel: "Unknown",
            permissionsSummary: [],
            checkedAt: Date(),
            failureCategory: "Discovery",
            message: "Longbridge CLI was not found. Local Paper remains available.",
            authorizationURL: "",
            shortCode: ""
        )
    }

    private func failed(
        executableURL: URL,
        failureCategory: String,
        message: String
    ) -> LongbridgeConnectionState {
        LongbridgeConnectionState(
            status: .degraded,
            executableURL: executableURL,
            cliVersion: "Unknown",
            connectivityReady: false,
            accountEnvironment: "Unknown",
            accountChannel: "Unknown",
            permissionsSummary: [],
            checkedAt: Date(),
            failureCategory: failureCategory,
            message: message,
            authorizationURL: "",
            shortCode: ""
        )
    }

    private func classifyChannel(_ channel: String) -> LongbridgeStatusState {
        switch channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lb_papertrading":
            return .readyPaper
        case "lb_live", "live", "production", "real":
            return .readyLive
        default:
            return .readyUnknownChannel
        }
    }

    private func semanticVersion(_ value: String) -> Int? {
        guard let expression = try? NSRegularExpression(
            pattern: "\\b(\\d+)\\.(\\d+)\\.(\\d+)\\b"
        ), let match = expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) else {
            return nil
        }
        let parts = (1...3).compactMap { index in
            Range(match.range(at: index), in: value).flatMap {
                Int(value[$0])
            }
        }
        guard parts.count == 3 else { return nil }
        return parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2]
    }

    private func looksUnauthenticated(_ value: String) -> Bool {
        [
            "unauthenticated",
            "not authorized",
            "login required",
            "sign in"
        ].contains { value.localizedCaseInsensitiveContains($0) }
    }

    private func normalized(_ value: String) -> String {
        let safe = SensitiveDataRedactor.redact(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "Unknown" : String(safe.prefix(128))
    }

    private func parseLoginProgress(_ output: String) -> LongbridgeAuthenticationProgress {
        let safe = SensitiveDataRedactor.redact(output)
        let url = firstMatch(
            pattern: "https://[^\\s\"'<>]+",
            value: safe,
            capture: 0
        )
        let code = firstMatch(
            pattern: "(?i)(?:code|verification)[^A-Z0-9]{0,12}([A-Z0-9-]{4,16})",
            value: safe,
            capture: 1
        )
        return LongbridgeAuthenticationProgress(
            status: .authorizing,
            authorizationURL: String(url.prefix(512)),
            shortCode: code,
            message: "Complete authorization in the browser, then return to Cytisus."
        )
    }

    private func firstMatch(
        pattern: String,
        value: String,
        capture: Int
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..., in: value)
              ),
              let range = Range(match.range(at: capture), in: value) else {
            return ""
        }
        return String(value[range])
    }

    private func appendAudit(
        action: String,
        result: AuditResult,
        processResult: CLIProcessResult
    ) {
        try? auditStore.appendAuditEvent(
            AuditEvent(
                id: UUID().uuidString,
                occurredAt: Date(),
                category: .accountMapping,
                action: action,
                result: result,
                actor: "Operator",
                correlationID: UUID().uuidString,
                context: [
                    "timed_out": processResult.timedOut ? "true" : "false",
                    "cancelled": processResult.cancelled ? "true" : "false",
                    "output_logged": "false"
                ]
            )
        )
    }

    private func appendAudit(
        action: String,
        result: AuditResult,
        status: LongbridgeStatusState,
        previousStatus: LongbridgeStatusState,
        metadata: LongbridgeConnectionMetadata
    ) {
        try? auditStore.appendAuditEvent(
            AuditEvent(
                id: UUID().uuidString,
                occurredAt: Date(),
                category: .accountMapping,
                action: action,
                result: result,
                actor: "Application",
                correlationID: UUID().uuidString,
                context: [
                    "previous_status": previousStatus.rawValue,
                    "status": status.rawValue,
                    "environment": metadata.accountEnvironment,
                    "channel": metadata.accountChannel,
                    "raw_output_stored": "false"
                ]
            )
        )
    }
}

struct LongbridgeAuthFacts {
    let authenticated: Bool
    let refreshPending: Bool
    let expired: Bool
    let environment: String
    let channel: String
    let permissions: [String]
}

enum LongbridgeAuthStatusParser {
    static func parse(_ json: String) throws -> LongbridgeAuthFacts {
        guard let data = json.data(using: .utf8) else {
            throw LongbridgeAdapterError.invalidJSON(.status)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        var values: [String: [Any]] = [:]
        visit(object, values: &values)
        let status = findString(values, keys: ["auth_status", "status"])
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return LongbridgeAuthFacts(
            authenticated: findBool(values, key: "authenticated") ??
                ["authenticated", "ready", "active"].contains(status),
            refreshPending: findBool(values, key: "refresh_pending") ??
                ["refreshpending", "refresh_pending"].contains(status),
            expired: findBool(values, key: "expired") ??
                (status == "expired"),
            environment: findString(
                values,
                keys: ["account_environment", "environment"]
            ),
            channel: findString(
                values,
                keys: ["account_channel", "channel"]
            ),
            permissions: findStrings(
                values,
                keys: ["permissions", "scopes"]
            )
        )
    }

    private static func visit(_ value: Any, values: inout [String: [Any]]) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.replacingOccurrences(of: "-", with: "_")
                    .lowercased()
                values[normalized, default: []].append(child)
                visit(child, values: &values)
            }
        } else if let array = value as? [Any] {
            array.forEach { visit($0, values: &values) }
        }
    }

    private static func findBool(
        _ values: [String: [Any]],
        key: String
    ) -> Bool? {
        values[key]?.compactMap { $0 as? Bool }.first
    }

    private static func findString(
        _ values: [String: [Any]],
        keys: [String]
    ) -> String {
        for key in keys {
            if let value = values[key]?.compactMap({ $0 as? String }).first {
                return SensitiveDataRedactor.redact(value)
            }
        }
        return "Unknown"
    }

    private static func findStrings(
        _ values: [String: [Any]],
        keys: [String]
    ) -> [String] {
        var result: [String] = []
        for key in keys {
            for value in values[key] ?? [] {
                if let strings = value as? [String] {
                    result.append(contentsOf: strings.map(SensitiveDataRedactor.redact))
                }
            }
        }
        return Array(Set(result.filter { !$0.isEmpty })).sorted().prefix(32).map { $0 }
    }
}

enum LongbridgeInstallGuidance {
    static let repositoryURL =
        "https://github.com/longbridge/longbridge-terminal"
    static let windowsPowerShell =
        "iwr https://open.longbridge.cn/longbridge/longbridge-terminal/install.ps1 | iex"
    static let windowsScoop =
        "scoop install https://open.longbridge.cn/longbridge/longbridge-terminal/longbridge.json"
    static let macHomebrew =
        "brew install --cask longbridge/tap/longbridge-terminal"
    static let macShell =
        "curl -sSL https://open.longbridge.cn/longbridge/longbridge-terminal/install | sh"
}
