namespace CytisusTrading.Windows;

public sealed record AppServices(
    IFactorRepository FactorRepository,
    IFactorGovernanceService GovernanceService,
    ISettingsStore SettingsStore,
    IApplicationLogStore LogStore,
    IAuditEventStore AuditStore,
    IMigrationStore MigrationStore)
{
    public static AppServices CreateOfflineFixture()
    {
        var store = new JsonFilePersistentStore(JsonFilePersistentStore.DefaultRootDirectory());
        store.InitializeSchema();
        return new AppServices(
            new FixtureFactorRepository(),
            new FixtureFactorGovernanceService(),
            store,
            store,
            store,
            store);
    }
}
