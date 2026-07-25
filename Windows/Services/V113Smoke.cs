using System.IO;

namespace CytisusTrading.Windows;

public static class V113Smoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            Directory.CreateDirectory(rootDirectory);
            var store = new JsonFilePersistentStore(rootDirectory);
            store.InitializeSchema();
            Require(
                store.GetSchemaVersion().Version == 8,
                "Schema migration failed.");

            var runner = new V113FakeRunner();
            var adapter = new LongbridgeCliAdapter(runner);
            var authentication = new LongbridgeAuthenticationService(
                adapter,
                runner,
                store,
                store);
            var executable = Environment.ProcessPath ??
                throw new InvalidOperationException("Process path is unavailable.");

            var inspection = adapter.InspectAsync(
                    executable,
                    TimeSpan.FromSeconds(2),
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            Require(
                inspection.Capabilities is not null,
                "CLI capabilities were not discovered.");
            var capabilities = inspection.Capabilities ??
                throw new InvalidOperationException(
                    "CLI capabilities were not discovered.");
            var commands = capabilities.Commands.ToDictionary(
                item => item.Operation,
                item => string.Join(" ", item.Arguments));
            Require(
                commands[LongbridgeOperation.Status] ==
                    "auth status --format json" &&
                commands[LongbridgeOperation.Connectivity] ==
                    "check --format json" &&
                commands[LongbridgeOperation.CurrentSnapshot] ==
                    "quote {symbol} --format json" &&
                commands[LongbridgeOperation.HistoricalBars] ==
                    "kline history {symbol} --start {start} --end {end} --format json" &&
                commands[LongbridgeOperation.SecurityList] ==
                    "security-list {market} --format json" &&
                commands[LongbridgeOperation.BrokerPositions] ==
                    "positions --format json",
                "Canonical command mapping failed.");
            Require(
                !commands.Values.Any(value =>
                    value.Contains("--output", StringComparison.Ordinal) ||
                    value.Contains("--json", StringComparison.Ordinal) ||
                    value.StartsWith("market ", StringComparison.Ordinal) ||
                    value.StartsWith("account ", StringComparison.Ordinal)),
                "A provisional CLI command escaped isolation.");

            var state = authentication.CheckAsync(
                    executable,
                    TimeSpan.FromSeconds(2),
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            Require(
                state.Status == LongbridgeStatusState.ReadyPaper &&
                state.AccountChannel == "lb_papertrading" &&
                state.LongbridgePaperAvailable,
                "Paper channel classification failed.");

            var deviceState = authentication.SignInAsync(
                    executable,
                    TimeSpan.FromSeconds(2),
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            Require(
                deviceState.AuthorizationUrl ==
                    "https://open.longbridge.com/device" &&
                deviceState.ShortCode == "ABCD-EFGH",
                "Device authorization progress parsing failed.");

            var codeState = authentication.SignInWithAuthorizationCodeAsync(
                    executable,
                    "CODE-1234",
                    TimeSpan.FromSeconds(2),
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            Require(
                codeState.Status == LongbridgeStatusState.ReadyPaper &&
                !authentication.HasAuthorizationCodeInMemory &&
                runner.RecordedArguments.All(value =>
                    !value.Contains("CODE-1234", StringComparison.Ordinal)),
                "Authorization-code memory or diagnostic clearing failed.");

            var paperFacts = LongbridgeAuthStatusParser.Parse(
                """
                {"authenticated":true,"account_environment":"Paper","account_channel":"lb_papertrading","permissions":["market_data"]}
                """);
            var liveFacts = LongbridgeAuthStatusParser.Parse(
                """
                {"authenticated":true,"account_environment":"Live","account_channel":"lb_live","permissions":[]}
                """);
            var refreshFacts = LongbridgeAuthStatusParser.Parse(
                """
                {"authenticated":true,"refresh_pending":true,"account_channel":"lb_papertrading"}
                """);
            Require(
                paperFacts.Authenticated &&
                liveFacts.Channel == "lb_live" &&
                refreshFacts.RefreshPending,
                "Authentication JSON parsing failed.");

            runner.AuthStatusOutput =
                """{"authenticated":true,"account_environment":"Live","account_channel":"lb_live","permissions":[]}""";
            Require(
                authentication.CheckAsync(
                        executable,
                        TimeSpan.FromSeconds(2),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .Status == LongbridgeStatusState.ReadyLive,
                "Live channel classification failed.");
            runner.AuthStatusOutput =
                """{"authenticated":true,"account_environment":"Unknown","account_channel":"future_channel","permissions":[]}""";
            Require(
                authentication.CheckAsync(
                        executable,
                        TimeSpan.FromSeconds(2),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .Status == LongbridgeStatusState.ReadyUnknownChannel,
                "Unknown channel classification failed.");
            runner.AuthStatusOutput =
                """{"authenticated":true,"refresh_pending":true,"account_environment":"Paper","account_channel":"lb_papertrading","permissions":[]}""";
            Require(
                authentication.CheckAsync(
                        executable,
                        TimeSpan.FromSeconds(2),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .Status == LongbridgeStatusState.RefreshPending,
                "Refresh-pending classification failed.");
            runner.AuthStatusOutput =
                """{"authenticated":false,"expired":true,"account_environment":"Paper","account_channel":"lb_papertrading","permissions":[]}""";
            Require(
                authentication.CheckAsync(
                        executable,
                        TimeSpan.FromSeconds(2),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .Status == LongbridgeStatusState.Expired,
                "Expired classification failed.");
            runner.AuthStatusOutput =
                """{"authenticated":true,"account_environment":"Paper","account_channel":"lb_papertrading","permissions":[]}""";
            runner.VersionOutput = "longbridge 0.19.9";
            Require(
                authentication.CheckAsync(
                        executable,
                        TimeSpan.FromSeconds(2),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult()
                    .Status == LongbridgeStatusState.UpdateRequired,
                "Minimum-version classification failed.");
            runner.VersionOutput = "longbridge 0.20.0";

            var redacted = SensitiveDataRedactor.Redact(
                """{"access_token":"synthetic","authorization_code":"CODE-1234","account_id":"A123"}""");
            Require(
                !redacted.Contains("synthetic", StringComparison.Ordinal) &&
                !redacted.Contains("CODE-1234", StringComparison.Ordinal) &&
                !redacted.Contains("A123", StringComparison.Ordinal),
                "Sensitive-field redaction failed.");

            foreach (var cliState in Enum.GetValues<LongbridgeStatusState>())
            {
                Require(
                    LongbridgePaperPolicy.CanRun(
                        LongbridgePaperMode.LocalPaper,
                        cliState),
                    $"Local Paper was blocked by {cliState}.");
            }
            Require(
                LongbridgePaperPolicy.CanRun(
                    LongbridgePaperMode.LongbridgePaper,
                    LongbridgeStatusState.ReadyPaper) &&
                !LongbridgePaperPolicy.CanRun(
                    LongbridgePaperMode.LongbridgePaper,
                    LongbridgeStatusState.ReadyLive) &&
                !LongbridgePaperPolicy.CanRun(
                    LongbridgePaperMode.LongbridgePaper,
                    LongbridgeStatusState.ReadyUnknownChannel),
                "Longbridge Paper readiness policy failed.");

            var now = DateTimeOffset.Parse("2026-07-25T00:00:00Z");
            var order = new BrokerOrder(
                1,
                "order-v113",
                "correlation-v113",
                "AAPL.US",
                OrderSide.Buy,
                1,
                200,
                StrategyMode.Live,
                BrokerOrderState.Accepted,
                now,
                now.AddMinutes(1),
                0,
                "Prepared");
            var liveAdapter = new LongbridgeLiveBrokerAdapter(
                new LongbridgeLiveCommandFactory());
            var liveResult = liveAdapter.Submit(
                order,
                new LiveAdapterConfiguration(
                    true,
                    false,
                    executable,
                    TimeSpan.FromSeconds(2),
                    new LongbridgeExecutionCapability(
                        1,
                        "synthetic-v1.1.3",
                        true,
                        true,
                        true,
                        new[] { "synthetic-order", "{symbol}", "{quantity}" },
                        "Synthetic fixture only.")));
            Require(
                liveResult.State == LiveSubmissionState.Rejected &&
                liveAdapter.SubmissionAttempts == 0,
                "The Live adapter did not remain rejecting.");

            var metadataText = File.ReadAllText(
                Path.Combine(rootDirectory, "longbridge-connection.json"));
            Require(
                metadataText.Contains(
                    "\"account_channel\"",
                    StringComparison.Ordinal) &&
                !metadataText.Contains("access_token", StringComparison.Ordinal) &&
                !metadataText.Contains("authorization_code", StringComparison.Ordinal),
                "Longbridge persistence boundary failed.");

            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                SensitiveDataRedactor.Redact(exception.Message));
            return 1;
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private sealed class V113FakeRunner : IReadOnlyProcessRunner
    {
        public List<string> RecordedArguments { get; } = new();
        public string VersionOutput { get; set; } = "longbridge 0.20.0";
        public string AuthStatusOutput { get; set; } =
            """{"authenticated":true,"account_environment":"Paper","account_channel":"lb_papertrading","permissions":["market_data","positions"]}""";

        public Task<CliProcessResult> RunAsync(
            string executablePath,
            IReadOnlyList<string> arguments,
            TimeSpan timeout,
            int outputLimit,
            CancellationToken cancellationToken)
        {
            RecordedArguments.Add(RedactedArguments(arguments));
            var command = string.Join(" ", arguments);
            var output = command switch
            {
                "--version" => VersionOutput,
                "--help" => "auth check quote kline security-list positions",
                "auth --help" => "Commands: login logout status",
                "auth status --help" => "Usage: auth status --format FORMAT",
                "check --help" => "Usage: check --format FORMAT",
                "quote --help" => "Usage: quote SYMBOL --format FORMAT",
                "kline history --help" =>
                    "Usage: kline history SYMBOL --start DATE --end DATE --format FORMAT",
                "security-list --help" =>
                    "Usage: security-list MARKET --format FORMAT",
                "positions --help" => "Usage: positions --format FORMAT",
                "auth status --format json" => AuthStatusOutput,
                "check --format json" => """{"ok":true}""",
                "auth login" =>
                    "Open https://open.longbridge.com/device and enter code ABCD-EFGH",
                _ when arguments.Count >= 4 &&
                    arguments[0] == "auth" &&
                    arguments[1] == "login" &&
                    arguments[2] == "--auth-code" => """{"ok":true}""",
                _ => string.Empty
            };
            var exitCode = output.Length == 0 ? 2 : 0;
            return Task.FromResult(new CliProcessResult(
                exitCode,
                output,
                exitCode == 0 ? string.Empty : "Unsupported fixture command.",
                false,
                false,
                false,
                TimeSpan.FromMilliseconds(1)));
        }

        private static string RedactedArguments(
            IReadOnlyList<string> arguments)
        {
            var values = arguments.ToArray();
            var codeIndex = Array.IndexOf(values, "--auth-code");
            if (codeIndex >= 0 && codeIndex + 1 < values.Length)
            {
                values[codeIndex + 1] = "[REDACTED]";
            }
            return string.Join(" ", values);
        }
    }
}
