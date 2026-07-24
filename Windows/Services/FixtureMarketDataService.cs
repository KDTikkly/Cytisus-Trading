using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public interface ILongbridgeDataService
{
    LongbridgeDataSnapshot LoadFixtureSnapshot();
}

public sealed class FixtureLongbridgeDataService : ILongbridgeDataService
{
    private readonly IMarketDataCache _cache;
    private readonly IUniverseService _universeService;
    private readonly Assembly _assembly;
    private readonly JsonSerializerOptions _options;

    public FixtureLongbridgeDataService(
        IMarketDataCache cache,
        IUniverseService universeService,
        Assembly? assembly = null)
    {
        _cache = cache;
        _universeService = universeService;
        _assembly = assembly ?? typeof(FixtureLongbridgeDataService).Assembly;
        _options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
        _options.Converters.Add(new JsonStringEnumConverter());
    }

    public LongbridgeDataSnapshot LoadFixtureSnapshot()
    {
        var capabilities = Read<LongbridgeCapabilities>("cli-capabilities.json");
        var authorization = Read<AuthorizationStatusSummary>("authorization-status.json");
        var connectivity = Read<ConnectivitySummary>("connectivity-check.json");
        var bars = Read<HistoricalBarSeries>("historical-daily-bars.json");
        var current = Read<CurrentMarketSnapshot>("current-market-snapshot.json");
        var marketStatus = Read<MarketStatusSnapshot>("market-status.json");
        var securities = Read<SecurityListSnapshot>("security-list.json");
        var positions = Read<BrokerPositionSnapshot>("broker-positions.json");
        var configuration = Read<UniverseConfiguration>("universe-config.json");
        var universe = _universeService.BuildDailySnapshot(
            securities.CollectedAt,
            configuration,
            securities,
            positions);

        _cache.StoreHistoricalBars(bars);
        _cache.StoreCurrentSnapshot(current);
        _cache.StoreUniverseSnapshot(universe);

        return new LongbridgeDataSnapshot(
            capabilities,
            authorization,
            connectivity,
            bars,
            current,
            marketStatus,
            securities,
            positions,
            universe);
    }

    private T Read<T>(string fileName)
    {
        var resourceName = _assembly
            .GetManifestResourceNames()
            .SingleOrDefault(name =>
                name.EndsWith(fileName, StringComparison.OrdinalIgnoreCase));
        if (resourceName is null)
        {
            throw new FileNotFoundException(
                $"Embedded Longbridge fixture not found: {fileName}");
        }

        using var stream = _assembly.GetManifestResourceStream(resourceName)
            ?? throw new FileNotFoundException(
                $"Embedded Longbridge fixture stream not found: {fileName}");
        return JsonSerializer.Deserialize<T>(stream, _options)
            ?? throw new InvalidDataException(
                $"Invalid Longbridge fixture JSON: {fileName}");
    }
}
