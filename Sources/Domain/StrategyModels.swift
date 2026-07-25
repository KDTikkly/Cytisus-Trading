import Foundation

enum StrategySource: String, Codable, CaseIterable {
    case official = "Official"
    case thirdParty = "ThirdParty"
}

enum StrategyRuntimeState: String, Codable, CaseIterable {
    case stopped = "Stopped"
    case starting = "Starting"
    case ready = "Ready"
    case running = "Running"
    case paused = "Paused"
    case unhealthy = "Unhealthy"
    case exited = "Exited"
    case rejected = "Rejected"
}

enum ParameterType: String, Codable {
    case number = "Number"
    case integer = "Integer"
    case boolean = "Boolean"
    case string = "String"
}

enum RiskTier: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum ParameterActivationMode: String, Codable {
    case immediate = "Immediate"
    case nextCycle = "NextCycle"
    case safeBoundary = "SafeBoundary"
}

enum ParameterChangeResult: String, Codable {
    case applied = "Applied"
    case pendingCycle = "PendingCycle"
    case pendingConfirmation = "PendingConfirmation"
    case pendingSafeBoundary = "PendingSafeBoundary"
    case rejected = "Rejected"
}

enum LiveToPaperTransition: String, Codable, CaseIterable, Identifiable {
    case stopOpeningRisk = "StopOpeningRisk"
    case freeze = "Freeze"
    case controlledExit = "ControlledExit"

    var id: String { rawValue }
}

struct StrategyManifest: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let protocolVersion: Int
    let strategyId: String
    let name: String
    let version: String
    let source: StrategySource
    let entrypoint: String
    let supportedModes: [StrategyMode]
    let requiredData: [String]
    let parameterSchemaVersion: Int
    let parameterSchema: String
    let requestedCapabilities: [String]

    var id: String { strategyId }
}

struct ParameterSafetyOverride: Codable, Equatable {
    let hardMin: String?
    let hardMax: String?
    let riskTier: RiskTier
    let liveMutable: Bool
    let requiresPreview: Bool
    let requiresPause: Bool
    let requiresConfirmation: Bool
    let activationMode: ParameterActivationMode
    let rollbackRequired: Bool
}

struct StrategyParameterDefinition: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    let description: String
    let type: ParameterType
    let defaultValue: String
    let recommendedMin: String?
    let recommendedMax: String?
    let recommendedActivationMode: ParameterActivationMode
    let safetyOverride: ParameterSafetyOverride

    var id: String { key }
}

struct StrategyParameterSchema: Codable, Equatable {
    let schemaVersion: Int
    let strategyId: String
    let parameters: [StrategyParameterDefinition]
}

struct StrategyParameterChange: Codable, Identifiable, Equatable {
    let changeId: String
    let strategyId: String
    let parameterKey: String
    let oldValue: String
    let newValue: String
    let requestedAt: Date
    let effectiveAt: Date?
    let requestedBy: String
    let riskTier: RiskTier
    let parameterVersion: Int
    let activationMode: ParameterActivationMode
    let result: ParameterChangeResult
    let rollbackVersion: Int

    var id: String { changeId }
}

struct StrategyMessageEnvelope: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let eventId: String
    let correlationId: String
    let strategyId: String
    let strategyVersion: String
    let cycleId: String
    let timestamp: Date
    let messageType: String
    let payload: [String: String]

    var id: String { eventId }
}

struct StrategySignal: Identifiable, Equatable {
    let symbol: String
    let score: Double
    let reason: String
    let timestamp: Date

    var id: String { "\(symbol)-\(timestamp.timeIntervalSince1970)" }
}

struct StrategyTarget: Identifiable, Equatable {
    let symbol: String
    let targetWeight: Double
    let reason: String
    let timestamp: Date

    var id: String { "\(symbol)-\(timestamp.timeIntervalSince1970)" }
}

struct StrategyIntentRecord: Codable, Identifiable, Equatable {
    let intentId: String
    let symbol: String
    let targetWeight: Double
    let priority: Int
    let allowPartial: Bool
    let reasonCode: String
    let cycleId: String
    let timestamp: Date
    let mode: StrategyMode

    var id: String { intentId }
}

struct StrategyCycleSummary: Identifiable, Equatable {
    let cycleId: String
    let completedAt: Date
    let signalCount: Int
    let targetCount: Int
    let intentCount: Int
    let result: String

    var id: String { cycleId }
}

struct StrategyPersistentState: Codable, Equatable {
    let strategyId: String
    var mode: StrategyMode
    var runtimeState: StrategyRuntimeState
    var health: HealthState
    var lastHeartbeat: Date?
    var parameterVersion: Int
    var parameterValues: [String: String]
    var blocksNewRisk: Bool
    var liveToPaperTransition: LiveToPaperTransition
}

struct LiveAuthorization: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let authorizationId: String
    let strategyId: String
    let allowedMarkets: [String]
    let allowedSymbolsOrUniverse: [String]
    let maximumCapital: Decimal
    let maximumStrategyAllocation: Decimal
    let maximumSinglePositionExposure: Decimal
    let maximumDailyLoss: Decimal
    let maximumDrawdown: Decimal
    let maximumOrderFrequency: Int
    let outsideRegularHoursPermission: Bool
    let parameterVersion: Int
    let validFrom: Date
    let expiresAt: Date
    let enabled: Bool

    var id: String { authorizationId }
}

struct ParameterChangeDecision {
    let change: StrategyParameterChange
    let blocksNewRisk: Bool
    let impactPreview: String
}

struct ModeSelectionResult {
    let accepted: Bool
    let mode: StrategyMode
    let message: String
}

struct PaperCycleResult {
    let cycle: StrategyCycleSummary
    let lastHeartbeat: Date
    let health: HealthState
    let signals: [StrategySignal]
    let targets: [StrategyTarget]
    let intents: [StrategyIntentRecord]
    let messages: [StrategyMessageEnvelope]
}

enum StrategyProtocolMessageTypes {
    static let coreToStrategy: Set<String> = [
        "initialize", "load_parameters", "apply_parameters",
        "market_snapshot", "allocation_budget", "start_cycle",
        "pause", "resume", "shutdown"
    ]
    static let strategyToCore: Set<String> = [
        "ready", "heartbeat", "log", "health", "signal",
        "factor_observation", "target_position", "trade_intent",
        "cycle_complete", "error"
    ]
}
