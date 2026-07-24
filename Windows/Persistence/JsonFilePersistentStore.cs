using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public sealed class JsonFilePersistentStore :
    ISettingsStore,
    IApplicationLogStore,
    IAuditEventStore,
    IMigrationStore
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
