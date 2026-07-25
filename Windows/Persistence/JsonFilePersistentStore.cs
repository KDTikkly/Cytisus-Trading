using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public sealed class JsonFilePersistentStore :
    ISettingsStore,
    IApplicationLogStore,
    IAuditEventStore,
    IMigrationStore,
    IStrategyStateStore,
    IFactorResearchStore
{
    private readonly string _rootDirectory;
    private readonly object _gate = new();
    private readonly JsonSerializerOptions _documentOptions;
    private readonly JsonSerializerOptions _lineOptions;

    private string SettingsPath => Path.Combine(_rootDirectory, "settings.json");
    private string SchemaPath => Path.Combine(_rootDirectory, "schema-version.json");
    private string MigrationsPath => Path.Combine(_rootDirectory, "migrations.json");
    private string LogsPath => Path.Combine(_rootDirectory, "application-logs.ndjson");
    private string AuditPath => Path.Combine(_rootDirectory, "audit-events.ndjson");
    private string StrategyManifestsPath =>
        Path.Combine(_rootDirectory, "strategy-manifests.json");
    private string StrategyStatesPath =>
        Path.Combine(_rootDirectory, "strategy-states.json");
    private string ParameterChangesPath =>
        Path.Combine(_rootDirectory, "parameter-changes.ndjson");
    private string LiveAuthorizationsPath =>
        Path.Combine(_rootDirectory, "live-authorizations.json");
    private string FactorDefinitionsPath =>
        Path.Combine(_rootDirectory, "factor-definitions.json");
    private string FactorTrialsPath =>
        Path.Combine(_rootDirectory, "factor-trials.ndjson");

    public JsonFilePersistentStore(string rootDirectory)
    {
        _rootDirectory = rootDirectory;
        _documentOptions = CreateOptions(writeIndented: true);
        _lineOptions = CreateOptions(writeIndented: false);
    }

    public static string DefaultRootDirectory()
    {
        var baseDirectory = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(baseDirectory, "Cytisus-Trading");
    }

    public void InitializeSchema()
    {
        lock (_gate)
        {
            Directory.CreateDirectory(_rootDirectory);
            if (!File.Exists(SchemaPath))
            {
                WriteDocument(SchemaPath, StoreSchemaVersion.Current);
                WriteDocument(MigrationsPath, Array.Empty<MigrationRecord>());
                return;
            }

            var existing = ReadDocument<StoreSchemaVersion>(SchemaPath);
            if (existing.Version > StoreSchemaVersion.Current.Version)
            {
                throw new InvalidOperationException(
                    $"Unsupported store schema version {existing.Version}.");
            }

            if (existing.Version == StoreSchemaVersion.Current.Version)
            {
                return;
            }

            var migrations = File.Exists(MigrationsPath)
                ? ReadDocument<List<MigrationRecord>>(MigrationsPath)
                : new List<MigrationRecord>();
            migrations.Add(new MigrationRecord(
                Guid.NewGuid().ToString("D"),
                existing.Version,
                StoreSchemaVersion.Current.Version,
                DateTimeOffset.UtcNow));
            WriteDocument(MigrationsPath, migrations);
            WriteDocument(SchemaPath, StoreSchemaVersion.Current);
        }
    }

    public StoreSchemaVersion GetSchemaVersion()
    {
        lock (_gate)
        {
            return ReadDocument<StoreSchemaVersion>(SchemaPath);
        }
    }

    public IReadOnlyList<MigrationRecord> GetMigrationRecords()
    {
        lock (_gate)
        {
            return File.Exists(MigrationsPath)
                ? ReadDocument<List<MigrationRecord>>(MigrationsPath)
                : Array.Empty<MigrationRecord>();
        }
    }

    public AppSettings LoadSettings()
    {
        lock (_gate)
        {
            return File.Exists(SettingsPath)
                ? ReadDocument<AppSettings>(SettingsPath)
                : AppSettings.Default;
        }
    }

    public void SaveSettings(AppSettings settings)
    {
        lock (_gate)
        {
            Directory.CreateDirectory(_rootDirectory);
            WriteDocument(SettingsPath, settings);
        }
    }

    public void AppendLog(ApplicationLogEntry entry)
    {
        AppendLine(LogsPath, entry);
    }

    public IReadOnlyList<ApplicationLogEntry> LoadLogs(int limit)
    {
        lock (_gate)
        {
            if (!File.Exists(LogsPath))
            {
                return Array.Empty<ApplicationLogEntry>();
            }

            return File.ReadLines(LogsPath, Encoding.UTF8)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .TakeLast(Math.Max(0, limit))
                .Select(line => JsonSerializer.Deserialize<ApplicationLogEntry>(line, _lineOptions)
                    ?? throw new InvalidDataException("Invalid application-log JSON line."))
                .ToArray();
        }
    }

    public void AppendAuditEvent(AuditEvent auditEvent)
    {
        AppendLine(AuditPath, auditEvent);
    }

    public IReadOnlyList<AuditEvent> LoadAuditEvents(int limit)
    {
        lock (_gate)
        {
            if (!File.Exists(AuditPath))
            {
                return Array.Empty<AuditEvent>();
            }

            return File.ReadLines(AuditPath, Encoding.UTF8)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .TakeLast(Math.Max(0, limit))
                .Select(line => JsonSerializer.Deserialize<AuditEvent>(line, _lineOptions)
                    ?? throw new InvalidDataException("Invalid audit-event JSON line."))
                .ToArray();
        }
    }

    public IReadOnlyList<StrategyManifest> LoadStrategyManifests()
    {
        lock (_gate)
        {
            return File.Exists(StrategyManifestsPath)
                ? ReadDocument<List<StrategyManifest>>(StrategyManifestsPath)
                : Array.Empty<StrategyManifest>();
        }
    }

    public void SaveStrategyManifest(StrategyManifest manifest)
    {
        lock (_gate)
        {
            var manifests = File.Exists(StrategyManifestsPath)
                ? ReadDocument<List<StrategyManifest>>(StrategyManifestsPath)
                : new List<StrategyManifest>();
            var existingIndex = manifests.FindIndex(item =>
                string.Equals(
                    item.StrategyId,
                    manifest.StrategyId,
                    StringComparison.Ordinal));
            if (existingIndex >= 0)
            {
                manifests[existingIndex] = manifest;
            }
            else
            {
                manifests.Add(manifest);
            }
            WriteDocument(StrategyManifestsPath, manifests);
        }
    }

    public IReadOnlyList<StrategyPersistentState> LoadStrategyStates()
    {
        lock (_gate)
        {
            return File.Exists(StrategyStatesPath)
                ? ReadDocument<List<StrategyPersistentState>>(StrategyStatesPath)
                : Array.Empty<StrategyPersistentState>();
        }
    }

    public void SaveStrategyState(StrategyPersistentState state)
    {
        lock (_gate)
        {
            var states = File.Exists(StrategyStatesPath)
                ? ReadDocument<List<StrategyPersistentState>>(StrategyStatesPath)
                : new List<StrategyPersistentState>();
            var existingIndex = states.FindIndex(item =>
                string.Equals(
                    item.StrategyId,
                    state.StrategyId,
                    StringComparison.Ordinal));
            if (existingIndex >= 0)
            {
                states[existingIndex] = state;
            }
            else
            {
                states.Add(state);
            }
            WriteDocument(StrategyStatesPath, states);
        }
    }

    public IReadOnlyList<StrategyParameterChange> LoadParameterChanges(
        string strategyId,
        int limit)
    {
        lock (_gate)
        {
            if (!File.Exists(ParameterChangesPath))
            {
                return Array.Empty<StrategyParameterChange>();
            }

            return File.ReadLines(ParameterChangesPath, Encoding.UTF8)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .Select(line => JsonSerializer.Deserialize<StrategyParameterChange>(
                    line,
                    _lineOptions) ?? throw new InvalidDataException(
                    "Invalid parameter-change JSON line."))
                .Where(change => string.Equals(
                    change.StrategyId,
                    strategyId,
                    StringComparison.Ordinal))
                .TakeLast(Math.Max(0, limit))
                .ToArray();
        }
    }

    public void AppendParameterChange(StrategyParameterChange change)
    {
        AppendLine(ParameterChangesPath, change);
    }

    public IReadOnlyList<LiveAuthorization> LoadLiveAuthorizations()
    {
        lock (_gate)
        {
            return File.Exists(LiveAuthorizationsPath)
                ? ReadDocument<List<LiveAuthorization>>(LiveAuthorizationsPath)
                : Array.Empty<LiveAuthorization>();
        }
    }

    public void SaveLiveAuthorization(LiveAuthorization authorization)
    {
        lock (_gate)
        {
            var authorizations = File.Exists(LiveAuthorizationsPath)
                ? ReadDocument<List<LiveAuthorization>>(LiveAuthorizationsPath)
                : new List<LiveAuthorization>();
            var existingIndex = authorizations.FindIndex(item =>
                string.Equals(
                    item.AuthorizationId,
                    authorization.AuthorizationId,
                    StringComparison.Ordinal));
            if (existingIndex >= 0)
            {
                authorizations[existingIndex] = authorization;
            }
            else
            {
                authorizations.Add(authorization);
            }
            WriteDocument(LiveAuthorizationsPath, authorizations);
        }
    }

    public IReadOnlyList<FactorDefinition> LoadFactorDefinitions()
    {
        lock (_gate)
        {
            return File.Exists(FactorDefinitionsPath)
                ? ReadDocument<List<FactorDefinition>>(FactorDefinitionsPath)
                : Array.Empty<FactorDefinition>();
        }
    }

    public void SaveFactorDefinitions(
        IReadOnlyList<FactorDefinition> definitions)
    {
        lock (_gate)
        {
            WriteDocument(
                FactorDefinitionsPath,
                definitions
                    .OrderBy(definition => definition.FactorId)
                    .ToArray());
        }
    }

    public IReadOnlyList<FactorTrial> LoadFactorTrials(int limit)
    {
        lock (_gate)
        {
            if (!File.Exists(FactorTrialsPath))
            {
                return Array.Empty<FactorTrial>();
            }
            return File.ReadLines(FactorTrialsPath, Encoding.UTF8)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .TakeLast(Math.Max(0, limit))
                .Select(line => JsonSerializer.Deserialize<FactorTrial>(
                    line,
                    _lineOptions) ?? throw new InvalidDataException(
                    "Invalid factor-trial JSON line."))
                .ToArray();
        }
    }

    public void AppendFactorTrial(FactorTrial trial)
    {
        AppendLine(FactorTrialsPath, trial);
    }

    private static JsonSerializerOptions CreateOptions(bool writeIndented)
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            WriteIndented = writeIndented
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }

    private T ReadDocument<T>(string path)
    {
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path, Encoding.UTF8), _documentOptions)
            ?? throw new InvalidDataException($"Invalid JSON document: {Path.GetFileName(path)}");
    }

    private void WriteDocument<T>(string path, T value)
    {
        var temporaryPath = path + ".tmp";
        File.WriteAllText(
            temporaryPath,
            JsonSerializer.Serialize(value, _documentOptions) + Environment.NewLine,
            new UTF8Encoding(false));
        File.Move(temporaryPath, path, true);
    }

    private void AppendLine<T>(string path, T value)
    {
        lock (_gate)
        {
            Directory.CreateDirectory(_rootDirectory);
            File.AppendAllText(
                path,
                JsonSerializer.Serialize(value, _lineOptions) + Environment.NewLine,
                new UTF8Encoding(false));
        }
    }
}
