using System.IO;

namespace CytisusTrading.Windows;

public static class Prompt2Smoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            Directory.CreateDirectory(rootDirectory);
            var cache = new JsonMarketDataCache(
                Path.Combine(rootDirectory, "market-cache"));
            var universeService = new UniverseService();
            var fixtureService = new FixtureLongbridgeDataService(
                cache,
                universeService);
            var snapshot = fixtureService.LoadFixtureSnapshot();

            if (snapshot.HistoricalBars.Bars.Count != 5 ||
                snapshot.HistoricalBars.Bars.Any(bar =>
                    bar.AvailableTime < bar.EventTime) ||
                snapshot.CurrentSnapshot.Symbol != "AAPL.US" ||
                snapshot.CurrentSnapshot.DataHash.Length != 64)
            {
                return 2;
            }

            var command = CapabilityAwareCommandFactory.Build(
                "C:\\Program Files\\Longbridge\\longbridge.exe",
                snapshot.Capabilities,
                LongbridgeOperation.HistoricalBars,
                new Dictionary<string, string>
                {
                    ["symbol"] = "AAPL.US",
                    ["interval"] = "Daily",
                    ["start"] = "2026-07-20T00:00:00Z",
                    ["end"] = "2026-07-24T23:59:59Z"
                });
            if (command.Category != CliCallCategory.ReadOnlyData ||
                command.Arguments.Count != 12 ||
                command.Arguments[0] != "market" ||
                command.Arguments[1] != "bars" ||
                command.Arguments.Contains(
                    "market bars",
                    StringComparer.Ordinal))
            {
                return 3;
            }

            var redacted = SensitiveDataRedactor.Redact(
                "{\"token\":\"alpha\",\"nested\":{\"account_number\":\"12345678\",\"authenticated\":true}}");
            if (redacted.Contains("alpha", StringComparison.Ordinal) ||
                redacted.Contains("12345678", StringComparison.Ordinal) ||
                !redacted.Contains("\"authenticated\":true", StringComparison.Ordinal))
            {
                return 4;
            }

            var currentExecutable = Environment.ProcessPath
                ?? throw new InvalidOperationException(
                    "The current executable path is unavailable.");
            var timeoutAdapter = new LongbridgeCliAdapter(
                new FixedProcessRunner(new CliProcessResult(
                    -1,
                    string.Empty,
                    string.Empty,
                    true,
                    false,
                    false,
                    TimeSpan.FromSeconds(1))));
            var timeoutInspection = timeoutAdapter
                .InspectAsync(
                    currentExecutable,
                    TimeSpan.FromSeconds(1),
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            if (timeoutInspection.State != LongbridgeStatusState.Degraded ||
                !timeoutInspection.Message.Contains(
                    "timed out",
                    StringComparison.OrdinalIgnoreCase))
            {
                return 5;
            }

            var nonZeroAdapter = new LongbridgeCliAdapter(
                new FixedProcessRunner(new CliProcessResult(
                    17,
                    string.Empty,
                    "failure",
                    false,
                    false,
                    false,
                    TimeSpan.Zero)));
            var nonZeroInspection = nonZeroAdapter
                .InspectAsync(
                    currentExecutable,
                    TimeSpan.FromSeconds(1),
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            if (nonZeroInspection.State != LongbridgeStatusState.Degraded)
            {
                return 6;
            }

            var included = snapshot.Universe.Entries.Single(
                entry => entry.Symbol == "AAPL.US");
            var excluded = snapshot.Universe.Entries.Single(
                entry => entry.Symbol == "LOWP.US");
            var reduceOnly = snapshot.Universe.Entries.Single(
                entry => entry.Symbol == "HALT.US");
            if (!included.Included ||
                included.Disposition != UniverseDisposition.Included ||
                excluded.Included ||
                excluded.Disposition != UniverseDisposition.Excluded ||
                reduceOnly.Included ||
                reduceOnly.Disposition != UniverseDisposition.ReduceOnly)
            {
                return 7;
            }

            if (cache.StoreHistoricalBars(snapshot.HistoricalBars) !=
                    CacheWriteResult.Unchanged ||
                cache.LoadHistoricalBars(
                    snapshot.HistoricalBars.Symbol,
                    snapshot.HistoricalBars.Interval,
                    snapshot.HistoricalBars.Start,
                    snapshot.HistoricalBars.End)?.DataHash !=
                    snapshot.HistoricalBars.DataHash)
            {
                return 8;
            }

            return 0;
        }
        catch
        {
            return 1;
        }
    }

    private sealed class FixedProcessRunner : IReadOnlyProcessRunner
    {
        private readonly CliProcessResult _result;

        public FixedProcessRunner(CliProcessResult result)
        {
            _result = result;
        }

        public Task<CliProcessResult> RunAsync(
            string executablePath,
            IReadOnlyList<string> arguments,
            TimeSpan timeout,
            int outputLimit,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(_result);
        }
    }
}
