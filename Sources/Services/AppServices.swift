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
    let executionStore: ExecutionStore
    let executionFixtures: ExecutionFixtureService
    let internalNetting: InternalNettingService
    let fillAllocator: PartialFillAllocator
    let paperBroker: DeterministicPaperBroker
    let liveExecutionAdapter: LongbridgeLiveBrokerAdapter
    let virtualLedger: VirtualLedgerService
    let reconciliation: ReconciliationService
    let executionGateway: ExecutionGateway
    let modelProviderStore: ModelProviderStore
    let modelSecretStore: ModelSecretStore
    let modelProviderClient: ModelProviderClient
    let modelProviderManager: ModelProviderManager
    let modelLongbridgeCoordinator: ModelLongbridgeCoordinator
    let localStudioStore: LocalStudioStore
    let localStudioService: LocalStudioService
    let quantWorkerClient: LocalQuantWorkerClient

    static func offlineFixture() -> AppServices {
        let store = JSONFilePersistentStore(rootURL: JSONFilePersistentStore.defaultRootURL())
        try? store.initializeSchema()
        let settings = (try? store.loadSettings()) ?? AppSettings()
        let cacheURL = settings.cacheDirectory.isEmpty
            ? JSONMarketDataCache.defaultRootURL()
            : URL(fileURLWithPath: settings.cacheDirectory, isDirectory: true)
        let cache = JSONMarketDataCache(rootURL: cacheURL)
        let universeService = UniverseService()
        let processRunner = LongbridgeProcessRunner()
        let cliAdapter = LongbridgeCLIAdapter(runner: processRunner)
        let strategyCodec = StrategyMessageCodec()
        let liveAdapter = RejectingLiveBrokerAdapter()
        let router = StrategyIntentRouter()
        let researchFixtures = ResearchFixtureService()
        let factorDSL = FactorDSLService()
        let executionFixtures = ExecutionFixtureService()
        let internalNetting = InternalNettingService()
        let fillAllocator = PartialFillAllocator()
        let paperBroker = DeterministicPaperBroker()
        let liveExecution = LongbridgeLiveBrokerAdapter(
            commandFactory: LongbridgeLiveCommandFactory()
        )
        let virtualLedger = VirtualLedgerService()
        let reconciliation = ReconciliationService()
        let modelSecretStore = KeychainModelSecretStore()
        let modelProviderClient = HTTPModelProviderClient()
        let modelProviderManager = ModelProviderManager(
            store: store,
            secrets: modelSecretStore,
            client: modelProviderClient
        )
        let modelLongbridgeCoordinator = ModelLongbridgeCoordinator(
            gateway: FixtureReadOnlyLongbridgeToolGateway(
                fixtures: FixtureLongbridgeDataService(
                    cache: cache,
                    universeService: universeService
                )
            )
        )
        let localStudioService = LocalStudioService(
            store: store,
            auditStore: store
        )
        let executionGateway = ExecutionGateway(
            store: store,
            auditStore: store,
            netting: internalNetting,
            allocator: fillAllocator,
            paperBroker: paperBroker,
            liveBroker: liveExecution,
            ledger: virtualLedger,
            reconciliation: reconciliation
        )

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
            capitalAllocator: DynamicCapitalAllocator(),
            executionStore: store,
            executionFixtures: executionFixtures,
            internalNetting: internalNetting,
            fillAllocator: fillAllocator,
            paperBroker: paperBroker,
            liveExecutionAdapter: liveExecution,
            virtualLedger: virtualLedger,
            reconciliation: reconciliation,
            executionGateway: executionGateway,
            modelProviderStore: store,
            modelSecretStore: modelSecretStore,
            modelProviderClient: modelProviderClient,
            modelProviderManager: modelProviderManager,
            modelLongbridgeCoordinator: modelLongbridgeCoordinator,
            localStudioStore: store,
            localStudioService: localStudioService,
            quantWorkerClient: ProcessLocalQuantWorkerClient()
        )
    }
}
