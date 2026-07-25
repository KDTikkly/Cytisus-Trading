import Foundation

struct StoreSchemaVersion: Codable, Equatable {
    static let current = StoreSchemaVersion(version: 3)

    let version: Int
}

struct MigrationRecord: Codable, Identifiable {
    let id: String
    let fromVersion: Int
    let toVersion: Int
    let appliedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fromVersion = "from_version"
        case toVersion = "to_version"
        case appliedAt = "applied_at"
    }
}

protocol SettingsStore {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
}

protocol ApplicationLogStore {
    func appendLog(_ entry: ApplicationLogEntry) throws
    func loadLogs(limit: Int) throws -> [ApplicationLogEntry]
}

protocol AuditEventStore {
    func appendAuditEvent(_ event: AuditEvent) throws
    func loadAuditEvents(limit: Int) throws -> [AuditEvent]
}

protocol MigrationStore {
    func initializeSchema() throws
    func schemaVersion() throws -> StoreSchemaVersion
    func migrationRecords() throws -> [MigrationRecord]
}

protocol FactorRepository: AnyObject {
    func loadFactors() throws -> [FactorItem]
    func saveFactors(_ factors: [FactorItem]) throws
    func resetToFixtures() throws -> [FactorItem]
}

protocol MarketDataCache {
    func storeHistoricalBars(_ series: HistoricalBarSeries) throws -> CacheWriteResult
    func storeCurrentSnapshot(_ snapshot: CurrentMarketSnapshot) throws -> CacheWriteResult
    func storeUniverseSnapshot(_ snapshot: UniverseSnapshot) throws -> CacheWriteResult
    func loadHistoricalBars(
        symbol: String,
        interval: String,
        start: Date,
        end: Date
    ) throws -> HistoricalBarSeries?
    func loadUniverseSnapshot(date: String) throws -> UniverseSnapshot?
    func cacheSizeBytes() throws -> Int64
}

protocol StrategyStateStore {
    func loadStrategyManifests() throws -> [StrategyManifest]
    func saveStrategyManifest(_ manifest: StrategyManifest) throws
    func loadStrategyStates() throws -> [StrategyPersistentState]
    func saveStrategyState(_ state: StrategyPersistentState) throws
    func loadParameterChanges(
        strategyId: String,
        limit: Int
    ) throws -> [StrategyParameterChange]
    func appendParameterChange(_ change: StrategyParameterChange) throws
    func loadLiveAuthorizations() throws -> [LiveAuthorization]
    func saveLiveAuthorization(_ authorization: LiveAuthorization) throws
}
