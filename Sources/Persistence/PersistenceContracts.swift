import Foundation

struct StoreSchemaVersion: Codable, Equatable {
    static let current = StoreSchemaVersion(version: 1)

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
