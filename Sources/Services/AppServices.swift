import Foundation

struct AppServices {
    let factorRepository: FactorRepository
    let governanceService: FactorGovernanceServicing
    let settingsStore: SettingsStore
    let logStore: ApplicationLogStore
    let auditStore: AuditEventStore
    let migrationStore: MigrationStore
    let marketDataCache: MarketDataCache
    let universeService: UniverseServicing
    let fixtureDataService: LongbridgeDataServicing
    let cliAdapter: LongbridgeCLIAdapting
    let marketDataClient: LongbridgeMarketDataClient

    static func offlineFixture() -> AppServices {
        let store = JSONFilePersistentStore(rootURL: JSONFilePersistentStore.defaultRootURL())
        try? store.initializeSchema()
        let settings = (try? store.loadSettings()) ?? AppSettings()
        let cacheURL = settings.cacheDirectory.isEmpty
            ? JSONMarketDataCache.defaultRootURL()
            : URL(fileURLWithPath: settings.cacheDirectory, isDirectory: true)
        let cache = JSONMarketDataCache(rootURL: cacheURL)
        let universeService = UniverseService()
        let cliAdapter = LongbridgeCLIAdapter(runner: LongbridgeProcessRunner())

        return AppServices(
            factorRepository: FixtureFactorRepository(),
            governanceService: FixtureFactorGovernanceService(),
            settingsStore: store,
            logStore: store,
            auditStore: store,
            migrationStore: store,
            marketDataCache: cache,
            universeService: universeService,
            fixtureDataService: FixtureLongbridgeDataService(
                cache: cache,
                universeService: universeService
            ),
            cliAdapter: cliAdapter,
            marketDataClient: CLILongbridgeMarketDataClient(adapter: cliAdapter)
        )
    }
}
