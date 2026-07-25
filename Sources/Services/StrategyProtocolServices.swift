import Foundation

enum StrategyProtocolError: LocalizedError {
    case invalidManifest(String)
    case malformedMessage(String)
    case missingFixture(String)
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let message),
             .malformedMessage(let message),
             .runtime(let message):
            return message
        case .missingFixture(let name):
            return "Missing strategy fixture: \(name)"
        }
    }
}

enum StrategyMessageDirection {
    case coreToStrategy
    case strategyToCore
}

final class StrategyMessageCodec {
    static let defaultMaximumMessageBytes = 64 * 1024

    private let maximumMessageBytes: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(maximumMessageBytes: Int = StrategyMessageCodec.defaultMaximumMessageBytes) {
        self.maximumMessageBytes = maximumMessageBytes
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func encode(
        _ message: StrategyMessageEnvelope,
        direction: StrategyMessageDirection
    ) throws -> String {
        try validate(message, direction: direction)
        var data = try encoder.encode(message)
        guard data.count <= maximumMessageBytes else {
            throw StrategyProtocolError.malformedMessage(
                "Strategy message exceeds the configured size limit."
            )
        }
        data.append(0x0A)
        guard let line = String(data: data, encoding: .utf8) else {
            throw StrategyProtocolError.malformedMessage(
                "Strategy message is not valid UTF-8."
            )
        }
        return line
    }

    func decode(
        _ line: String,
        direction: StrategyMessageDirection,
        expectedStrategyId: String? = nil,
        expectedStrategyVersion: String? = nil
    ) throws -> StrategyMessageEnvelope {
        guard !line.isEmpty,
              !line.contains("\n"),
              !line.contains("\r"),
              let data = line.data(using: .utf8),
              data.count <= maximumMessageBytes else {
            throw StrategyProtocolError.malformedMessage(
                "Malformed or oversized NDJSON strategy message."
            )
        }
        let message: StrategyMessageEnvelope
        do {
            message = try decoder.decode(StrategyMessageEnvelope.self, from: data)
        } catch {
            throw StrategyProtocolError.malformedMessage(
                "Malformed strategy JSON."
            )
        }
        try validate(message, direction: direction)
        if let expectedStrategyId,
           message.strategyId != expectedStrategyId {
            throw StrategyProtocolError.malformedMessage(
                "Strategy message identity mismatch."
            )
        }
        if let expectedStrategyVersion,
           message.strategyVersion != expectedStrategyVersion {
            throw StrategyProtocolError.malformedMessage(
                "Strategy message version mismatch."
            )
        }
        return message
    }

    private func validate(
        _ message: StrategyMessageEnvelope,
        direction: StrategyMessageDirection
    ) throws {
        guard message.schemaVersion == 1,
              !message.eventId.isEmpty,
              message.eventId.count <= 128,
              !message.correlationId.isEmpty,
              message.correlationId.count <= 128,
              !message.strategyId.isEmpty,
              !message.strategyVersion.isEmpty,
              !message.cycleId.isEmpty else {
            throw StrategyProtocolError.malformedMessage(
                "Strategy message is missing a required envelope field."
            )
        }
        let allowed = direction == .coreToStrategy
            ? StrategyProtocolMessageTypes.coreToStrategy
            : StrategyProtocolMessageTypes.strategyToCore
        guard allowed.contains(message.messageType) else {
            throw StrategyProtocolError.malformedMessage(
                "Unknown or directionally invalid strategy message type."
            )
        }
        guard !message.payload.keys.contains(where: sensitiveKey) else {
            throw StrategyProtocolError.malformedMessage(
                "Strategy payload contains a prohibited sensitive field."
            )
        }
    }

    private func sensitiveKey(_ value: String) -> Bool {
        let key = value.replacingOccurrences(of: "-", with: "_").lowercased()
        return key.contains("token") ||
            key.contains("secret") ||
            key.contains("credential") ||
            key.contains("authorization_code") ||
            key.contains("account_number")
    }
}

struct StrategyHeartbeatMonitor {
    let timeout: TimeInterval

    func isTimedOut(lastHeartbeat: Date?, now: Date) -> Bool {
        guard timeout > 0, let lastHeartbeat else { return true }
        return now.timeIntervalSince(lastHeartbeat) > timeout
    }
}

protocol StrategyRegistryServicing {
    func loadOfficial() throws -> (
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema
    )
    func loadThirdParty(
        manifestPath: String,
        existingStrategyIds: Set<String>
    ) throws -> (
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema
    )
    func validate(
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema,
        existingStrategyIds: Set<String>,
        manifestDirectory: URL?
    ) -> String?
    func loadAuthorizationFixture(_ name: String) throws -> LiveAuthorization
}

final class StrategyRegistryService: StrategyRegistryServicing {
    private let bundle: Bundle
    private let decoder: JSONDecoder
    private let allowedCapabilities: Set<String> = [
        "market_data", "strategy_events", "structured_logs"
    ]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func loadOfficial() throws -> (
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema
    ) {
        let manifest: StrategyManifest = try readFixture(
            "sample-strategy-manifest",
            directory: "strategies"
        )
        let parameters: StrategyParameterSchema = try readFixture(
            "official-parameter-schema",
            directory: "strategies"
        )
        if let error = validate(
            manifest: manifest,
            parameters: parameters,
            existingStrategyIds: [],
            manifestDirectory: nil
        ) {
            throw StrategyProtocolError.invalidManifest(error)
        }
        return (manifest, parameters)
    }

    func loadThirdParty(
        manifestPath: String,
        existingStrategyIds: Set<String>
    ) throws -> (
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema
    ) {
        let manifestURL = URL(fileURLWithPath: manifestPath).standardizedFileURL
        let rawManifest = try String(contentsOf: manifestURL, encoding: .utf8)
        try rejectDirectCLI(rawManifest)
        var manifest = try decoder.decode(
            StrategyManifest.self,
            from: Data(rawManifest.utf8)
        )
        guard manifest.source == .thirdParty else {
            throw StrategyProtocolError.invalidManifest(
                "A local registration must declare ThirdParty source."
            )
        }
        let directory = manifestURL.deletingLastPathComponent()
        let parameterURL = URL(
            fileURLWithPath: manifest.parameterSchema,
            relativeTo: directory
        ).standardizedFileURL
        let rawParameters = try String(contentsOf: parameterURL, encoding: .utf8)
        try rejectDirectCLI(rawParameters)
        let parameters = try decoder.decode(
            StrategyParameterSchema.self,
            from: Data(rawParameters.utf8)
        )
        if let error = validate(
            manifest: manifest,
            parameters: parameters,
            existingStrategyIds: existingStrategyIds,
            manifestDirectory: directory
        ) {
            throw StrategyProtocolError.invalidManifest(error)
        }
        let entrypointURL = URL(
            fileURLWithPath: manifest.entrypoint,
            relativeTo: directory
        ).standardizedFileURL
        manifest = StrategyManifest(
            schemaVersion: manifest.schemaVersion,
            protocolVersion: manifest.protocolVersion,
            strategyId: manifest.strategyId,
            name: manifest.name,
            version: manifest.version,
            source: manifest.source,
            entrypoint: entrypointURL.path,
            supportedModes: manifest.supportedModes,
            requiredData: manifest.requiredData,
            parameterSchemaVersion: manifest.parameterSchemaVersion,
            parameterSchema: parameterURL.path,
            requestedCapabilities: manifest.requestedCapabilities
        )
        return (manifest, parameters)
    }

    func validate(
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema,
        existingStrategyIds: Set<String>,
        manifestDirectory: URL?
    ) -> String? {
        guard manifest.schemaVersion == 1 else {
            return "Unsupported manifest schema version."
        }
        guard manifest.protocolVersion == 1 else {
            return "Unsupported strategy protocol version."
        }
        guard manifest.strategyId.range(
            of: "^[a-z0-9][a-z0-9-]{2,63}$",
            options: .regularExpression
        ) != nil else {
            return "Invalid strategy ID."
        }
        guard !existingStrategyIds.contains(manifest.strategyId) else {
            return "Duplicate strategy ID."
        }
        guard !manifest.name.isEmpty,
              manifest.version.range(
                of: "^[0-9]+\\.[0-9]+\\.[0-9]+$",
                options: .regularExpression
              ) != nil else {
            return "Invalid strategy identity or version."
        }
        guard manifest.supportedModes.contains(.paperOnly) else {
            return "Every strategy must support PaperOnly."
        }
        guard manifest.requestedCapabilities.allSatisfy({
            allowedCapabilities.contains($0) &&
                !$0.localizedCaseInsensitiveContains("cli")
        }) else {
            return "Direct CLI access is prohibited."
        }
        guard parameters.strategyId == manifest.strategyId,
              parameters.schemaVersion == manifest.parameterSchemaVersion,
              !parameters.parameters.isEmpty,
              Set(parameters.parameters.map(\.key)).count ==
                parameters.parameters.count else {
            return "Parameter schema identity, version, or keys are invalid."
        }
        for parameter in parameters.parameters {
            guard !parameter.key.isEmpty,
                  !parameter.label.isEmpty,
                  !parameter.description.isEmpty,
                  ParameterGovernanceService.isValueValid(
                    definition: parameter,
                    value: parameter.defaultValue
                  ) else {
                return "Invalid default value or incomplete parameter definition."
            }
            let safety = parameter.safetyOverride
            if safety.riskTier == .high &&
                (!safety.requiresPreview ||
                 !safety.requiresConfirmation ||
                 !safety.rollbackRequired ||
                 safety.activationMode != .safeBoundary) {
                return "High-risk safety override is incomplete."
            }
        }
        if manifest.source == .official {
            guard manifest.entrypoint.hasPrefix("fixture://") else {
                return "Official fixture entrypoint is invalid."
            }
        } else {
            guard let manifestDirectory else {
                return "Third-party manifest directory is unavailable."
            }
            let entrypoint = URL(
                fileURLWithPath: manifest.entrypoint,
                relativeTo: manifestDirectory
            ).standardizedFileURL
            guard FileManager.default.fileExists(atPath: entrypoint.path) else {
                return "Strategy entrypoint does not exist."
            }
        }
        return nil
    }

    func loadAuthorizationFixture(_ name: String) throws -> LiveAuthorization {
        try readFixture(name, directory: "execution")
    }

    private func rejectDirectCLI(_ rawJSON: String) throws {
        let raw = rawJSON.lowercased()
        if raw.contains("longbridge_cli") ||
            raw.contains("direct_cli_access") ||
            raw.contains("broker_secret") {
            throw StrategyProtocolError.invalidManifest(
                "Direct CLI access declarations are prohibited."
            )
        }
    }

    private func readFixture<T: Decodable>(
        _ name: String,
        directory: String
    ) throws -> T {
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "fixtures/\(directory)"
        ) ?? bundle.resourceURL?
            .appendingPathComponent("fixtures/\(directory)", isDirectory: true)
            .appendingPathComponent("\(name).json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw StrategyProtocolError.missingFixture(name)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

protocol ParameterGovernanceServicing {
    func requestChange(
        strategyId: String,
        definition: StrategyParameterDefinition,
        oldValue: String,
        newValue: String,
        currentVersion: Int,
        requestedBy: String,
        confirmed: Bool,
        requestedAt: Date
    ) -> ParameterChangeDecision
    func applyBoundary(
        _ change: StrategyParameterChange,
        effectiveAt: Date
    ) -> StrategyParameterChange
}

final class ParameterGovernanceService: ParameterGovernanceServicing {
    func requestChange(
        strategyId: String,
        definition: StrategyParameterDefinition,
        oldValue: String,
        newValue: String,
        currentVersion: Int,
        requestedBy: String,
        confirmed: Bool,
        requestedAt: Date
    ) -> ParameterChangeDecision {
        guard Self.isValueValid(definition: definition, value: newValue) else {
            return decision(
                strategyId: strategyId,
                definition: definition,
                oldValue: oldValue,
                newValue: newValue,
                currentVersion: currentVersion,
                requestedBy: requestedBy,
                requestedAt: requestedAt,
                result: .rejected,
                blocksNewRisk: false,
                preview: "The parameter value violates its type or hard bound."
            )
        }
        let safety = definition.safetyOverride
        if safety.riskTier == .high && !confirmed {
            return decision(
                strategyId: strategyId,
                definition: definition,
                oldValue: oldValue,
                newValue: newValue,
                currentVersion: currentVersion,
                requestedBy: requestedBy,
                requestedAt: requestedAt,
                result: .pendingConfirmation,
                blocksNewRisk: true,
                preview: "High-risk preview: \(definition.label) changes from \(oldValue) to \(newValue). New risk remains blocked until confirmation and a safe boundary."
            )
        }
        let result: ParameterChangeResult
        switch safety.activationMode {
        case .immediate: result = .applied
        case .nextCycle: result = .pendingCycle
        case .safeBoundary: result = .pendingSafeBoundary
        }
        var resultDecision = decision(
            strategyId: strategyId,
            definition: definition,
            oldValue: oldValue,
            newValue: newValue,
            currentVersion: currentVersion,
            requestedBy: requestedBy,
            requestedAt: requestedAt,
            result: result,
            blocksNewRisk: safety.riskTier == .high && result != .applied,
            preview: result == .applied
                ? "Change applied immediately."
                : "Change queued for \(safety.activationMode.rawValue)."
        )
        if result == .applied {
            let change = resultDecision.change
            resultDecision = ParameterChangeDecision(
                change: StrategyParameterChange(
                    changeId: change.changeId,
                    strategyId: change.strategyId,
                    parameterKey: change.parameterKey,
                    oldValue: change.oldValue,
                    newValue: change.newValue,
                    requestedAt: change.requestedAt,
                    effectiveAt: requestedAt,
                    requestedBy: change.requestedBy,
                    riskTier: change.riskTier,
                    parameterVersion: change.parameterVersion,
                    activationMode: change.activationMode,
                    result: change.result,
                    rollbackVersion: change.rollbackVersion
                ),
                blocksNewRisk: resultDecision.blocksNewRisk,
                impactPreview: resultDecision.impactPreview
            )
        }
        return resultDecision
    }

    func applyBoundary(
        _ change: StrategyParameterChange,
        effectiveAt: Date
    ) -> StrategyParameterChange {
        guard change.result == .pendingCycle ||
                change.result == .pendingSafeBoundary else {
            return change
        }
        return StrategyParameterChange(
            changeId: change.changeId,
            strategyId: change.strategyId,
            parameterKey: change.parameterKey,
            oldValue: change.oldValue,
            newValue: change.newValue,
            requestedAt: change.requestedAt,
            effectiveAt: effectiveAt,
            requestedBy: change.requestedBy,
            riskTier: change.riskTier,
            parameterVersion: change.parameterVersion,
            activationMode: change.activationMode,
            result: .applied,
            rollbackVersion: change.rollbackVersion
        )
    }

    static func isValueValid(
        definition: StrategyParameterDefinition,
        value: String
    ) -> Bool {
        switch definition.type {
        case .number:
            guard let numeric = Double(value) else { return false }
            return inBounds(numeric, safety: definition.safetyOverride)
        case .integer:
            guard let numeric = Int(value) else { return false }
            return inBounds(Double(numeric), safety: definition.safetyOverride)
        case .boolean:
            return value.lowercased() == "true" ||
                value.lowercased() == "false"
        case .string:
            return value.count <= 512
        }
    }

    private static func inBounds(
        _ value: Double,
        safety: ParameterSafetyOverride
    ) -> Bool {
        if let minimum = safety.hardMin.flatMap(Double.init), value < minimum {
            return false
        }
        if let maximum = safety.hardMax.flatMap(Double.init), value > maximum {
            return false
        }
        return true
    }

    private func decision(
        strategyId: String,
        definition: StrategyParameterDefinition,
        oldValue: String,
        newValue: String,
        currentVersion: Int,
        requestedBy: String,
        requestedAt: Date,
        result: ParameterChangeResult,
        blocksNewRisk: Bool,
        preview: String
    ) -> ParameterChangeDecision {
        let parameterVersion = result == .pendingConfirmation
            ? currentVersion
            : currentVersion + 1
        return ParameterChangeDecision(
            change: StrategyParameterChange(
                changeId: UUID().uuidString,
                strategyId: strategyId,
                parameterKey: definition.key,
                oldValue: oldValue,
                newValue: newValue,
                requestedAt: requestedAt,
                effectiveAt: nil,
                requestedBy: requestedBy,
                riskTier: definition.safetyOverride.riskTier,
                parameterVersion: parameterVersion,
                activationMode: definition.safetyOverride.activationMode,
                result: result,
                rollbackVersion: currentVersion
            ),
            blocksNewRisk: blocksNewRisk,
            impactPreview: preview
        )
    }
}

protocol StrategyModeServicing {
    func selectMode(
        requestedMode: StrategyMode,
        globalLiveLock: Bool,
        manifest: StrategyManifest,
        parameterVersion: Int,
        authorization: LiveAuthorization?,
        market: String,
        now: Date
    ) -> ModeSelectionResult
}

final class StrategyModeService: StrategyModeServicing {
    func selectMode(
        requestedMode: StrategyMode,
        globalLiveLock: Bool,
        manifest: StrategyManifest,
        parameterVersion: Int,
        authorization: LiveAuthorization?,
        market: String,
        now: Date
    ) -> ModeSelectionResult {
        guard requestedMode == .live else {
            return ModeSelectionResult(
                accepted: true,
                mode: .paperOnly,
                message: "Local Paper selected. It does not require or invoke Longbridge CLI."
            )
        }
        guard globalLiveLock else {
            return rejected("Global Live Lock is OFF.")
        }
        guard manifest.supportedModes.contains(.live) else {
            return rejected("The strategy does not support Live mode.")
        }
        guard let authorization, authorization.enabled else {
            return rejected("A valid Live authorization is required.")
        }
        guard authorization.strategyId == manifest.strategyId,
              authorization.parameterVersion == parameterVersion else {
            return rejected(
                "The Live authorization is incompatible with this strategy or parameter version."
            )
        }
        guard now >= authorization.validFrom,
              now < authorization.expiresAt else {
            return rejected("The Live authorization is not currently valid.")
        }
        guard authorization.allowedMarkets.contains(where: {
            $0.caseInsensitiveCompare(market) == .orderedSame
        }),
        authorization.maximumOrderFrequency > 0,
        authorization.maximumCapital > 0 else {
            return rejected(
                "The Live authorization does not permit the current market or risk bounds."
            )
        }
        return ModeSelectionResult(
            accepted: true,
            mode: .live,
            message: "Live mode is selected, but the Longbridge adapter remains intentionally rejecting until v1.1.3 command verification."
        )
    }

    private func rejected(_ message: String) -> ModeSelectionResult {
        ModeSelectionResult(
            accepted: false,
            mode: .paperOnly,
            message: message
        )
    }
}

protocol LiveBrokerAdapting: AnyObject {
    var submissionAttempts: Int { get }
    func submit(_ intent: StrategyIntentRecord) -> String
}

final class RejectingLiveBrokerAdapter: LiveBrokerAdapting {
    private(set) var submissionAttempts = 0

    func submit(_ intent: StrategyIntentRecord) -> String {
        submissionAttempts += 1
        return "Rejected: Live broker submission remains unavailable. v1.1.3 validates authentication and Paper readiness only."
    }
}

struct StrategyIntentRouter {
    func route(
        mode: StrategyMode,
        intent: StrategyIntentRecord,
        liveAdapter: LiveBrokerAdapting
    ) -> String {
        mode == .paperOnly
            ? "PaperLifecycleRecorded"
            : liveAdapter.submit(intent)
    }
}

protocol OfficialStrategyRuntimeServicing {
    func runPaperCycle(
        manifest: StrategyManifest,
        parameterValues: [String: String]
    ) throws -> PaperCycleResult
}

final class OfficialFixtureStrategyRuntime: OfficialStrategyRuntimeServicing {
    private let codec: StrategyMessageCodec
    private let router: StrategyIntentRouter
    private let liveAdapter: LiveBrokerAdapting
    private let bundle: Bundle

    init(
        codec: StrategyMessageCodec,
        router: StrategyIntentRouter,
        liveAdapter: LiveBrokerAdapting,
        bundle: Bundle = .main
    ) {
        self.codec = codec
        self.router = router
        self.liveAdapter = liveAdapter
        self.bundle = bundle
    }

    func runPaperCycle(
        manifest: StrategyManifest,
        parameterValues: [String: String]
    ) throws -> PaperCycleResult {
        for type in ["initialize", "load_parameters", "start_cycle"] {
            let payload = type == "load_parameters"
                ? parameterValues
                : ["mode": StrategyMode.paperOnly.rawValue]
            _ = try codec.encode(
                StrategyMessageEnvelope(
                    schemaVersion: 1,
                    eventId: UUID().uuidString,
                    correlationId: "corr-paper-0001",
                    strategyId: manifest.strategyId,
                    strategyVersion: manifest.version,
                    cycleId: "cycle-paper-0001",
                    timestamp: Date(timeIntervalSince1970: 1_721_858_999),
                    messageType: type,
                    payload: payload
                ),
                direction: .coreToStrategy
            )
        }
        let messages = try loadMessages(manifest: manifest)
        guard Set(messages.map(\.eventId)).count == messages.count else {
            throw StrategyProtocolError.malformedMessage(
                "The official fixture emitted a duplicate event ID."
            )
        }
        guard let completed = messages.first(where: {
            $0.messageType == "cycle_complete"
        }),
        let lastHeartbeat = messages
            .filter({ $0.messageType == "heartbeat" })
            .map(\.timestamp)
            .max() else {
            throw StrategyProtocolError.malformedMessage(
                "The official fixture did not complete with a heartbeat."
            )
        }
        let health: HealthState = StrategyHeartbeatMonitor(
            timeout: 10
        ).isTimedOut(lastHeartbeat: lastHeartbeat, now: completed.timestamp)
            ? .unhealthy
            : .healthy
        let signals = try messages
            .filter { $0.messageType == "signal" }
            .map {
                StrategySignal(
                    symbol: try required($0, "symbol"),
                    score: try number($0, "score"),
                    reason: try required($0, "reason"),
                    timestamp: $0.timestamp
                )
            }
        let targets = try messages
            .filter { $0.messageType == "target_position" }
            .map {
                StrategyTarget(
                    symbol: try required($0, "symbol"),
                    targetWeight: try number($0, "target_weight"),
                    reason: try required($0, "reason"),
                    timestamp: $0.timestamp
                )
            }
        let intents = try messages
            .filter { $0.messageType == "trade_intent" }
            .map {
                StrategyIntentRecord(
                    intentId: try required($0, "intent_id"),
                    symbol: try required($0, "symbol"),
                    targetWeight: try number($0, "target_weight"),
                    priority: Int(try required($0, "priority")) ?? 0,
                    allowPartial: Bool(try required($0, "allow_partial")) ?? false,
                    reasonCode: try required($0, "reason_code"),
                    cycleId: $0.cycleId,
                    timestamp: $0.timestamp,
                    mode: .paperOnly
                )
            }
        for intent in intents {
            guard router.route(
                mode: .paperOnly,
                intent: intent,
                liveAdapter: liveAdapter
            ) == "PaperLifecycleRecorded" else {
                throw StrategyProtocolError.runtime(
                    "Local Paper reached a Live adapter."
                )
            }
        }
        return PaperCycleResult(
            cycle: StrategyCycleSummary(
                cycleId: completed.cycleId,
                completedAt: completed.timestamp,
                signalCount: signals.count,
                targetCount: targets.count,
                intentCount: intents.count,
                result: try required(completed, "result")
            ),
            lastHeartbeat: lastHeartbeat,
            health: health,
            signals: signals,
            targets: targets,
            intents: intents,
            messages: messages
        )
    }

    private func loadMessages(
        manifest: StrategyManifest
    ) throws -> [StrategyMessageEnvelope] {
        let name = "official-paper-cycle"
        let url = bundle.url(
            forResource: name,
            withExtension: "ndjson",
            subdirectory: "fixtures/strategies"
        ) ?? bundle.resourceURL?
            .appendingPathComponent("fixtures/strategies", isDirectory: true)
            .appendingPathComponent("\(name).ndjson")
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw StrategyProtocolError.missingFixture(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map {
                try codec.decode(
                    String($0),
                    direction: .strategyToCore,
                    expectedStrategyId: manifest.strategyId,
                    expectedStrategyVersion: manifest.version
                )
            }
    }

    private func required(
        _ message: StrategyMessageEnvelope,
        _ key: String
    ) throws -> String {
        guard let value = message.payload[key], !value.isEmpty else {
            throw StrategyProtocolError.malformedMessage(
                "Strategy message is missing payload field \(key)."
            )
        }
        return value
    }

    private func number(
        _ message: StrategyMessageEnvelope,
        _ key: String
    ) throws -> Double {
        guard let value = Double(try required(message, key)) else {
            throw StrategyProtocolError.malformedMessage(
                "Strategy payload field \(key) is not numeric."
            )
        }
        return value
    }
}
