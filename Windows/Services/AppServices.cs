namespace CytisusTrading.Windows;

public sealed record AppServices(
    IFactorRepository FactorRepository,
    IFactorGovernanceService GovernanceService,
    ISettingsStore SettingsStore,
    IApplicationLogStore LogStore,
    IAuditEventStore AuditStore,
    IMigrationStore MigrationStore,
    IMarketDataCache MarketDataCache,
    IUniverseService UniverseService,
    ILongbridgeDataService FixtureDataService,
    ILongbridgeCliAdapter CliAdapter,
    ILongbridgeMarketDataClient MarketDataClient,
    IStrategyStateStore StrategyStore,
    IStrategyRegistryService StrategyRegistry,
    IParameterGovernanceService ParameterGovernance,
    IStrategyModeService StrategyModeService,
    StrategyMessageCodec StrategyMessageCodec,
    ILiveBrokerAdapter LiveBrokerAdapter,
    StrategyIntentRouter StrategyIntentRouter,
    IOfficialStrategyRuntime OfficialStrategyRuntime,
    IFactorResearchStore FactorResearchStore,
    IResearchFixtureService ResearchFixtures,
    IFactorDSLService FactorDSL,
    IFactorSearchService FactorSearch,
    IFactorLifecycleService FactorLifecycle,
    IRegimeEngine RegimeEngine,
    IDynamicCapitalAllocator CapitalAllocator,
    IExecutionStore ExecutionStore,
    ExecutionFixtureService ExecutionFixtures,
    IInternalNettingService InternalNetting,
    IPartialFillAllocator FillAllocator,
    IPaperBroker PaperBroker,
    ILongbridgeLiveBrokerAdapter LiveExecutionAdapter,
    VirtualLedgerService VirtualLedger,
    ReconciliationService Reconciliation,
    ExecutionGateway ExecutionGateway,
    IModelProviderStore ModelProviderStore,
    IModelSecretStore ModelSecretStore,
    IModelProviderClient ModelProviderClient,
    ModelProviderManager ModelProviderManager,
    ModelLongbridgeCoordinator ModelLongbridgeCoordinator)
{
    public static AppServices CreateOfflineFixture()
    {
        var store = new JsonFilePersistentStore(JsonFilePersistentStore.DefaultRootDirectory());
        store.InitializeSchema();
        var settings = store.LoadSettings();
        var cacheDirectory = string.IsNullOrWhiteSpace(settings.CacheDirectory)
            ? JsonMarketDataCache.DefaultDirectory()
            : settings.CacheDirectory;
        var cache = new JsonMarketDataCache(cacheDirectory);
        var universeService = new UniverseService();
        var processRunner = new LongbridgeProcessRunner();
        var cliAdapter = new LongbridgeCliAdapter(processRunner);
        var strategyCodec = new StrategyMessageCodec();
        var liveAdapter = new RejectingLiveBrokerAdapter();
        var intentRouter = new StrategyIntentRouter();
        var factorDSL = new FactorDSLService();
        var researchFixtures = new ResearchFixtureService();
        var executionFixtures = new ExecutionFixtureService();
        var internalNetting = new InternalNettingService();
        var fillAllocator = new PartialFillAllocator();
        var paperBroker = new DeterministicPaperBroker();
        var liveExecution = new LongbridgeLiveBrokerAdapter(
            new LongbridgeLiveCommandFactory());
        var virtualLedger = new VirtualLedgerService();
        var reconciliation = new ReconciliationService();
        var modelSecretStore = new DpapiModelSecretStore();
        var modelProviderClient = new HttpModelProviderClient();
        var modelProviderManager = new ModelProviderManager(
            store,
            modelSecretStore,
            modelProviderClient);
        var modelLongbridgeCoordinator = new ModelLongbridgeCoordinator(
            new FixtureReadOnlyLongbridgeToolGateway(
                new FixtureLongbridgeDataService(cache, universeService)));
        var executionGateway = new ExecutionGateway(
            store,
            store,
            internalNetting,
            fillAllocator,
            paperBroker,
            liveExecution,
            virtualLedger,
            reconciliation);
        return new AppServices(
            new FixtureFactorRepository(),
            new FixtureFactorGovernanceService(),
            store,
            store,
            store,
            store,
            cache,
            universeService,
            new FixtureLongbridgeDataService(cache, universeService),
            cliAdapter,
            new LongbridgeMarketDataClient(cliAdapter),
            store,
            new StrategyRegistryService(),
            new ParameterGovernanceService(),
            new StrategyModeService(),
            strategyCodec,
            liveAdapter,
            intentRouter,
            new OfficialFixtureStrategyRuntime(
                strategyCodec,
                intentRouter,
                liveAdapter),
            store,
            researchFixtures,
            factorDSL,
            new FactorSearchService(factorDSL, store),
            new FactorLifecycleService(),
            new RegimeEngine(),
            new DynamicCapitalAllocator(),
            store,
            executionFixtures,
            internalNetting,
            fillAllocator,
            paperBroker,
            liveExecution,
            virtualLedger,
            reconciliation,
            executionGateway,
            store,
            modelSecretStore,
            modelProviderClient,
            modelProviderManager,
            modelLongbridgeCoordinator);
    }
}
