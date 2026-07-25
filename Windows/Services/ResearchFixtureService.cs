using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public interface IResearchFixtureService
{
    NormalizedResearchDataset BuildDataset(LongbridgeDataSnapshot snapshot);
    IReadOnlyList<FactorDefinition> LoadFactorDefinitions();
    RegimeAllocationFixture LoadRegimeAllocationFixture();
}

public sealed class ResearchFixtureService : IResearchFixtureService
{
    private readonly Assembly _assembly;
    private readonly JsonSerializerOptions _options;

    public ResearchFixtureService(Assembly? assembly = null)
    {
        _assembly = assembly ?? typeof(ResearchFixtureService).Assembly;
        _options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
        _options.Converters.Add(new JsonStringEnumConverter());
    }

    public NormalizedResearchDataset BuildDataset(
        LongbridgeDataSnapshot snapshot)
    {
        var included = snapshot.Universe.Entries
            .Where(entry => entry.Included)
            .Select(entry => entry.Symbol)
            .ToHashSet(StringComparer.Ordinal);
        var reference = snapshot.SecurityList.Securities
            .FirstOrDefault(security =>
                security.Symbol == snapshot.HistoricalBars.Symbol &&
                included.Contains(security.Symbol))
            ?? throw new InvalidDataException(
                "The Longbridge-backed research symbol is not in the current universe.");
        var ordered = snapshot.HistoricalBars.Bars
            .OrderBy(bar => bar.EventTime)
            .ToArray();
        var observations = new List<ResearchObservation>();
        decimal? previousClose = null;
        foreach (var bar in ordered)
        {
            if (bar.AvailableTime < bar.EventTime)
            {
                throw new InvalidDataException(
                    "Research data violates available-time ordering.");
            }
            var dailyReturn = previousClose.HasValue &&
                previousClose.Value != 0
                ? (double)(bar.Close / previousClose.Value - 1)
                : 0;
            observations.Add(new ResearchObservation(
                snapshot.HistoricalBars.Symbol,
                reference.Industry,
                bar.EventTime,
                bar.AvailableTime,
                (double)bar.Open,
                (double)bar.High,
                (double)bar.Low,
                (double)bar.Close,
                (double)bar.Volume,
                dailyReturn,
                dailyReturn * 0.82,
                dailyReturn * 0.91,
                dailyReturn * (double)bar.Volume / 1_000_000));
            previousClose = bar.Close;
        }

        return new NormalizedResearchDataset(
            $"longbridge:{snapshot.HistoricalBars.DataHash}",
            $"{snapshot.Universe.RuleVersion}:{snapshot.Universe.SourceVersion}",
            snapshot.HistoricalBars.Bars
                .Select(bar => bar.CollectedAt)
                .DefaultIfEmpty(snapshot.Universe.CreatedAt)
                .Max(),
            observations);
    }

    public IReadOnlyList<FactorDefinition> LoadFactorDefinitions()
    {
        return ReadEmbedded<IReadOnlyList<FactorDefinition>>(
            "research-factor-definitions.json");
    }

    public RegimeAllocationFixture LoadRegimeAllocationFixture()
    {
        return ReadEmbedded<RegimeAllocationFixture>(
            "regime-allocation-input.json");
    }

    private T ReadEmbedded<T>(string fileName)
    {
        var resourceName = _assembly.GetManifestResourceNames()
            .SingleOrDefault(name => name.EndsWith(
                fileName,
                StringComparison.OrdinalIgnoreCase))
            ?? throw new FileNotFoundException(
                $"Embedded research fixture was not found: {fileName}");
        using var stream = _assembly.GetManifestResourceStream(resourceName)
            ?? throw new FileNotFoundException(
                $"Embedded research fixture could not be opened: {fileName}");
        return JsonSerializer.Deserialize<T>(stream, _options)
            ?? throw new InvalidDataException(
                $"Embedded research fixture is invalid: {fileName}");
    }
}
