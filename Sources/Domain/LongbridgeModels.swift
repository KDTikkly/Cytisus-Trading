import Foundation

enum LongbridgeStatusState: String, Codable, CaseIterable {
    case missing = "Missing"
    case unauthenticated = "Unauthenticated"
    case degraded = "Degraded"
    case ready = "Ready"
}

enum LongbridgeOperation: String, Codable, CaseIterable {
    case status = "Status"
    case connectivity = "Connectivity"
    case historicalBars = "HistoricalBars"
    case currentSnapshot = "CurrentSnapshot"
    case marketStatus = "MarketStatus"
    case securityList = "SecurityList"
    case brokerPositions = "BrokerPositions"
}

enum CLICallCategory: String, Codable {
    case readOnlyData = "ReadOnlyData"
}

enum UniverseDisposition: String, Codable {
    case included = "Included"
    case excluded = "Excluded"
    case reduceOnly = "ReduceOnly"
}

struct CLICommandTemplate: Codable, Equatable {
    let operation: LongbridgeOperation
    let arguments: [String]
}

struct LongbridgeCapabilities: Codable, Equatable {
    let schemaVersion: Int
    let fixtureMode: Bool
    let cliVersion: String
    let sourceVersion: String
    var statusState: LongbridgeStatusState
    let supportsJSON: Bool
    let commands: [CLICommandTemplate]
    let dataPermissions: [String]
    let discoveredAt: Date
    let liveExecutionAvailable: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtureMode = "fixture_mode"
        case cliVersion = "cli_version"
        case sourceVersion = "source_version"
        case statusState = "status_state"
        case supportsJSON = "supports_json"
        case commands
        case dataPermissions = "data_permissions"
        case discoveredAt = "discovered_at"
        case liveExecutionAvailable = "live_execution_available"
        case message
    }
}

struct AuthorizationStatusSummary: Codable, Equatable {
    let schemaVersion: Int
    let state: LongbridgeStatusState
    let authenticated: Bool
    let permissions: [String]
    let checkedAt: Date
    let message: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state
        case authenticated
        case permissions
        case checkedAt = "checked_at"
        case message
    }
}

struct ConnectivitySummary: Codable, Equatable {
    let schemaVersion: Int
    let state: LongbridgeStatusState
    let reachable: Bool
    let checkedAt: Date
    let latencyMS: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state
        case reachable
        case checkedAt = "checked_at"
        case latencyMS = "latency_ms"
        case message
    }
}

struct MarketBar: Codable, Equatable {
    let eventTime: Date
    let availableTime: Date
    let collectedAt: Date
    let sourceVersion: String
    let adjustmentMode: String
    let dataHash: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    enum CodingKeys: String, CodingKey {
        case eventTime = "event_time"
        case availableTime = "available_time"
        case collectedAt = "collected_at"
        case sourceVersion = "source_version"
        case adjustmentMode = "adjustment_mode"
        case dataHash = "data_hash"
        case open
        case high
        case low
        case close
        case volume
    }
}

struct HistoricalBarSeries: Codable, Equatable {
    let schemaVersion: Int
    let symbol: String
    let interval: String
    let start: Date
    let end: Date
    let bars: [MarketBar]
    let dataHash: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case symbol
        case interval
        case start
        case end
        case bars
        case dataHash = "data_hash"
    }
}

struct CurrentMarketSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let symbol: String
    let eventTime: Date
    let availableTime: Date
    let collectedAt: Date
    let sourceVersion: String
    let adjustmentMode: String
    let dataHash: String
    let last: Double
    let open: Double
    let high: Double
    let low: Double
    let previousClose: Double
    let volume: Double
    let currency: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case symbol
        case eventTime = "event_time"
        case availableTime = "available_time"
        case collectedAt = "collected_at"
        case sourceVersion = "source_version"
        case adjustmentMode = "adjustment_mode"
        case dataHash = "data_hash"
        case last
        case open
        case high
        case low
        case previousClose = "previous_close"
        case volume
        case currency
    }
}

struct MarketStatusSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let market: String
    let session: String
    let eventTime: Date
    let availableTime: Date
    let collectedAt: Date
    let sourceVersion: String
    let adjustmentMode: String
    let dataHash: String
    let nextOpen: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case market
        case session
        case eventTime = "event_time"
        case availableTime = "available_time"
        case collectedAt = "collected_at"
        case sourceVersion = "source_version"
        case adjustmentMode = "adjustment_mode"
        case dataHash = "data_hash"
        case nextOpen = "next_open"
    }
}

struct SecurityReference: Codable, Equatable {
    let symbol: String
    let name: String
    let industry: String
    let tradable: Bool
    let lastPrice: Double
    let averageDailyVolume: Double
    let averageDailyValue: Double
    let listingAgeDays: Int
    let historyCoverageDays: Int
    let suspended: Bool
    let delisted: Bool
    let abnormal: Bool
    let strategyEligible: Bool

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case industry
        case tradable
        case lastPrice = "last_price"
        case averageDailyVolume = "average_daily_volume"
        case averageDailyValue = "average_daily_value"
        case listingAgeDays = "listing_age_days"
        case historyCoverageDays = "history_coverage_days"
        case suspended
        case delisted
        case abnormal
        case strategyEligible = "strategy_eligible"
    }
}

struct SecurityListSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let market: String
    let collectedAt: Date
    let sourceVersion: String
    let dataHash: String
    let securities: [SecurityReference]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case market
        case collectedAt = "collected_at"
        case sourceVersion = "source_version"
        case dataHash = "data_hash"
        case securities
    }
}

struct BrokerPosition: Codable, Equatable {
    let symbol: String
    let quantity: Double
}

struct BrokerPositionSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let collectedAt: Date
    let sourceVersion: String
    let dataHash: String
    let positions: [BrokerPosition]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case collectedAt = "collected_at"
        case sourceVersion = "source_version"
        case dataHash = "data_hash"
        case positions
    }
}

struct UniverseConfiguration: Codable, Equatable {
    let schemaVersion: Int
    let market: String
    let minimumPrice: Double
    let minimumAverageDailyVolume: Double
    let minimumListingAgeDays: Int
    let minimumHistoryCoverageDays: Int
    let ruleVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case market
        case minimumPrice = "minimum_price"
        case minimumAverageDailyVolume = "minimum_average_daily_volume"
        case minimumListingAgeDays = "minimum_listing_age_days"
        case minimumHistoryCoverageDays = "minimum_history_coverage_days"
        case ruleVersion = "rule_version"
    }
}

struct UniverseLiquidityMetrics: Codable, Equatable {
    let lastPrice: Double
    let averageDailyVolume: Double
    let averageDailyValue: Double

    enum CodingKeys: String, CodingKey {
        case lastPrice = "last_price"
        case averageDailyVolume = "average_daily_volume"
        case averageDailyValue = "average_daily_value"
    }
}

struct UniverseDataCoverage: Codable, Equatable {
    let listingAgeDays: Int
    let historyCoverageDays: Int

    enum CodingKeys: String, CodingKey {
        case listingAgeDays = "listing_age_days"
        case historyCoverageDays = "history_coverage_days"
    }
}

struct UniverseEntry: Codable, Equatable, Identifiable {
    let date: String
    let symbol: String
    let included: Bool
    let disposition: UniverseDisposition
    let reason: String
    let liquidityMetrics: UniverseLiquidityMetrics
    let dataCoverage: UniverseDataCoverage
    let industry: String
    let ruleVersion: String
    let sourceVersion: String

    var id: String { "\(date):\(symbol)" }
    var dispositionLabel: String {
        disposition == .reduceOnly ? "Reduce Only" : disposition.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case date
        case symbol
        case included
        case disposition
        case reason
        case liquidityMetrics = "liquidity_metrics"
        case dataCoverage = "data_coverage"
        case industry
        case ruleVersion = "rule_version"
        case sourceVersion = "source_version"
    }
}

struct UniverseSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let date: String
    let market: String
    let ruleVersion: String
    let sourceVersion: String
    let createdAt: Date
    let entries: [UniverseEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case market
        case ruleVersion = "rule_version"
        case sourceVersion = "source_version"
        case createdAt = "created_at"
        case entries
    }
}

struct LongbridgeDataSnapshot {
    let capabilities: LongbridgeCapabilities
    let authorization: AuthorizationStatusSummary
    let connectivity: ConnectivitySummary
    let historicalBars: HistoricalBarSeries
    let currentSnapshot: CurrentMarketSnapshot
    let marketStatus: MarketStatusSnapshot
    let securityList: SecurityListSnapshot
    let brokerPositions: BrokerPositionSnapshot
    let universe: UniverseSnapshot
}

struct CLICommand: Equatable {
    let executableURL: URL
    let arguments: [String]
    let category: CLICallCategory
    let operation: LongbridgeOperation
}

struct CLIProcessResult: Equatable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    let timedOut: Bool
    let cancelled: Bool
    let outputTruncated: Bool
    let duration: TimeInterval

    var succeeded: Bool {
        exitCode == 0 && !timedOut && !cancelled
    }
}

struct LongbridgeInspection {
    let state: LongbridgeStatusState
    let executableURL: URL?
    let cliVersion: String
    let checkedAt: Date
    let dataPermissions: [String]
    let message: String
    let capabilities: LongbridgeCapabilities?
}

enum CacheWriteResult {
    case created
    case updated
    case unchanged
}
