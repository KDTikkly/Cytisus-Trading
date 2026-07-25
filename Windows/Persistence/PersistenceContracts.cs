namespace CytisusTrading.Windows;

public sealed record StoreSchemaVersion(int Version)
{
    public static StoreSchemaVersion Current { get; } = new(7);
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

public interface IFactorResearchStore
{
    IReadOnlyList<FactorDefinition> LoadFactorDefinitions();
    void SaveFactorDefinitions(IReadOnlyList<FactorDefinition> definitions);
    IReadOnlyList<FactorTrial> LoadFactorTrials(int limit);
    void AppendFactorTrial(FactorTrial trial);
}

public interface IExecutionStore
{
    ExecutionStateSnapshot LoadExecutionState();
    void SaveExecutionState(ExecutionStateSnapshot state);
}

public interface IModelProviderStore
{
    IReadOnlyList<ModelProviderProfile> LoadModelProviders();
    void SaveModelProviders(IReadOnlyList<ModelProviderProfile> providers);
    IReadOnlyList<ProviderModelRecord> LoadProviderModels();
    void SaveProviderModels(IReadOnlyList<ProviderModelRecord> models);
    IReadOnlyList<ModelRoleAssignment> LoadModelRoleAssignments();
    void SaveModelRoleAssignments(IReadOnlyList<ModelRoleAssignment> assignments);
    IReadOnlyList<ProviderTestEvent> LoadProviderTestEvents(int limit);
    void AppendProviderTestEvent(ProviderTestEvent testEvent);
}

public interface IModelSecretStore
{
    void Save(string secret, string reference);
    void Replace(string secret, string reference);
    string Retrieve(string reference);
    void Delete(string reference);
}

public interface ILocalStudioStore
{
    LocalStudioState LoadLocalStudioState();
    void SaveLocalStudioState(LocalStudioState state);
}
