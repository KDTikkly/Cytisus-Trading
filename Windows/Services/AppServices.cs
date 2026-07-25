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
    IOfficialStrategyRuntime OfficialStrategyRuntime)
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
        var cliAdapter = new LongbridgeCliAdapter(new LongbridgeProcessRunner());
        var strategyCodec = new StrategyMessageCodec();
        var liveAdapter = new RejectingLiveBrokerAdapter();
        var intentRouter = new StrategyIntentRouter();
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
                liveAdapter));
    }
}
