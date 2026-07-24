namespace CytisusTrading.Windows;

public sealed record StoreSchemaVersion(int Version)
{
    public static StoreSchemaVersion Current { get; } = new(1);
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
