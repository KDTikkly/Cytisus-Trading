using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public sealed class JsonMarketDataCache : IMarketDataCache
{
    private readonly string _rootDirectory;
    private readonly object _gate = new();
    private readonly JsonSerializerOptions _options;

    public JsonMarketDataCache(string rootDirectory)
    {
        _rootDirectory = Path.GetFullPath(rootDirectory);
        _options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            WriteIndented = true
        };
        _options.Converters.Add(new JsonStringEnumConverter());
    }

    public CacheWriteResult StoreHistoricalBars(HistoricalBarSeries series)
    {
        lock (_gate)
        {
            var path = HistoricalBarsPath(
                series.Symbol,
                series.Interval,
                series.Start,
                series.End);
            return WriteIdempotent(
                path,
                series,
                existing => existing.DataHash,
                series.DataHash);
        }
    }

    public CacheWriteResult StoreCurrentSnapshot(CurrentMarketSnapshot snapshot)
    {
        lock (_gate)
        {
            var key = StableKey(snapshot.Symbol.ToUpperInvariant());
            var path = Path.Combine(_rootDirectory, "market-snapshots", $"{key}.json");
            return WriteIdempotent(
                path,
                snapshot,
                existing => existing.DataHash,
                snapshot.DataHash);
        }
    }

    public CacheWriteResult StoreUniverseSnapshot(UniverseSnapshot snapshot)
    {
        lock (_gate)
        {
            var safeDate = snapshot.Date.Replace("-", string.Empty, StringComparison.Ordinal);
            var path = Path.Combine(_rootDirectory, "universe", $"{safeDate}.json");
            return WriteIdempotent(
                path,
                snapshot,
                existing => $"{existing.RuleVersion}:{existing.SourceVersion}:{existing.Entries.Count}",
                $"{snapshot.RuleVersion}:{snapshot.SourceVersion}:{snapshot.Entries.Count}");
        }
    }

    public HistoricalBarSeries? LoadHistoricalBars(
        string symbol,
        string interval,
        DateTimeOffset start,
        DateTimeOffset end)
    {
        lock (_gate)
        {
            return ReadIfPresent<HistoricalBarSeries>(
                HistoricalBarsPath(symbol, interval, start, end));
        }
    }

    public UniverseSnapshot? LoadUniverseSnapshot(string date)
    {
        lock (_gate)
        {
            var safeDate = date.Replace("-", string.Empty, StringComparison.Ordinal);
            return ReadIfPresent<UniverseSnapshot>(
                Path.Combine(_rootDirectory, "universe", $"{safeDate}.json"));
        }
    }

    public long CacheSizeBytes()
    {
        lock (_gate)
        {
            if (!Directory.Exists(_rootDirectory))
            {
                return 0;
            }

            return Directory.EnumerateFiles(
                    _rootDirectory,
                    "*.json",
                    SearchOption.AllDirectories)
                .Sum(path => new FileInfo(path).Length);
        }
    }

    public static string DefaultDirectory()
    {
        return Path.Combine(
            JsonFilePersistentStore.DefaultRootDirectory(),
            "market-cache");
    }

    private string HistoricalBarsPath(
        string symbol,
        string interval,
        DateTimeOffset start,
        DateTimeOffset end)
    {
        var identity = string.Join(
            "|",
            symbol.ToUpperInvariant(),
            interval.ToUpperInvariant(),
            start.ToUniversalTime().ToString("O"),
            end.ToUniversalTime().ToString("O"));
        return Path.Combine(
            _rootDirectory,
            "market-bars",
            $"{StableKey(identity)}.json");
    }

    private CacheWriteResult WriteIdempotent<T>(
        string path,
        T value,
        Func<T, string> identity,
        string expectedIdentity)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)
            ?? throw new InvalidOperationException("Cache path has no parent directory."));

        if (File.Exists(path))
        {
            var existing = Read<T>(path);
            if (string.Equals(
                    identity(existing),
                    expectedIdentity,
                    StringComparison.Ordinal))
            {
                return CacheWriteResult.Unchanged;
            }

            Write(path, value);
            return CacheWriteResult.Updated;
        }

        Write(path, value);
        return CacheWriteResult.Created;
    }

    private T? ReadIfPresent<T>(string path)
    {
        return File.Exists(path) ? Read<T>(path) : default;
    }

    private T Read<T>(string path)
    {
        return JsonSerializer.Deserialize<T>(
                File.ReadAllText(path, Encoding.UTF8),
                _options)
            ?? throw new InvalidDataException($"Invalid cache JSON: {Path.GetFileName(path)}");
    }

    private void Write<T>(string path, T value)
    {
        var temporaryPath = path + ".tmp";
        File.WriteAllText(
            temporaryPath,
            JsonSerializer.Serialize(value, _options) + Environment.NewLine,
            new UTF8Encoding(false));
        File.Move(temporaryPath, path, true);
    }

    private static string StableKey(string value)
    {
        return Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(value)))
            .ToLowerInvariant();
    }
}
