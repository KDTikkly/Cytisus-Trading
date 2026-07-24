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
    var cliExecutablePath: String = ""
    var defaultMarket: String = "US"
    var cacheDirectory: String = ""
    var processTimeoutSeconds: Int = 15
    var dataRetentionDays: Int = 90
    var logRetentionDays: Int = 30

    enum CodingKeys: String, CodingKey {
        case fixtureMode = "fixture_mode"
        case strategyMode = "strategy_mode"
        case health
        case riskBudget = "risk_budget"
        case coverageGate = "coverage_gate"
        case maxFactorWeight = "max_factor_weight"
        case cliExecutablePath = "cli_executable_path"
        case defaultMarket = "default_market"
        case cacheDirectory = "cache_directory"
        case processTimeoutSeconds = "process_timeout_seconds"
        case dataRetentionDays = "data_retention_days"
        case logRetentionDays = "log_retention_days"
    }

    init(
        fixtureMode: Bool = true,
        strategyMode: StrategyMode = .paperOnly,
        health: HealthState = .degraded,
        riskBudget: Double = 0.50,
        coverageGate: Double = 0.80,
        maxFactorWeight: Double = 0.35,
        cliExecutablePath: String = "",
        defaultMarket: String = "US",
        cacheDirectory: String = "",
        processTimeoutSeconds: Int = 15,
        dataRetentionDays: Int = 90,
        logRetentionDays: Int = 30
    ) {
        self.fixtureMode = fixtureMode
        self.strategyMode = strategyMode
        self.health = health
        self.riskBudget = riskBudget
        self.coverageGate = coverageGate
        self.maxFactorWeight = maxFactorWeight
        self.cliExecutablePath = cliExecutablePath
        self.defaultMarket = defaultMarket
        self.cacheDirectory = cacheDirectory
        self.processTimeoutSeconds = processTimeoutSeconds
        self.dataRetentionDays = dataRetentionDays
        self.logRetentionDays = logRetentionDays
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fixtureMode = try values.decodeIfPresent(Bool.self, forKey: .fixtureMode) ?? true
        strategyMode = try values.decodeIfPresent(
            StrategyMode.self,
            forKey: .strategyMode
        ) ?? .paperOnly
        health = try values.decodeIfPresent(HealthState.self, forKey: .health) ?? .degraded
        riskBudget = try values.decodeIfPresent(Double.self, forKey: .riskBudget) ?? 0.50
        coverageGate = try values.decodeIfPresent(Double.self, forKey: .coverageGate) ?? 0.80
        maxFactorWeight = try values.decodeIfPresent(
            Double.self,
            forKey: .maxFactorWeight
        ) ?? 0.35
        cliExecutablePath = try values.decodeIfPresent(
            String.self,
            forKey: .cliExecutablePath
        ) ?? ""
        defaultMarket = try values.decodeIfPresent(
            String.self,
            forKey: .defaultMarket
        ) ?? "US"
        cacheDirectory = try values.decodeIfPresent(
            String.self,
            forKey: .cacheDirectory
        ) ?? ""
        processTimeoutSeconds = try values.decodeIfPresent(
            Int.self,
            forKey: .processTimeoutSeconds
        ) ?? 15
        dataRetentionDays = try values.decodeIfPresent(
            Int.self,
            forKey: .dataRetentionDays
        ) ?? 90
        logRetentionDays = try values.decodeIfPresent(
            Int.self,
            forKey: .logRetentionDays
        ) ?? 30
    }
}
