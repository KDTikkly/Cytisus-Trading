namespace CytisusTrading.Windows;

public static class FoundationSmoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            var store = new JsonFilePersistentStore(rootDirectory);
            store.InitializeSchema();
            if (store.GetSchemaVersion().Version != StoreSchemaVersion.Current.Version)
            {
                return 2;
            }

            var expected = AppSettings.Default with { RiskBudget = 0.42 };
            store.SaveSettings(expected);
            if (store.LoadSettings() != expected)
            {
                return 3;
            }

            store.AppendLog(new ApplicationLogEntry(
                "log-smoke-0001",
                DateTimeOffset.Parse("2026-01-01T00:00:00Z"),
                ApplicationLogLevel.Info,
                "FoundationSmoke",
                "Persistence smoke check",
                "corr-smoke-0001",
                new Dictionary<string, string> { ["fixture_mode"] = "true" }));

            store.AppendAuditEvent(new AuditEvent(
                "audit-smoke-0001",
                DateTimeOffset.Parse("2026-01-01T00:00:00Z"),
                AuditEventCategory.Application,
                "PersistenceSmoke",
                AuditResult.Completed,
                "system",
                "corr-smoke-0001",
                new Dictionary<string, string> { ["fixture_mode"] = "true" }));

            if (store.LoadAuditEvents(10).Count != 1)
            {
                return 4;
            }

            if (new FixtureFactorRepository().LoadFactors().Count == 0)
            {
                return 5;
            }

            return 0;
        }
        catch
        {
            return 1;
        }
    }
}
