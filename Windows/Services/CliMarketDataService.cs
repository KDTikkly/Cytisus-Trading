using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public interface ILongbridgeMarketDataClient
{
    Task<HistoricalBarSeries> FetchHistoricalBarsAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string symbol,
        string interval,
        DateTimeOffset start,
        DateTimeOffset end,
        TimeSpan timeout,
        CancellationToken cancellationToken);
    Task<CurrentMarketSnapshot> FetchCurrentSnapshotAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string symbol,
        TimeSpan timeout,
        CancellationToken cancellationToken);
    Task<MarketStatusSnapshot> FetchMarketStatusAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string market,
        TimeSpan timeout,
        CancellationToken cancellationToken);
    Task<SecurityListSnapshot> FetchSecurityListAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string market,
        TimeSpan timeout,
        CancellationToken cancellationToken);
    Task<BrokerPositionSnapshot> FetchBrokerPositionsAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

public sealed class LongbridgeMarketDataClient : ILongbridgeMarketDataClient
{
    private readonly ILongbridgeCliAdapter _adapter;
    private readonly JsonSerializerOptions _options;

    public LongbridgeMarketDataClient(ILongbridgeCliAdapter adapter)
    {
        _adapter = adapter;
        _options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
        _options.Converters.Add(new JsonStringEnumConverter());
    }

    public Task<HistoricalBarSeries> FetchHistoricalBarsAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string symbol,
        string interval,
        DateTimeOffset start,
        DateTimeOffset end,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        return ExecuteAndParseAsync<HistoricalBarSeries>(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.HistoricalBars,
                new Dictionary<string, string>
                {
                    ["symbol"] = symbol,
                    ["interval"] = interval,
                    ["start"] = start.ToUniversalTime().ToString("O"),
                    ["end"] = end.ToUniversalTime().ToString("O")
                }),
            timeout,
            cancellationToken);
    }

    public Task<CurrentMarketSnapshot> FetchCurrentSnapshotAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string symbol,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        return ExecuteAndParseAsync<CurrentMarketSnapshot>(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.CurrentSnapshot,
                new Dictionary<string, string> { ["symbol"] = symbol }),
            timeout,
            cancellationToken);
    }

    public Task<MarketStatusSnapshot> FetchMarketStatusAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string market,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        return ExecuteAndParseAsync<MarketStatusSnapshot>(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.MarketStatus,
                new Dictionary<string, string> { ["market"] = market }),
            timeout,
            cancellationToken);
    }

    public Task<SecurityListSnapshot> FetchSecurityListAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        string market,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        return ExecuteAndParseAsync<SecurityListSnapshot>(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.SecurityList,
                new Dictionary<string, string> { ["market"] = market }),
            timeout,
            cancellationToken);
    }

    public Task<BrokerPositionSnapshot> FetchBrokerPositionsAsync(
        string executablePath,
        LongbridgeCapabilities capabilities,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        return ExecuteAndParseAsync<BrokerPositionSnapshot>(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.BrokerPositions),
            timeout,
            cancellationToken);
    }

    private async Task<T> ExecuteAndParseAsync<T>(
        CliCommand command,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var result = await _adapter.ExecuteReadOnlyAsync(
            command,
            timeout,
            cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            var reason = result.TimedOut
                ? "timed out"
                : $"failed with exit code {result.ExitCode}";
            throw new IOException(
                $"Longbridge read-only {command.Operation} call {reason}.");
        }

        try
        {
            return JsonSerializer.Deserialize<T>(
                    result.StandardOutput,
                    _options)
                ?? throw new InvalidDataException(
                    $"Longbridge {command.Operation} returned empty JSON.");
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException(
                $"Longbridge {command.Operation} returned invalid JSON.",
                exception);
        }
    }
}
