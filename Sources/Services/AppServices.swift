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
    let strategyStore: StrategyStateStore
    let strategyRegistry: StrategyRegistryServicing
    let parameterGovernance: ParameterGovernanceServicing
    let strategyModeService: StrategyModeServicing
    let strategyMessageCodec: StrategyMessageCodec
    let liveBrokerAdapter: LiveBrokerAdapting
    let strategyIntentRouter: StrategyIntentRouter
    let officialStrategyRuntime: OfficialStrategyRuntimeServicing
    let factorResearchStore: FactorResearchStore
    let researchFixtures: ResearchFixtureService
    let factorDSL: FactorDSLService
    let factorSearch: FactorSearchService
    let factorLifecycle: FactorLifecycleService
    let regimeEngine: RegimeEngine
    let capitalAllocator: DynamicCapitalAllocator

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
        let strategyCodec = StrategyMessageCodec()
        let liveAdapter = RejectingLiveBrokerAdapter()
        let router = StrategyIntentRouter()
        let researchFixtures = ResearchFixtureService()
        let factorDSL = FactorDSLService()

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
            marketDataClient: CLILongbridgeMarketDataClient(adapter: cliAdapter),
            strategyStore: store,
            strategyRegistry: StrategyRegistryService(),
            parameterGovernance: ParameterGovernanceService(),
            strategyModeService: StrategyModeService(),
            strategyMessageCodec: strategyCodec,
            liveBrokerAdapter: liveAdapter,
            strategyIntentRouter: router,
            officialStrategyRuntime: OfficialFixtureStrategyRuntime(
                codec: strategyCodec,
                router: router,
                liveAdapter: liveAdapter
            ),
            factorResearchStore: store,
            researchFixtures: researchFixtures,
            factorDSL: factorDSL,
            factorSearch: FactorSearchService(
                dsl: factorDSL,
                store: store
            ),
            factorLifecycle: FactorLifecycleService(),
            regimeEngine: RegimeEngine(),
            capitalAllocator: DynamicCapitalAllocator()
        )
    }
}
