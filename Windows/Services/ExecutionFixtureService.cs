using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public sealed class ExecutionFixtureService
{
    private readonly Assembly _assembly;
    private readonly JsonSerializerOptions _options;

    public ExecutionFixtureService(Assembly? assembly = null)
    {
        _assembly = assembly ?? typeof(ExecutionFixtureService).Assembly;
        _options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
        _options.Converters.Add(new JsonStringEnumConverter());
    }

    public PaperGatewayFixture LoadPaperGatewayFixture()
    {
        return Read<PaperGatewayFixture>("paper-gateway-cycle.json");
    }

    public LongbridgeExecutionCapability LoadExecutionCapability()
    {
        return Read<LongbridgeExecutionCapability>(
            "longbridge-execution-capability.json");
    }

    public ReconciliationFailureFixture LoadReconciliationFailure()
    {
        return Read<ReconciliationFailureFixture>(
            "reconciliation-failure.json");
    }

    private T Read<T>(string fileName)
    {
        var resourceName = _assembly.GetManifestResourceNames()
            .SingleOrDefault(name => name.EndsWith(
                fileName,
                StringComparison.OrdinalIgnoreCase))
            ?? throw new FileNotFoundException(
                $"Embedded execution fixture was not found: {fileName}");
        using var stream = _assembly.GetManifestResourceStream(resourceName)
            ?? throw new FileNotFoundException(
                $"Embedded execution fixture could not be opened: {fileName}");
        return JsonSerializer.Deserialize<T>(stream, _options)
            ?? throw new InvalidDataException(
                $"Embedded execution fixture is invalid: {fileName}");
    }
}
