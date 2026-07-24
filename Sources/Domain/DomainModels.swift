import Foundation

enum ProductVersion {
    static let current = "1.1.0"
}

enum StrategyMode: String, Codable, CaseIterable {
    case paperOnly = "PaperOnly"
    case live = "Live"
}

enum HealthState: String, Codable, CaseIterable {
    case healthy = "Healthy"
    case degraded = "Degraded"
    case unhealthy = "Unhealthy"
}

enum FactorState: String, Codable, CaseIterable {
    case candidate = "Candidate"
    case shadow = "Shadow"
    case active = "Active"
    case reduced = "Reduced"
    case probation = "Probation"
    case retired = "Retired"
    case quarantined = "Quarantined"
}

enum ExecutionRecordType: String, Codable, CaseIterable {
    case strategyIntent = "StrategyIntent"
    case riskDecision = "RiskDecision"
    case internalTransfer = "InternalTransfer"
    case brokerOrder = "BrokerOrder"
    case brokerFill = "BrokerFill"
    case virtualAllocation = "VirtualAllocation"
    case allocationShortfall = "AllocationShortfall"
}

struct FactorItem: Identifiable, Codable, Equatable {
    let factorID: String
    let name: String
    let category: String
    var state: FactorState
    var ic: Double
    var ir: Double
    var coverage: Double
    var weight: Double
    var evidenceWindows: Int
    var reason: String

    var id: String { factorID }

    enum CodingKeys: String, CodingKey {
        case factorID = "factor_id"
        case name
        case category
        case state
        case ic
        case ir
        case coverage
        case weight
        case evidenceWindows = "evidence_windows"
        case reason
    }
}

struct AppSettings: Codable, Equatable {
    var fixtureMode: Bool = true
    var strategyMode: StrategyMode = .paperOnly
    var health: HealthState = .degraded
    var riskBudget: Double = 0.50
    var coverageGate: Double = 0.80
    var maxFactorWeight: Double = 0.35

    enum CodingKeys: String, CodingKey {
        case fixtureMode = "fixture_mode"
        case strategyMode = "strategy_mode"
        case health
        case riskBudget = "risk_budget"
        case coverageGate = "coverage_gate"
        case maxFactorWeight = "max_factor_weight"
    }
}
