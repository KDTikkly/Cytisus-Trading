namespace CytisusTrading.Windows;

public sealed record StoreSchemaVersion(int Version)
{
    public static StoreSchemaVersion Current { get; } = new(3);
}

public sealed record MigrationRecord(
    string Id,
    int FromVersion,
    int ToVersion,
    DateTimeOffset AppliedAt);

public interface ISettingsStore
{
    AppSettings LoadSettings();
    void SaveSettings(AppSettings settings);
}

public interface IApplicationLogStore
{
    void AppendLog(ApplicationLogEntry entry);
    IReadOnlyList<ApplicationLogEntry> LoadLogs(int limit);
}

public interface IAuditEventStore
{
    void AppendAuditEvent(AuditEvent auditEvent);
    IReadOnlyList<AuditEvent> LoadAuditEvents(int limit);
}

public interface IMigrationStore
{
    void InitializeSchema();
    StoreSchemaVersion GetSchemaVersion();
    IReadOnlyList<MigrationRecord> GetMigrationRecords();
}

public interface IFactorRepository
{
    IReadOnlyList<FactorItem> LoadFactors();
    void SaveFactors(IReadOnlyList<FactorItem> factors);
    IReadOnlyList<FactorItem> ResetToFixtures();
}

public interface IMarketDataCache
{
    CacheWriteResult StoreHistoricalBars(HistoricalBarSeries series);
    CacheWriteResult StoreCurrentSnapshot(CurrentMarketSnapshot snapshot);
    CacheWriteResult StoreUniverseSnapshot(UniverseSnapshot snapshot);
    HistoricalBarSeries? LoadHistoricalBars(
        string symbol,
        string interval,
        DateTimeOffset start,
        DateTimeOffset end);
    UniverseSnapshot? LoadUniverseSnapshot(string date);
    long CacheSizeBytes();
}

public interface IStrategyStateStore
{
    IReadOnlyList<StrategyManifest> LoadStrategyManifests();
    void SaveStrategyManifest(StrategyManifest manifest);
    IReadOnlyList<StrategyPersistentState> LoadStrategyStates();
    void SaveStrategyState(StrategyPersistentState state);
    IReadOnlyList<StrategyParameterChange> LoadParameterChanges(
        string strategyId,
        int limit);
    void AppendParameterChange(StrategyParameterChange change);
    IReadOnlyList<LiveAuthorization> LoadLiveAuthorizations();
    void SaveLiveAuthorization(LiveAuthorization authorization);
}
