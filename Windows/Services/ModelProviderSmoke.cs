using System.Net;
using System.Net.Http;
using System.IO;
using System.Reflection;
using System.Text;

namespace CytisusTrading.Windows;

public static class ModelProviderSmoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            Directory.CreateDirectory(rootDirectory);
            File.WriteAllText(
                Path.Combine(rootDirectory, "schema-version.json"),
                "{\"version\":5}\n",
                new UTF8Encoding(false));
            File.WriteAllText(
                Path.Combine(rootDirectory, "migrations.json"),
                "[]\n",
                new UTF8Encoding(false));

            var store = new JsonFilePersistentStore(rootDirectory);
            store.InitializeSchema();
            Require(
                store.GetSchemaVersion().Version == 7 &&
                store.GetMigrationRecords().Any(item =>
                    item.FromVersion == 5 && item.ToVersion == 8),
                "The cumulative v1.1.0 to v1.1.3 migration did not run.");

            var secrets = new InMemoryModelSecretStore();
            secrets.Save("first", "secret:test");
            Require(
                secrets.Retrieve("secret:test") == "first",
                "Secret save or retrieve failed.");
            secrets.Replace("second", "secret:test");
            Require(
                secrets.Retrieve("secret:test") == "second",
                "Secret replacement failed.");
            secrets.Delete("secret:test");
            RequireThrows(
                () => secrets.Retrieve("secret:test"),
                "Secret deletion failed.");

            var now = DateTimeOffset.UtcNow;
            var fixtureModel = new ProviderModelRecord(
                "fixture-discovered",
                "placeholder",
                "fixture-tool-model",
                "Fixture Tool Model",
                false,
                ModelRecordSource.Discovered,
                ProviderModelStatus.Disabled,
                ModelCapabilityState.Supported,
                ModelCapabilityState.Supported,
                ModelCapabilityState.Supported,
                8192,
                now,
                now,
                now);
            var fixtureClient = new FixtureModelProviderClient(
                new[] { fixtureModel },
                "READY",
                new ModelToolDecision(
                    "Quote",
                    new Dictionary<string, string>
                    {
                        ["symbol"] = "AAPL.US"
                    }));
            var manager = new ModelProviderManager(
                store,
                secrets,
                fixtureClient);

            var provider = manager.AddProvider(
                "Fixture OpenAI",
                ModelProviderProtocol.OpenAICompatible,
                "https://models.example.invalid/v1",
                15,
                "fixture-secret-1",
                false);
            var model = manager.AddManualModel(
                provider.ProviderId,
                "fixture-tool-model");
            var test = manager.TestConnectionAsync(
                    provider.ProviderId,
                    model.ModelRecordId,
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            Require(test.IsReady, "Fixture connectivity test failed.");
            manager.SetProviderEnabled(provider.ProviderId, true);
            manager.SetModelEnabled(model.ModelRecordId, true);
            manager.SetPrimary(model.ModelRecordId);

            var fallbackProvider = manager.AddProvider(
                "Fixture Gemini",
                ModelProviderProtocol.GeminiCompatible,
                "https://generativelanguage.example.invalid/v1beta",
                15,
                "fixture-secret-2",
                false);
            var fallback = manager.AddManualModel(
                fallbackProvider.ProviderId,
                "models/fixture-gemini");
            Require(
                manager.TestConnectionAsync(
                        fallbackProvider.ProviderId,
                        fallback.ModelRecordId,
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .IsReady,
                "Fallback fixture connectivity failed.");
            manager.SetProviderEnabled(fallbackProvider.ProviderId, true);
            manager.SetModelEnabled(fallback.ModelRecordId, true);
            manager.AddFallback(fallback.ModelRecordId);
            Require(
                manager.SelectionChain().Count == 2,
                "Primary and fallback ordering failed.");
            manager.SetProviderEnabled(fallbackProvider.ProviderId, false);
            Require(
                manager.SelectionChain().Count == 1,
                "Disabled provider was not skipped.");
            Require(
                manager.GenerateTextWithFallbackAsync(
                        "Fixed fixture instruction.",
                        "Minimal fixture generation.",
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .Text == "READY",
                "Minimal fixture text generation failed.");

            var metadata = File.ReadAllText(
                Path.Combine(rootDirectory, "model-providers.json"),
                Encoding.UTF8);
            Require(
                !metadata.Contains("fixture-secret-1", StringComparison.Ordinal) &&
                !metadata.Contains("fixture-secret-2", StringComparison.Ordinal),
                "Plaintext API key entered provider metadata.");
            Require(
                SensitiveDataRedactor.Redact(
                    "{\"api_key\":\"secret-value\",\"x-api-key\":\"other\"}")
                .Contains("[REDACTED]", StringComparison.Ordinal) &&
                !SensitiveDataRedactor.Redact("apiKey=secret-value")
                    .Contains("secret-value", StringComparison.Ordinal),
                "API key redaction failed.");

            VerifyRequestConstruction(provider, model);
            VerifyEndpointSafety();
            VerifyFixtureDiscovery(provider);
            VerifyConnectivityMapping(provider, model);

            var selected = manager.SelectionChain().Single();
            var toolModel = selected.Model with
            {
                SupportsToolCalling = ModelCapabilityState.Supported,
                SupportsStructuredOutput = ModelCapabilityState.Supported
            };
            var decision = fixtureClient.RequestToolDecisionAsync(
                    selected.Provider,
                    toolModel,
                    "in-memory-only",
                    "Use only allowlisted read-only tools.",
                    "Get an AAPL quote.",
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            var coordinator = new ModelLongbridgeCoordinator(
                new FixtureReadOnlyGateway());
            var quote = coordinator.ExecuteDecisionAsync(
                    decision,
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            Require(
                quote.Tool == "Quote" &&
                quote.Result["symbol"] == "AAPL.US",
                "Read-only Longbridge quote flow failed.");
            RequireThrows(
                () => coordinator.ExecuteDecisionAsync(
                        new ModelToolDecision(
                            "BrokerOrder",
                            new Dictionary<string, string>()),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult(),
                "Trading tool was not rejected.");

            Console.WriteLine("Model provider smoke passed.");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                SensitiveDataRedactor.Redact(exception.ToString()));
            return 1;
        }
    }

    private static void VerifyRequestConstruction(
        ModelProviderProfile provider,
        ProviderModelRecord model)
    {
        var secret = "request-only-secret";
        foreach (var protocol in Enum.GetValues<ModelProviderProtocol>())
        {
            var configured = provider with
            {
                ProtocolType = protocol,
                BaseUrl = protocol == ModelProviderProtocol.GeminiCompatible
                    ? "https://generativelanguage.example.invalid/v1beta"
                    : "https://models.example.invalid/v1"
            };
            var configuredModel = model with
            {
                ModelId = protocol == ModelProviderProtocol.GeminiCompatible
                    ? "models/fixture-gemini"
                    : "fixture-model"
            };
            var request = ModelProviderRequestFactory.BuildGenerateText(
                configured,
                configuredModel,
                secret,
                "Fixed system instruction.",
                "Minimal fixture request.");
            Require(
                request.Method == HttpMethod.Post &&
                request.Uri.Scheme == Uri.UriSchemeHttps &&
                request.Body is not null &&
                !request.Body.Contains(secret, StringComparison.Ordinal),
                $"{protocol} request construction failed.");
        }
    }

    private static void VerifyEndpointSafety()
    {
        Require(
            ProviderEndpointValidator.Validate("https://example.invalid/v1") ==
                ProviderEndpointSafety.Secure &&
            ProviderEndpointValidator.Validate("http://localhost:11434/v1") ==
                ProviderEndpointSafety.LocalHttp &&
            ProviderEndpointValidator.Validate("http://example.invalid/v1") ==
                ProviderEndpointSafety.RemoteHttpConfirmationRequired,
            "Base URL safety classification failed.");
    }

    private static void VerifyFixtureDiscovery(
        ModelProviderProfile provider)
    {
        var fixture = ReadEmbedded("openai-models.json");
        using var http = new HttpClient(new FixtureHttpHandler(
            HttpStatusCode.OK,
            fixture));
        var client = new HttpModelProviderClient(http);
        var models = client.ListModelsAsync(
                provider,
                "in-memory-only",
                CancellationToken.None)
            .GetAwaiter()
            .GetResult();
        Require(
            models.Count == 2 &&
            models.All(item =>
                item.Source == ModelRecordSource.Discovered &&
                !item.Enabled),
            "Model-discovery fixture parsing failed.");
    }

    private static void VerifyConnectivityMapping(
        ModelProviderProfile provider,
        ProviderModelRecord model)
    {
        using var http = new HttpClient(new FixtureHttpHandler(
            HttpStatusCode.Unauthorized,
            "{\"error\":\"unauthorized\"}"));
        var client = new HttpModelProviderClient(http);
        var result = client.TestConnectionAsync(
                provider,
                model,
                "in-memory-only",
                CancellationToken.None)
            .GetAwaiter()
            .GetResult();
        Require(
            result.Category == ProviderTestResultCategory.Unauthorized,
            "Connectivity status mapping failed.");
    }

    private static string ReadEmbedded(string fileName)
    {
        var assembly = typeof(ModelProviderSmoke).Assembly;
        var name = assembly.GetManifestResourceNames().Single(item =>
            item.EndsWith(fileName, StringComparison.OrdinalIgnoreCase));
        using var stream = assembly.GetManifestResourceStream(name)
            ?? throw new InvalidDataException("Fixture stream is missing.");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void RequireThrows(Action action, string message)
    {
        try
        {
            action();
        }
        catch
        {
            return;
        }
        throw new InvalidOperationException(message);
    }

    private sealed class FixtureHttpHandler : HttpMessageHandler
    {
        private readonly HttpStatusCode _statusCode;
        private readonly string _body;

        public FixtureHttpHandler(HttpStatusCode statusCode, string body)
        {
            _statusCode = statusCode;
            _body = body;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new HttpResponseMessage(_statusCode)
            {
                Content = new StringContent(
                    _body,
                    Encoding.UTF8,
                    "application/json")
            });
        }
    }

    private sealed class FixtureReadOnlyGateway : IReadOnlyLongbridgeToolGateway
    {
        public Task<ModelToolResult> ExecuteAsync(
            ReadOnlyModelTool tool,
            IReadOnlyDictionary<string, string> arguments,
            CancellationToken cancellationToken)
        {
            return tool switch
            {
                ReadOnlyModelTool.Quote => Task.FromResult(
                    new ModelToolResult(
                        "Quote",
                        new Dictionary<string, string>
                        {
                            ["symbol"] = arguments["symbol"],
                            ["last_price"] = "215.25",
                            ["source"] = "synthetic-fixture"
                        })),
                ReadOnlyModelTool.MarketStatus => Task.FromResult(
                    new ModelToolResult(
                        "MarketStatus",
                        new Dictionary<string, string>
                        {
                            ["market"] = arguments["market"],
                            ["status"] = "Open"
                        })),
                ReadOnlyModelTool.SymbolLookup => Task.FromResult(
                    new ModelToolResult(
                        "SymbolLookup",
                        new Dictionary<string, string>
                        {
                            ["symbol"] = arguments["symbol"],
                            ["found"] = "true"
                        })),
                _ => throw new InvalidOperationException(
                    "Unsupported read-only tool.")
            };
        }
    }
}
