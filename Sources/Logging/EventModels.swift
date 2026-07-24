import Foundation

enum ApplicationLogLevel: String, Codable {
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"
}

struct ApplicationLogEntry: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let severity: ApplicationLogLevel
    let module: String
    let message: String
    let correlationID: String?
    let context: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case severity
        case module
        case message
        case correlationID = "correlation_id"
        case context
    }
}

enum AuditEventCategory: String, Codable {
    case application = "Application"
    case settings = "Settings"
    case strategyLifecycle = "StrategyLifecycle"
    case factorLifecycle = "FactorLifecycle"
    case riskRejection = "RiskRejection"
    case liveAuthorization = "LiveAuthorization"
    case strategyIntent = "StrategyIntent"
    case riskDecision = "RiskDecision"
    case internalTransfer = "InternalTransfer"
    case brokerOrder = "BrokerOrder"
    case brokerFill = "BrokerFill"
    case virtualAllocation = "VirtualAllocation"
    case allocationShortfall = "AllocationShortfall"
    case reconciliation = "Reconciliation"
}

enum AuditResult: String, Codable {
    case accepted = "Accepted"
    case rejected = "Rejected"
    case completed = "Completed"
    case failed = "Failed"
}

struct AuditEvent: Codable, Identifiable {
    let schemaVersion: Int = 1
    let id: String
    let occurredAt: Date
    let category: AuditEventCategory
    let action: String
    let result: AuditResult
    let actor: String
    let correlationID: String
    let context: [String: String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id = "event_id"
        case occurredAt = "occurred_at"
        case category
        case action
        case result
        case actor
        case correlationID = "correlation_id"
        case context
    }
}
