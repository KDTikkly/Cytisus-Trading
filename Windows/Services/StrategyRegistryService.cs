using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace CytisusTrading.Windows;

public interface IStrategyRegistryService
{
    (StrategyManifest Manifest, StrategyParameterSchema Parameters) LoadOfficial();
    ManifestValidationResult Validate(
        StrategyManifest manifest,
        StrategyParameterSchema parameters,
        IReadOnlyCollection<string> existingStrategyIds,
        string? manifestDirectory);
    (StrategyManifest Manifest, StrategyParameterSchema Parameters)
        LoadThirdParty(
            string manifestPath,
            IReadOnlyCollection<string> existingStrategyIds);
    LiveAuthorization LoadAuthorizationFixture(string fileName);
}

public sealed class StrategyRegistryService : IStrategyRegistryService
{
    private static readonly Regex StrategyIdPattern =
        new("^[a-z0-9][a-z0-9-]{2,63}$", RegexOptions.CultureInvariant);
    private static readonly Regex VersionPattern =
        new("^[0-9]+\\.[0-9]+\\.[0-9]+$", RegexOptions.CultureInvariant);
    private static readonly HashSet<string> AllowedCapabilities =
        new(StringComparer.Ordinal)
        {
            "market_data",
            "strategy_events",
            "structured_logs"
        };
    private readonly Assembly _assembly;
    private readonly JsonSerializerOptions _options;

    public StrategyRegistryService(Assembly? assembly = null)
    {
        _assembly = assembly ?? typeof(StrategyRegistryService).Assembly;
        _options = CreateOptions();
    }

    public (StrategyManifest Manifest, StrategyParameterSchema Parameters)
        LoadOfficial()
    {
        var manifest = ReadEmbedded<StrategyManifest>(
            "sample-strategy-manifest.json");
        var parameters = ReadEmbedded<StrategyParameterSchema>(
            "official-parameter-schema.json");
        var validation = Validate(
            manifest,
            parameters,
            Array.Empty<string>(),
            null);
        if (!validation.IsValid)
        {
            throw new InvalidDataException(validation.Message);
        }
        return (manifest, parameters);
    }

    public ManifestValidationResult Validate(
        StrategyManifest manifest,
        StrategyParameterSchema parameters,
        IReadOnlyCollection<string> existingStrategyIds,
        string? manifestDirectory)
    {
        if (manifest.SchemaVersion != 1)
        {
            return ManifestValidationResult.Invalid(
                "Unsupported manifest schema version.");
        }
        if (manifest.ProtocolVersion != 1)
        {
            return ManifestValidationResult.Invalid(
                "Unsupported strategy protocol version.");
        }
        if (!StrategyIdPattern.IsMatch(manifest.StrategyId))
        {
            return ManifestValidationResult.Invalid("Invalid strategy ID.");
        }
        if (existingStrategyIds.Contains(
                manifest.StrategyId,
                StringComparer.Ordinal))
        {
            return ManifestValidationResult.Invalid("Duplicate strategy ID.");
        }
        if (string.IsNullOrWhiteSpace(manifest.Name) ||
            !VersionPattern.IsMatch(manifest.Version))
        {
            return ManifestValidationResult.Invalid(
                "Invalid strategy identity or version.");
        }
        if (manifest.SupportedModes.Count == 0 ||
            !manifest.SupportedModes.Contains(StrategyMode.PaperOnly))
        {
            return ManifestValidationResult.Invalid(
                "Every strategy must support PaperOnly.");
        }
        if (manifest.RequestedCapabilities.Any(capability =>
                !AllowedCapabilities.Contains(capability)) ||
            manifest.RequestedCapabilities.Any(capability =>
                capability.Contains("cli", StringComparison.OrdinalIgnoreCase)))
        {
            return ManifestValidationResult.Invalid(
                "Direct CLI access is prohibited.");
        }
        if (!string.Equals(
                parameters.StrategyId,
                manifest.StrategyId,
                StringComparison.Ordinal) ||
            parameters.SchemaVersion != manifest.ParameterSchemaVersion)
        {
            return ManifestValidationResult.Invalid(
                "Parameter schema identity or version is incompatible.");
        }
        if (!ValidateParameters(parameters, out var parameterError))
        {
            return ManifestValidationResult.Invalid(parameterError);
        }

        if (manifest.Source == StrategySource.Official)
        {
            if (!manifest.Entrypoint.StartsWith(
                    "fixture://",
                    StringComparison.Ordinal))
            {
                return ManifestValidationResult.Invalid(
                    "Official fixture entrypoint is invalid.");
            }
        }
        else
        {
            if (string.IsNullOrWhiteSpace(manifestDirectory))
            {
                return ManifestValidationResult.Invalid(
                    "Third-party manifest directory is unavailable.");
            }
            var entrypoint = Path.GetFullPath(
                manifest.Entrypoint,
                manifestDirectory);
            if (!File.Exists(entrypoint))
            {
                return ManifestValidationResult.Invalid(
                    "Strategy entrypoint does not exist.");
            }
        }

        return ManifestValidationResult.Valid;
    }

    public (StrategyManifest Manifest, StrategyParameterSchema Parameters)
        LoadThirdParty(
            string manifestPath,
            IReadOnlyCollection<string> existingStrategyIds)
    {
        var fullManifestPath = Path.GetFullPath(manifestPath);
        var manifestDirectory = Path.GetDirectoryName(fullManifestPath)
            ?? throw new InvalidDataException(
                "Strategy manifest directory is unavailable.");
        var rawManifest = File.ReadAllText(fullManifestPath, Encoding.UTF8);
        RejectDirectCLIDeclaration(rawManifest);
        var manifest = JsonSerializer.Deserialize<StrategyManifest>(
                rawManifest,
                _options)
            ?? throw new InvalidDataException("Invalid strategy manifest JSON.");
        if (manifest.Source != StrategySource.ThirdParty)
        {
            throw new InvalidDataException(
                "A local registration must declare ThirdParty source.");
        }

        var parameterPath = Path.GetFullPath(
            manifest.ParameterSchema,
            manifestDirectory);
        if (!File.Exists(parameterPath))
        {
            throw new InvalidDataException(
                "Strategy parameter schema does not exist.");
        }
        var rawParameters = File.ReadAllText(parameterPath, Encoding.UTF8);
        RejectDirectCLIDeclaration(rawParameters);
        var parameters = JsonSerializer.Deserialize<StrategyParameterSchema>(
                rawParameters,
                _options)
            ?? throw new InvalidDataException(
                "Invalid strategy parameter schema JSON.");
        var validation = Validate(
            manifest,
            parameters,
            existingStrategyIds,
            manifestDirectory);
        if (!validation.IsValid)
        {
            throw new InvalidDataException(validation.Message);
        }

        return (
            manifest with
            {
                Entrypoint = Path.GetFullPath(
                    manifest.Entrypoint,
                    manifestDirectory),
                ParameterSchema = parameterPath
            },
            parameters);
    }

    public LiveAuthorization LoadAuthorizationFixture(string fileName)
    {
        return ReadEmbedded<LiveAuthorization>(fileName);
    }

    private static bool ValidateParameters(
        StrategyParameterSchema schema,
        out string error)
    {
        if (schema.Parameters.Count == 0)
        {
            error = "Parameter schema contains no parameters.";
            return false;
        }
        if (schema.Parameters
            .GroupBy(parameter => parameter.Key, StringComparer.Ordinal)
            .Any(group => group.Count() > 1))
        {
            error = "Parameter schema contains duplicate keys.";
            return false;
        }

        foreach (var parameter in schema.Parameters)
        {
            if (string.IsNullOrWhiteSpace(parameter.Key) ||
                string.IsNullOrWhiteSpace(parameter.Label) ||
                string.IsNullOrWhiteSpace(parameter.Description))
            {
                error = "Parameter schema contains an incomplete definition.";
                return false;
            }
            if (!ParameterGovernanceService.IsValueValid(
                    parameter,
                    parameter.DefaultValue,
                    out _))
            {
                error = $"Invalid default value for {parameter.Key}.";
                return false;
            }
            var safety = parameter.SafetyOverride;
            if (safety.RiskTier == RiskTier.High &&
                (!safety.RequiresPreview ||
                 !safety.RequiresConfirmation ||
                 !safety.RollbackRequired ||
                 safety.ActivationMode !=
                    ParameterActivationMode.SafeBoundary))
            {
                error =
                    $"High-risk safety override is incomplete for {parameter.Key}.";
                return false;
            }
        }

        error = string.Empty;
        return true;
    }

    private static void RejectDirectCLIDeclaration(string rawJSON)
    {
        if (rawJSON.Contains("longbridge_cli", StringComparison.OrdinalIgnoreCase) ||
            rawJSON.Contains("direct_cli_access", StringComparison.OrdinalIgnoreCase) ||
            rawJSON.Contains("broker_secret", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                "Direct CLI access declarations are prohibited.");
        }
    }

    private T ReadEmbedded<T>(string fileName)
    {
        var resourceName = _assembly
            .GetManifestResourceNames()
            .SingleOrDefault(name =>
                name.EndsWith(fileName, StringComparison.OrdinalIgnoreCase));
        if (resourceName is null)
        {
            throw new FileNotFoundException(
                $"Embedded strategy fixture not found: {fileName}");
        }
        using var stream = _assembly.GetManifestResourceStream(resourceName)
            ?? throw new FileNotFoundException(
                $"Embedded strategy fixture stream not found: {fileName}");
        return JsonSerializer.Deserialize<T>(stream, _options)
            ?? throw new InvalidDataException(
                $"Invalid embedded strategy fixture: {fileName}");
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}
