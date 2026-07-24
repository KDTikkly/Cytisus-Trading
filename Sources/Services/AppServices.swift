import Foundation

struct AppServices {
    let factorRepository: FactorRepository
    let governanceService: FactorGovernanceServicing
    let settingsStore: SettingsStore
    let logStore: ApplicationLogStore
    let auditStore: AuditEventStore
    let migrationStore: MigrationStore

    static func offlineFixture() -> AppServices {
        let store = JSONFilePersistentStore(rootURL: JSONFilePersistentStore.defaultRootURL())
        try? store.initializeSchema()

        return AppServices(
            factorRepository: FixtureFactorRepository(),
            governanceService: FixtureFactorGovernanceService(),
            settingsStore: store,
            logStore: store,
            auditStore: store,
            migrationStore: store
        )
    }
}
