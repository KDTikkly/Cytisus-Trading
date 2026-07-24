using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public sealed class FixtureFactorRepository : IFactorRepository
{
    private const string FixtureSuffix = "fixtures.factors.demo-factors.json";
    private readonly object _gate = new();
    private readonly JsonSerializerOptions _options;
    private List<FactorItem>? _current;

    public FixtureFactorRepository()
    {
        _options = new JsonSerializerOptions();
        _options.Converters.Add(new JsonStringEnumConverter());
    }

    public IReadOnlyList<FactorItem> LoadFactors()
    {
        lock (_gate)
        {
            _current ??= LoadEmbeddedFixture();
            return _current.Select(factor => factor.Clone()).ToArray();
        }
    }

    public void SaveFactors(IReadOnlyList<FactorItem> factors)
    {
        lock (_gate)
        {
            _current = factors.Select(factor => factor.Clone()).ToList();
        }
    }

    public IReadOnlyList<FactorItem> ResetToFixtures()
    {
        lock (_gate)
        {
            _current = LoadEmbeddedFixture();
            return _current.Select(factor => factor.Clone()).ToArray();
        }
    }

    private List<FactorItem> LoadEmbeddedFixture()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = assembly
            .GetManifestResourceNames()
            .SingleOrDefault(name => name.EndsWith(FixtureSuffix, StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("Embedded factor fixture was not found.");

        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("Embedded factor fixture could not be opened.");
        return JsonSerializer.Deserialize<List<FactorItem>>(stream, _options)
            ?? throw new InvalidDataException("Embedded factor fixture is invalid.");
    }
}
