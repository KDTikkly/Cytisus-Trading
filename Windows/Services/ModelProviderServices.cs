using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CytisusTrading.Windows;

public enum ProviderEndpointSafety
{
    Secure,
    LocalHttp,
    RemoteHttpConfirmationRequired,
    Invalid
}

public sealed record ProviderRequest(
    HttpMethod Method,
    Uri Uri,
    IReadOnlyDictionary<string, string> Headers,
    string? Body);

public sealed record ProviderClientTestResult(
    ProviderTestResultCategory Category,
    string Message,
    int? LatencyMilliseconds)
{
    public bool IsReady => Category == ProviderTestResultCategory.Ready;
}

public sealed record ModelGenerationOutcome(
    string Text,
    ModelProviderSelection Selection);

public interface IModelProviderClient
{
    Task<IReadOnlyList<ProviderModelRecord>> ListModelsAsync(
        ModelProviderProfile provider,
        string apiKey,
        CancellationToken cancellationToken);
    Task<ProviderClientTestResult> TestConnectionAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        CancellationToken cancellationToken);
    Task<string> GenerateTextAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken);
    Task<JsonObject> GenerateStructuredResponseAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken);
    Task<ModelToolDecision> RequestToolDecisionAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken);
}

public static class ProviderEndpointValidator
{
    public static ProviderEndpointSafety Validate(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps &&
             uri.Scheme != Uri.UriSchemeHttp))
        {
            return ProviderEndpointSafety.Invalid;
        }
        if (uri.Scheme == Uri.UriSchemeHttps)
        {
            return ProviderEndpointSafety.Secure;
        }
        return IsLoopback(uri.Host)
            ? ProviderEndpointSafety.LocalHttp
            : ProviderEndpointSafety.RemoteHttpConfirmationRequired;
    }

    private static bool IsLoopback(string host)
    {
        return string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(host, "127.0.0.1", StringComparison.Ordinal) ||
            string.Equals(host, "::1", StringComparison.Ordinal);
    }
}

public static class ModelProviderRequestFactory
{
    public static ProviderRequest BuildListModels(
        ModelProviderProfile provider,
        string apiKey)
    {
        return provider.ProtocolType switch
        {
            ModelProviderProtocol.OpenAICompatible => new ProviderRequest(
                HttpMethod.Get,
                Append(provider.BaseUrl, "models"),
                new Dictionary<string, string>
                {
                    ["Authorization"] = "Bearer " + apiKey
                },
                null),
            ModelProviderProtocol.GeminiCompatible => new ProviderRequest(
                HttpMethod.Get,
                Append(provider.BaseUrl, "models"),
                new Dictionary<string, string>
                {
                    ["x-goog-api-key"] = apiKey
                },
                null),
            _ => throw new NotSupportedException(
                "Anthropic-compatible model discovery is optional and unavailable.")
        };
    }

    public static ProviderRequest BuildGenerateText(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText)
    {
        return provider.ProtocolType switch
        {
            ModelProviderProtocol.OpenAICompatible => BuildOpenAI(
                provider,
                model,
                apiKey,
                systemInstruction,
                userText),
            ModelProviderProtocol.AnthropicCompatible => BuildAnthropic(
                provider,
                model,
                apiKey,
                systemInstruction,
                userText),
            ModelProviderProtocol.GeminiCompatible => BuildGemini(
                provider,
                model,
                apiKey,
                systemInstruction,
                userText),
            _ => throw new NotSupportedException("Unsupported provider protocol.")
        };
    }

    private static ProviderRequest BuildOpenAI(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText)
    {
        var body = new JsonObject
        {
            ["model"] = model.ModelId,
            ["temperature"] = 0,
            ["messages"] = new JsonArray
            {
                new JsonObject
                {
                    ["role"] = "system",
                    ["content"] = systemInstruction
                },
                new JsonObject
                {
                    ["role"] = "user",
                    ["content"] = userText
                }
            }
        };
        return JsonRequest(
            Append(provider.BaseUrl, "chat/completions"),
            new Dictionary<string, string>
            {
                ["Authorization"] = "Bearer " + apiKey
            },
            body);
    }

    private static ProviderRequest BuildAnthropic(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText)
    {
        var body = new JsonObject
        {
            ["model"] = model.ModelId,
            ["max_tokens"] = 64,
            ["temperature"] = 0,
            ["system"] = systemInstruction,
            ["messages"] = new JsonArray
            {
                new JsonObject
                {
                    ["role"] = "user",
                    ["content"] = userText
                }
            }
        };
        return JsonRequest(
            Append(provider.BaseUrl, "messages"),
            new Dictionary<string, string>
            {
                ["x-api-key"] = apiKey,
                ["anthropic-version"] = "2023-06-01"
            },
            body);
    }

    private static ProviderRequest BuildGemini(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText)
    {
        var modelId = model.ModelId.StartsWith(
            "models/",
            StringComparison.Ordinal)
            ? model.ModelId["models/".Length..]
            : model.ModelId;
        var body = new JsonObject
        {
            ["systemInstruction"] = new JsonObject
            {
                ["parts"] = new JsonArray
                {
                    new JsonObject { ["text"] = systemInstruction }
                }
            },
            ["contents"] = new JsonArray
            {
                new JsonObject
                {
                    ["role"] = "user",
                    ["parts"] = new JsonArray
                    {
                        new JsonObject { ["text"] = userText }
                    }
                }
            },
            ["generationConfig"] = new JsonObject
            {
                ["temperature"] = 0,
                ["maxOutputTokens"] = 64
            }
        };
        return JsonRequest(
            Append(
                provider.BaseUrl,
                $"models/{Uri.EscapeDataString(modelId)}:generateContent"),
            new Dictionary<string, string>
            {
                ["x-goog-api-key"] = apiKey
            },
            body);
    }

    private static ProviderRequest JsonRequest(
        Uri uri,
        IReadOnlyDictionary<string, string> headers,
        JsonObject body)
    {
        return new ProviderRequest(
            HttpMethod.Post,
            uri,
            headers,
            body.ToJsonString());
    }

    private static Uri Append(string baseUrl, string relative)
    {
        return new Uri(
            baseUrl.TrimEnd('/') + "/" + relative.TrimStart('/'),
            UriKind.Absolute);
    }
}

public sealed class HttpModelProviderClient : IModelProviderClient
{
    private readonly HttpClient _client;

    public HttpModelProviderClient(HttpClient? client = null)
    {
        _client = client ?? new HttpClient();
    }

    public async Task<IReadOnlyList<ProviderModelRecord>> ListModelsAsync(
        ModelProviderProfile provider,
        string apiKey,
        CancellationToken cancellationToken)
    {
        var request = ModelProviderRequestFactory.BuildListModels(
            provider,
            apiKey);
        using var response = await SendAsync(
            request,
            provider.RequestTimeoutSeconds,
            cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, body);
        return ParseModels(provider, body);
    }

    public async Task<ProviderClientTestResult> TestConnectionAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            _ = await GenerateTextAsync(
                provider,
                model,
                apiKey,
                "Return the single word READY.",
                "Connectivity check.",
                cancellationToken);
            return new ProviderClientTestResult(
                ProviderTestResultCategory.Ready,
                "Provider and model responded.",
                (int)stopwatch.ElapsedMilliseconds);
        }
        catch (Exception exception)
        {
            return new ProviderClientTestResult(
                MapFailure(exception, cancellationToken),
                SensitiveDataRedactor.Redact(exception.Message),
                (int)stopwatch.ElapsedMilliseconds);
        }
    }

    public async Task<string> GenerateTextAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken)
    {
        var request = ModelProviderRequestFactory.BuildGenerateText(
            provider,
            model,
            apiKey,
            systemInstruction,
            userText);
        using var response = await SendAsync(
            request,
            provider.RequestTimeoutSeconds,
            cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, body);
        return ParseGeneratedText(provider.ProtocolType, body);
    }

    public async Task<JsonObject> GenerateStructuredResponseAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken)
    {
        var text = await GenerateTextAsync(
            provider,
            model,
            apiKey,
            systemInstruction,
            userText,
            cancellationToken);
        return JsonNode.Parse(text) as JsonObject
            ?? throw new InvalidDataException(
                "The provider response was not a JSON object.");
    }

    public async Task<ModelToolDecision> RequestToolDecisionAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken)
    {
        if (model.SupportsToolCalling != ModelCapabilityState.Supported)
        {
            throw new NotSupportedException(
                "Tool calling is not explicitly supported by this model.");
        }
        var node = await GenerateStructuredResponseAsync(
            provider,
            model,
            apiKey,
            systemInstruction,
            userText,
            cancellationToken);
        var tool = node["tool"]?.GetValue<string>()
            ?? throw new InvalidDataException("The tool decision has no tool.");
        var arguments = node["arguments"] is JsonObject values
            ? values.ToDictionary(
                pair => pair.Key,
                pair => pair.Value?.GetValue<string>() ?? string.Empty)
            : new Dictionary<string, string>();
        return new ModelToolDecision(tool, arguments);
    }

    private async Task<HttpResponseMessage> SendAsync(
        ProviderRequest request,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(
            timeoutSeconds,
            2,
            120)));
        using var message = new HttpRequestMessage(request.Method, request.Uri);
        foreach (var header in request.Headers)
        {
            message.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }
        if (request.Body is not null)
        {
            message.Content = new StringContent(
                request.Body,
                Encoding.UTF8,
                "application/json");
        }
        return await _client.SendAsync(message, timeout.Token);
    }

    private static IReadOnlyList<ProviderModelRecord> ParseModels(
        ModelProviderProfile provider,
        string body)
    {
        var root = JsonNode.Parse(body) as JsonObject
            ?? throw new InvalidDataException("Invalid model-list response.");
        IEnumerable<(string Id, string Name)> values =
            provider.ProtocolType switch
            {
                ModelProviderProtocol.OpenAICompatible =>
                    (root["data"] as JsonArray ?? new JsonArray())
                    .OfType<JsonObject>()
                    .Select(item =>
                    {
                        var id = item["id"]?.GetValue<string>() ?? string.Empty;
                        return (id, id);
                    }),
                ModelProviderProtocol.GeminiCompatible =>
                    (root["models"] as JsonArray ?? new JsonArray())
                    .OfType<JsonObject>()
                    .Select(item =>
                    {
                        var id = item["name"]?.GetValue<string>() ?? string.Empty;
                        var name = item["displayName"]?.GetValue<string>() ?? id;
                        return (id, name);
                    }),
                _ => Array.Empty<(string, string)>()
            };
        var now = DateTimeOffset.UtcNow;
        return values
            .Where(item => !string.IsNullOrWhiteSpace(item.Id))
            .Select(item => new ProviderModelRecord(
                Guid.NewGuid().ToString("D"),
                provider.ProviderId,
                item.Id,
                item.Name,
                false,
                ModelRecordSource.Discovered,
                ProviderModelStatus.Disabled,
                ModelCapabilityState.Supported,
                ModelCapabilityState.Unknown,
                ModelCapabilityState.Unknown,
                null,
                now,
                now,
                now))
            .ToArray();
    }

    private static string ParseGeneratedText(
        ModelProviderProtocol protocol,
        string body)
    {
        var root = JsonNode.Parse(body) as JsonObject
            ?? throw new InvalidDataException("Invalid generation response.");
        return protocol switch
        {
            ModelProviderProtocol.OpenAICompatible =>
                root["choices"]?[0]?["message"]?["content"]?.GetValue<string>(),
            ModelProviderProtocol.AnthropicCompatible =>
                root["content"]?[0]?["text"]?.GetValue<string>(),
            ModelProviderProtocol.GeminiCompatible =>
                root["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]
                    ?.GetValue<string>(),
            _ => null
        } ?? throw new InvalidDataException(
            "The provider response did not contain text.");
    }

    private static void EnsureSuccess(
        HttpResponseMessage response,
        string body)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }
        throw new HttpRequestException(
            SensitiveDataRedactor.Redact(
                $"Provider returned {(int)response.StatusCode}: {body}"),
            null,
            response.StatusCode);
    }

    private static ProviderTestResultCategory MapFailure(
        Exception exception,
        CancellationToken cancellationToken)
    {
        if (exception is OperationCanceledException)
        {
            return cancellationToken.IsCancellationRequested
                ? ProviderTestResultCategory.Cancelled
                : ProviderTestResultCategory.ConnectionTimeout;
        }
        if (exception is HttpRequestException request)
        {
            if (request.InnerException is AuthenticationException)
            {
                return ProviderTestResultCategory.TLSFailure;
            }
            if (request.InnerException is SocketException socket &&
                socket.SocketErrorCode is
                    SocketError.HostNotFound or
                    SocketError.NoData or
                    SocketError.TryAgain)
            {
                return ProviderTestResultCategory.DNSFailure;
            }
            return request.StatusCode switch
            {
                HttpStatusCode.Unauthorized =>
                    ProviderTestResultCategory.Unauthorized,
                HttpStatusCode.Forbidden =>
                    ProviderTestResultCategory.Forbidden,
                HttpStatusCode.NotFound =>
                    ProviderTestResultCategory.ModelNotFound,
                HttpStatusCode.TooManyRequests =>
                    ProviderTestResultCategory.RateLimited,
                HttpStatusCode.ServiceUnavailable =>
                    ProviderTestResultCategory.ProviderUnavailable,
                _ => ProviderTestResultCategory.ProviderUnavailable
            };
        }
        return exception switch
        {
            JsonException or InvalidDataException =>
                ProviderTestResultCategory.ResponseParseFailure,
            NotSupportedException =>
                ProviderTestResultCategory.UnsupportedCapability,
            _ => ProviderTestResultCategory.Unknown
        };
    }
}

public sealed class ModelProviderManager
{
    private readonly IModelProviderStore _store;
    private readonly IModelSecretStore _secrets;
    private readonly IModelProviderClient _client;

    public ModelProviderManager(
        IModelProviderStore store,
        IModelSecretStore secrets,
        IModelProviderClient client)
    {
        _store = store;
        _secrets = secrets;
        _client = client;
    }

    public IReadOnlyList<ModelProviderProfile> LoadProviders() =>
        _store.LoadModelProviders();

    public IReadOnlyList<ProviderModelRecord> LoadModels() =>
        _store.LoadProviderModels();

    public IReadOnlyList<ModelRoleAssignment> LoadAssignments() =>
        _store.LoadModelRoleAssignments();

    public ModelProviderProfile AddProvider(
        string displayName,
        ModelProviderProtocol protocol,
        string baseUrl,
        int timeoutSeconds,
        string apiKey,
        bool confirmRemoteHttp)
    {
        var providers = _store.LoadModelProviders().ToList();
        if (string.IsNullOrWhiteSpace(displayName) ||
            providers.Any(item => string.Equals(
                item.DisplayName,
                displayName.Trim(),
                StringComparison.OrdinalIgnoreCase)))
        {
            throw new InvalidOperationException(
                "Provider name is required and must be unique.");
        }
        ValidateEndpoint(baseUrl, confirmRemoteHttp);
        var now = DateTimeOffset.UtcNow;
        var providerId = Guid.NewGuid().ToString("D");
        var reference = "model-provider:" + providerId;
        _secrets.Save(apiKey, reference);
        var provider = new ModelProviderProfile(
            providerId,
            displayName.Trim(),
            protocol,
            baseUrl.Trim(),
            false,
            Math.Clamp(timeoutSeconds, 2, 120),
            now,
            now,
            null,
            ProviderConnectionStatus.NotVerified,
            "Saved. Test the provider before enabling it.",
            reference);
        providers.Add(provider);
        _store.SaveModelProviders(providers);
        return provider;
    }

    public void ReplaceApiKey(string providerId, string apiKey)
    {
        var provider = RequiredProvider(providerId);
        _secrets.Replace(apiKey, provider.SecretReference);
        SaveProvider(provider with
        {
            Enabled = false,
            UpdatedAt = DateTimeOffset.UtcNow,
            LastTestStatus = ProviderConnectionStatus.NotVerified,
            LastTestMessage = "API key replaced. Test before enabling."
        });
    }

    public void UpdateProvider(
        string providerId,
        string displayName,
        ModelProviderProtocol protocol,
        string baseUrl,
        int timeoutSeconds,
        bool confirmRemoteHttp)
    {
        var provider = RequiredProvider(providerId);
        var name = displayName.Trim();
        if (string.IsNullOrWhiteSpace(name) ||
            _store.LoadModelProviders().Any(item =>
                item.ProviderId != providerId &&
                string.Equals(
                    item.DisplayName,
                    name,
                    StringComparison.OrdinalIgnoreCase)))
        {
            throw new InvalidOperationException(
                "Provider name is required and must be unique.");
        }
        ValidateEndpoint(baseUrl, confirmRemoteHttp);
        SaveProvider(provider with
        {
            DisplayName = name,
            ProtocolType = protocol,
            BaseUrl = baseUrl.Trim(),
            RequestTimeoutSeconds = Math.Clamp(timeoutSeconds, 2, 120),
            Enabled = false,
            UpdatedAt = DateTimeOffset.UtcNow,
            LastTestStatus = ProviderConnectionStatus.NotVerified,
            LastTestMessage = "Configuration changed. Test before enabling."
        });
    }

    public void DeleteProvider(string providerId)
    {
        var provider = RequiredProvider(providerId);
        _secrets.Delete(provider.SecretReference);
        var removedIds = _store.LoadProviderModels()
            .Where(item => item.ProviderId == providerId)
            .Select(item => item.ModelRecordId)
            .ToHashSet(StringComparer.Ordinal);
        _store.SaveModelProviders(
            _store.LoadModelProviders()
                .Where(item => item.ProviderId != providerId)
                .ToArray());
        _store.SaveProviderModels(
            _store.LoadProviderModels()
                .Where(item => item.ProviderId != providerId)
                .ToArray());
        _store.SaveModelRoleAssignments(
            _store.LoadModelRoleAssignments()
                .Where(item => !removedIds.Contains(item.ModelRecordId))
                .ToArray());
    }

    public ProviderModelRecord AddManualModel(
        string providerId,
        string modelId,
        string? displayName = null)
    {
        _ = RequiredProvider(providerId);
        var models = _store.LoadProviderModels().ToList();
        if (string.IsNullOrWhiteSpace(modelId) ||
            models.Any(item =>
                item.ProviderId == providerId &&
                string.Equals(
                    item.ModelId,
                    modelId.Trim(),
                    StringComparison.Ordinal)))
        {
            throw new InvalidOperationException(
                "Model ID is required and must be unique for this provider.");
        }
        var now = DateTimeOffset.UtcNow;
        var model = new ProviderModelRecord(
            Guid.NewGuid().ToString("D"),
            providerId,
            modelId.Trim(),
            string.IsNullOrWhiteSpace(displayName)
                ? modelId.Trim()
                : displayName.Trim(),
            false,
            ModelRecordSource.Manual,
            ProviderModelStatus.Unverified,
            ModelCapabilityState.Supported,
            ModelCapabilityState.Unknown,
            ModelCapabilityState.Unknown,
            null,
            now,
            now,
            null);
        models.Add(model);
        _store.SaveProviderModels(models);
        return model;
    }

    public async Task<IReadOnlyList<ProviderModelRecord>> DiscoverModelsAsync(
        string providerId,
        CancellationToken cancellationToken)
    {
        var provider = RequiredProvider(providerId);
        var secret = _secrets.Retrieve(provider.SecretReference);
        var discovered = await _client.ListModelsAsync(
            provider,
            secret,
            cancellationToken);
        var models = _store.LoadProviderModels().ToList();
        foreach (var candidate in discovered)
        {
            if (!models.Any(item =>
                    item.ProviderId == providerId &&
                    item.ModelId == candidate.ModelId))
            {
                models.Add(candidate);
            }
        }
        _store.SaveProviderModels(models);
        return discovered;
    }

    public void SetProviderEnabled(string providerId, bool enabled)
    {
        var provider = RequiredProvider(providerId);
        if (enabled && provider.LastTestStatus != ProviderConnectionStatus.Ready)
        {
            throw new InvalidOperationException(
                "Test the provider successfully before enabling it.");
        }
        SaveProvider(provider with
        {
            Enabled = enabled,
            UpdatedAt = DateTimeOffset.UtcNow,
            LastTestStatus = enabled
                ? provider.LastTestStatus
                : ProviderConnectionStatus.Disabled
        });
    }

    public void SetModelEnabled(string modelRecordId, bool enabled)
    {
        var models = _store.LoadProviderModels().ToList();
        var index = models.FindIndex(item =>
            item.ModelRecordId == modelRecordId);
        if (index < 0)
        {
            throw new KeyNotFoundException("Model not found.");
        }
        models[index] = models[index] with
        {
            Enabled = enabled,
            Status = enabled
                ? ProviderModelStatus.Available
                : ProviderModelStatus.Disabled,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _store.SaveProviderModels(models);
        if (!enabled)
        {
            _store.SaveModelRoleAssignments(
                _store.LoadModelRoleAssignments()
                    .Where(item => item.ModelRecordId != modelRecordId)
                    .ToArray());
        }
    }

    public void UpdateModelDisplayName(
        string modelRecordId,
        string displayName)
    {
        var name = displayName.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new InvalidOperationException(
                "Model display name is required.");
        }
        var models = _store.LoadProviderModels().ToList();
        var index = models.FindIndex(item =>
            item.ModelRecordId == modelRecordId);
        if (index < 0)
        {
            throw new KeyNotFoundException("Model not found.");
        }
        models[index] = models[index] with
        {
            DisplayName = name,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _store.SaveProviderModels(models);
    }

    public void RemoveModel(string modelRecordId)
    {
        _store.SaveProviderModels(
            _store.LoadProviderModels()
                .Where(item => item.ModelRecordId != modelRecordId)
                .ToArray());
        _store.SaveModelRoleAssignments(
            _store.LoadModelRoleAssignments()
                .Where(item => item.ModelRecordId != modelRecordId)
                .ToArray());
    }

    public void SetPrimary(string modelRecordId)
    {
        RequireSelectable(modelRecordId);
        var assignments = _store.LoadModelRoleAssignments()
            .Where(item =>
                item.Role != ModelRole.Primary &&
                item.ModelRecordId != modelRecordId)
            .ToList();
        assignments.Add(new ModelRoleAssignment(
            Guid.NewGuid().ToString("D"),
            modelRecordId,
            ModelRole.Primary,
            0,
            DateTimeOffset.UtcNow));
        _store.SaveModelRoleAssignments(assignments);
    }

    public void AddFallback(string modelRecordId)
    {
        RequireSelectable(modelRecordId);
        var assignments = _store.LoadModelRoleAssignments().ToList();
        if (assignments.Any(item => item.ModelRecordId == modelRecordId))
        {
            return;
        }
        var position = assignments
            .Where(item => item.Role == ModelRole.Fallback)
            .Select(item => item.Position)
            .DefaultIfEmpty(0)
            .Max() + 1;
        assignments.Add(new ModelRoleAssignment(
            Guid.NewGuid().ToString("D"),
            modelRecordId,
            ModelRole.Fallback,
            position,
            DateTimeOffset.UtcNow));
        _store.SaveModelRoleAssignments(assignments);
    }

    public void MoveFallback(string modelRecordId, int delta)
    {
        var all = _store.LoadModelRoleAssignments().ToList();
        var fallbacks = all
            .Where(item => item.Role == ModelRole.Fallback)
            .OrderBy(item => item.Position)
            .ToList();
        var index = fallbacks.FindIndex(item =>
            item.ModelRecordId == modelRecordId);
        var destination = Math.Clamp(index + delta, 0, fallbacks.Count - 1);
        if (index < 0 || destination == index)
        {
            return;
        }
        (fallbacks[index], fallbacks[destination]) =
            (fallbacks[destination], fallbacks[index]);
        var now = DateTimeOffset.UtcNow;
        var reordered = fallbacks.Select((item, position) =>
            item with { Position = position + 1, UpdatedAt = now });
        _store.SaveModelRoleAssignments(
            all.Where(item => item.Role == ModelRole.Primary)
                .Concat(reordered)
                .ToArray());
    }

    public void RemoveRole(string modelRecordId)
    {
        _store.SaveModelRoleAssignments(
            _store.LoadModelRoleAssignments()
                .Where(item => item.ModelRecordId != modelRecordId)
                .ToArray());
    }

    public IReadOnlyList<ModelProviderSelection> SelectionChain()
    {
        var providers = _store.LoadModelProviders()
            .ToDictionary(item => item.ProviderId, StringComparer.Ordinal);
        var models = _store.LoadProviderModels()
            .ToDictionary(item => item.ModelRecordId, StringComparer.Ordinal);
        return _store.LoadModelRoleAssignments()
            .OrderBy(item => item.Role == ModelRole.Primary ? 0 : 1)
            .ThenBy(item => item.Position)
            .Select(item =>
            {
                if (!models.TryGetValue(item.ModelRecordId, out var model) ||
                    !providers.TryGetValue(model.ProviderId, out var provider))
                {
                    return null;
                }
                return provider.Enabled &&
                    provider.LastTestStatus == ProviderConnectionStatus.Ready &&
                    model.Enabled &&
                    model.Status == ProviderModelStatus.Available
                    ? new ModelProviderSelection(provider, model)
                    : null;
            })
            .OfType<ModelProviderSelection>()
            .ToArray();
    }

    public async Task<ModelGenerationOutcome> GenerateTextWithFallbackAsync(
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken)
    {
        Exception? lastFailure = null;
        foreach (var selection in SelectionChain())
        {
            try
            {
                var secret = _secrets.Retrieve(
                    selection.Provider.SecretReference);
                var text = await _client.GenerateTextAsync(
                    selection.Provider,
                    selection.Model,
                    secret,
                    systemInstruction,
                    userText,
                    cancellationToken);
                return new ModelGenerationOutcome(text, selection);
            }
            catch (Exception exception) when (FallbackEligible(exception))
            {
                lastFailure = exception;
            }
        }
        throw lastFailure ?? new InvalidOperationException(
            "No Ready primary model is configured.");
    }

    public async Task<(ModelToolDecision Decision, ModelProviderSelection Selection)>
        RequestToolDecisionWithFallbackAsync(
            string systemInstruction,
            string userText,
            CancellationToken cancellationToken)
    {
        Exception? lastFailure = null;
        foreach (var selection in SelectionChain())
        {
            try
            {
                var secret = _secrets.Retrieve(
                    selection.Provider.SecretReference);
                var decision = await _client.RequestToolDecisionAsync(
                    selection.Provider,
                    selection.Model,
                    secret,
                    systemInstruction,
                    userText,
                    cancellationToken);
                return (decision, selection);
            }
            catch (Exception exception) when (FallbackEligible(exception))
            {
                lastFailure = exception;
            }
        }
        throw lastFailure ?? new InvalidOperationException(
            "No Ready tool-capable model is configured.");
    }

    public async Task<ProviderClientTestResult> TestConnectionAsync(
        string providerId,
        string modelRecordId,
        CancellationToken cancellationToken)
    {
        var provider = RequiredProvider(providerId);
        var model = _store.LoadProviderModels().Single(item =>
            item.ModelRecordId == modelRecordId &&
            item.ProviderId == providerId);
        var started = DateTimeOffset.UtcNow;
        ProviderClientTestResult result;
        try
        {
            var secret = _secrets.Retrieve(provider.SecretReference);
            result = await _client.TestConnectionAsync(
                provider,
                model,
                secret,
                cancellationToken);
        }
        catch (Exception exception)
        {
            result = new ProviderClientTestResult(
                ProviderTestResultCategory.SecretStoreFailure,
                SensitiveDataRedactor.Redact(exception.Message),
                null);
        }
        var completed = DateTimeOffset.UtcNow;
        var status = MapStatus(result.Category);
        SaveProvider(provider with
        {
            Enabled = result.IsReady && provider.Enabled,
            UpdatedAt = completed,
            LastTestedAt = completed,
            LastTestStatus = status,
            LastTestMessage = SensitiveDataRedactor.Redact(result.Message)
        });
        _store.AppendProviderTestEvent(new ProviderTestEvent(
            Guid.NewGuid().ToString("D"),
            providerId,
            modelRecordId,
            started,
            completed,
            result.Category,
            SensitiveDataRedactor.Redact(result.Message),
            result.LatencyMilliseconds));
        return result;
    }

    private static void ValidateEndpoint(
        string baseUrl,
        bool confirmRemoteHttp)
    {
        var safety = ProviderEndpointValidator.Validate(baseUrl);
        if (safety == ProviderEndpointSafety.Invalid)
        {
            throw new InvalidOperationException("The Base URL is invalid.");
        }
        if (safety == ProviderEndpointSafety.RemoteHttpConfirmationRequired &&
            !confirmRemoteHttp)
        {
            throw new InvalidOperationException(
                "Remote HTTP requires explicit confirmation.");
        }
    }

    private ModelProviderProfile RequiredProvider(string providerId)
    {
        return _store.LoadModelProviders().SingleOrDefault(item =>
            item.ProviderId == providerId)
            ?? throw new KeyNotFoundException("Provider not found.");
    }

    private void SaveProvider(ModelProviderProfile updated)
    {
        var providers = _store.LoadModelProviders().ToList();
        var index = providers.FindIndex(item =>
            item.ProviderId == updated.ProviderId);
        if (index < 0)
        {
            throw new KeyNotFoundException("Provider not found.");
        }
        providers[index] = updated;
        _store.SaveModelProviders(providers);
    }

    private void RequireSelectable(string modelRecordId)
    {
        var model = _store.LoadProviderModels().SingleOrDefault(item =>
            item.ModelRecordId == modelRecordId)
            ?? throw new KeyNotFoundException("Model not found.");
        var provider = RequiredProvider(model.ProviderId);
        if (!provider.Enabled ||
            provider.LastTestStatus != ProviderConnectionStatus.Ready ||
            !model.Enabled ||
            model.Status != ProviderModelStatus.Available)
        {
            throw new InvalidOperationException(
                "Only enabled models from Ready providers are selectable.");
        }
    }

    private static ProviderConnectionStatus MapStatus(
        ProviderTestResultCategory result)
    {
        return result switch
        {
            ProviderTestResultCategory.Ready =>
                ProviderConnectionStatus.Ready,
            ProviderTestResultCategory.Unauthorized =>
                ProviderConnectionStatus.Unauthorized,
            ProviderTestResultCategory.RateLimited =>
                ProviderConnectionStatus.RateLimited,
            ProviderTestResultCategory.ProviderUnavailable =>
                ProviderConnectionStatus.Unavailable,
            _ => ProviderConnectionStatus.Degraded
        };
    }

    private static bool FallbackEligible(Exception exception)
    {
        if (exception is TaskCanceledException)
        {
            return true;
        }
        if (exception is not HttpRequestException request)
        {
            return false;
        }
        return request.StatusCode is null ||
            request.StatusCode == HttpStatusCode.RequestTimeout ||
            request.StatusCode == HttpStatusCode.TooManyRequests ||
            (int)request.StatusCode >= 500;
    }
}

public interface IReadOnlyLongbridgeToolGateway
{
    Task<ModelToolResult> ExecuteAsync(
        ReadOnlyModelTool tool,
        IReadOnlyDictionary<string, string> arguments,
        CancellationToken cancellationToken);
}

public sealed class ModelLongbridgeCoordinator
{
    private readonly IReadOnlyLongbridgeToolGateway _gateway;

    public ModelLongbridgeCoordinator(IReadOnlyLongbridgeToolGateway gateway)
    {
        _gateway = gateway;
    }

    public Task<ModelToolResult> ExecuteDecisionAsync(
        ModelToolDecision decision,
        CancellationToken cancellationToken)
    {
        if (!Enum.TryParse<ReadOnlyModelTool>(
                decision.Tool,
                ignoreCase: false,
                out var tool))
        {
            throw new InvalidOperationException(
                "Trading and account-mutation model tools are rejected.");
        }
        return _gateway.ExecuteAsync(tool, decision.Arguments, cancellationToken);
    }
}

public sealed class FixtureReadOnlyLongbridgeToolGateway :
    IReadOnlyLongbridgeToolGateway
{
    private readonly ILongbridgeDataService _fixtures;

    public FixtureReadOnlyLongbridgeToolGateway(
        ILongbridgeDataService fixtures)
    {
        _fixtures = fixtures;
    }

    public Task<ModelToolResult> ExecuteAsync(
        ReadOnlyModelTool tool,
        IReadOnlyDictionary<string, string> arguments,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var snapshot = _fixtures.LoadFixtureSnapshot();
        return Task.FromResult(tool switch
        {
            ReadOnlyModelTool.Quote => Quote(snapshot, arguments),
            ReadOnlyModelTool.MarketStatus => MarketStatus(snapshot),
            ReadOnlyModelTool.SymbolLookup => SymbolLookup(snapshot, arguments),
            _ => throw new InvalidOperationException(
                "Unsupported read-only model tool.")
        });
    }

    private static ModelToolResult Quote(
        LongbridgeDataSnapshot snapshot,
        IReadOnlyDictionary<string, string> arguments)
    {
        var symbol = Required(arguments, "symbol");
        if (!string.Equals(
                symbol,
                snapshot.CurrentSnapshot.Symbol,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new KeyNotFoundException(
                "The fixture has no quote for the requested symbol.");
        }
        return new ModelToolResult(
            "Quote",
            new Dictionary<string, string>
            {
                ["symbol"] = snapshot.CurrentSnapshot.Symbol,
                ["last_price"] = snapshot.CurrentSnapshot.Last.ToString(
                    System.Globalization.CultureInfo.InvariantCulture),
                ["source"] = snapshot.CurrentSnapshot.SourceVersion
            });
    }

    private static ModelToolResult MarketStatus(
        LongbridgeDataSnapshot snapshot)
    {
        return new ModelToolResult(
            "MarketStatus",
            new Dictionary<string, string>
            {
                ["market"] = snapshot.MarketStatus.Market,
                ["status"] = snapshot.MarketStatus.Session,
                ["source"] = snapshot.MarketStatus.SourceVersion
            });
    }

    private static ModelToolResult SymbolLookup(
        LongbridgeDataSnapshot snapshot,
        IReadOnlyDictionary<string, string> arguments)
    {
        var symbol = Required(arguments, "symbol");
        var security = snapshot.SecurityList.Securities.FirstOrDefault(item =>
            string.Equals(
                item.Symbol,
                symbol,
                StringComparison.OrdinalIgnoreCase));
        return new ModelToolResult(
            "SymbolLookup",
            new Dictionary<string, string>
            {
                ["symbol"] = symbol,
                ["found"] = security is null ? "false" : "true",
                ["name"] = security?.Name ?? string.Empty
            });
    }

    private static string Required(
        IReadOnlyDictionary<string, string> arguments,
        string key)
    {
        return arguments.TryGetValue(key, out var value) &&
            !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new InvalidOperationException(
                $"Read-only tool argument is required: {key}");
    }
}

public sealed class FixtureModelProviderClient : IModelProviderClient
{
    private readonly IReadOnlyList<ProviderModelRecord> _models;
    private readonly string _text;
    private readonly ModelToolDecision _decision;

    public FixtureModelProviderClient(
        IReadOnlyList<ProviderModelRecord> models,
        string text,
        ModelToolDecision decision)
    {
        _models = models;
        _text = text;
        _decision = decision;
    }

    public Task<IReadOnlyList<ProviderModelRecord>> ListModelsAsync(
        ModelProviderProfile provider,
        string apiKey,
        CancellationToken cancellationToken) =>
        Task.FromResult(_models);

    public Task<ProviderClientTestResult> TestConnectionAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        CancellationToken cancellationToken) =>
        Task.FromResult(new ProviderClientTestResult(
            ProviderTestResultCategory.Ready,
            "Fixture provider is ready.",
            1));

    public Task<string> GenerateTextAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken) =>
        Task.FromResult(_text);

    public Task<JsonObject> GenerateStructuredResponseAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken) =>
        Task.FromResult(new JsonObject
        {
            ["tool"] = _decision.Tool,
            ["arguments"] = JsonSerializer.SerializeToNode(_decision.Arguments)
        });

    public Task<ModelToolDecision> RequestToolDecisionAsync(
        ModelProviderProfile provider,
        ProviderModelRecord model,
        string apiKey,
        string systemInstruction,
        string userText,
        CancellationToken cancellationToken) =>
        Task.FromResult(_decision);
}
