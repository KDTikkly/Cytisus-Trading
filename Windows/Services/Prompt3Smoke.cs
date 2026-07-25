using System.IO;

namespace CytisusTrading.Windows;

public static class Prompt3Smoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            Directory.CreateDirectory(rootDirectory);
            var registry = new StrategyRegistryService();
            var (manifest, parameters) = registry.LoadOfficial();
            if (!registry.Validate(
                    manifest,
                    parameters,
                    Array.Empty<string>(),
                    null).IsValid)
            {
                return 2;
            }

            if (registry.Validate(
                    manifest,
                    parameters,
                    new[] { manifest.StrategyId },
                    null).IsValid ||
                registry.Validate(
                    manifest with { ProtocolVersion = 99 },
                    parameters,
                    Array.Empty<string>(),
                    null).IsValid ||
                registry.Validate(
                    manifest with
                    {
                        Source = StrategySource.ThirdParty,
                        Entrypoint = "missing-strategy.exe"
                    },
                    parameters,
                    Array.Empty<string>(),
                    rootDirectory).IsValid ||
                registry.Validate(
                    manifest with
                    {
                        RequestedCapabilities = new[]
                        {
                            "market_data",
                            "longbridge_cli"
                        }
                    },
                    parameters,
                    Array.Empty<string>(),
                    null).IsValid)
            {
                return 3;
            }

            var invalidParameters = parameters with
            {
                Parameters = new[]
                {
                    parameters.Parameters[0],
                    parameters.Parameters[0]
                }
            };
            if (registry.Validate(
                    manifest,
                    invalidParameters,
                    Array.Empty<string>(),
                    null).IsValid)
            {
                return 4;
            }

            var codec = new StrategyMessageCodec();
            var coreMessage = new StrategyMessageEnvelope(
                1,
                "event-smoke-1",
                "correlation-smoke-1",
                manifest.StrategyId,
                manifest.Version,
                "cycle-smoke-1",
                DateTimeOffset.Parse("2026-07-24T21:09:59Z"),
                "initialize",
                new Dictionary<string, string>
                {
                    ["mode"] = StrategyMode.PaperOnly.ToString()
                });
            var encoded = codec.Encode(
                coreMessage,
                StrategyMessageDirection.CoreToStrategy);
            var roundTrip = codec.Decode(
                encoded.TrimEnd('\n'),
                StrategyMessageDirection.CoreToStrategy,
                manifest.StrategyId,
                manifest.Version);
            if (roundTrip.EventId != coreMessage.EventId)
            {
                return 5;
            }
            try
            {
                _ = codec.Decode(
                    "{\"schema_version\":1}",
                    StrategyMessageDirection.StrategyToCore);
                return 6;
            }
            catch (StrategyProtocolException)
            {
            }

            var heartbeat = new StrategyHeartbeatMonitor(
                TimeSpan.FromSeconds(10));
            var now = DateTimeOffset.Parse("2026-07-24T21:10:30Z");
            if (!heartbeat.IsTimedOut(now.AddSeconds(-11), now) ||
                heartbeat.IsTimedOut(now.AddSeconds(-9), now))
            {
                return 7;
            }

            var governance = new ParameterGovernanceService();
            var low = parameters.Parameters.Single(parameter =>
                parameter.SafetyOverride.RiskTier == RiskTier.Low);
            var medium = parameters.Parameters.Single(parameter =>
                parameter.SafetyOverride.RiskTier == RiskTier.Medium);
            var high = parameters.Parameters.Single(parameter =>
                parameter.SafetyOverride.RiskTier == RiskTier.High);
            var lowDecision = governance.RequestChange(
                manifest.StrategyId,
                low,
                low.DefaultValue,
                "0.16",
                1,
                "smoke",
                false,
                now);
            var mediumDecision = governance.RequestChange(
                manifest.StrategyId,
                medium,
                medium.DefaultValue,
                "7",
                lowDecision.Change.ParameterVersion,
                "smoke",
                false,
                now);
            var highPreview = governance.RequestChange(
                manifest.StrategyId,
                high,
                high.DefaultValue,
                "0.55",
                mediumDecision.Change.ParameterVersion,
                "smoke",
                false,
                now);
            var highConfirmed = governance.RequestChange(
                manifest.StrategyId,
                high,
                high.DefaultValue,
                "0.55",
                mediumDecision.Change.ParameterVersion,
                "smoke",
                true,
                now);
            if (lowDecision.Change.Result != ParameterChangeResult.Applied ||
                mediumDecision.Change.Result !=
                    ParameterChangeResult.PendingCycle ||
                governance.ApplyBoundary(
                    mediumDecision.Change,
                    now).Result != ParameterChangeResult.Applied ||
                highPreview.Change.Result !=
                    ParameterChangeResult.PendingConfirmation ||
                !highPreview.BlocksNewRisk ||
                highConfirmed.Change.Result !=
                    ParameterChangeResult.PendingSafeBoundary ||
                !highConfirmed.BlocksNewRisk ||
                governance.ApplyBoundary(
                    highConfirmed.Change,
                    now).Result != ParameterChangeResult.Applied)
            {
                return 8;
            }

            var modeService = new StrategyModeService();
            var validAuthorization = registry.LoadAuthorizationFixture(
                "valid-live-authorization.json");
            var expiredAuthorization = registry.LoadAuthorizationFixture(
                "sample-live-authorization.json");
            if (modeService.SelectMode(
                    StrategyMode.Live,
                    false,
                    manifest,
                    1,
                    validAuthorization,
                    "US",
                    now).Accepted ||
                modeService.SelectMode(
                    StrategyMode.Live,
                    true,
                    manifest,
                    1,
                    expiredAuthorization,
                    "US",
                    now).Accepted ||
                modeService.SelectMode(
                    StrategyMode.Live,
                    true,
                    manifest,
                    2,
                    validAuthorization,
                    "US",
                    now).Accepted ||
                !modeService.SelectMode(
                    StrategyMode.Live,
                    true,
                    manifest,
                    1,
                    validAuthorization,
                    "US",
                    now).Accepted)
            {
                return 9;
            }

            var liveAdapter = new RejectingLiveBrokerAdapter();
            var router = new StrategyIntentRouter();
            var paperIntent = new StrategyIntentRecord(
                "intent-smoke",
                "AAPL.US",
                0.05,
                1,
                false,
                "fixture_signal",
                "cycle-smoke",
                now,
                StrategyMode.PaperOnly);
            if (router.Route(
                    StrategyMode.PaperOnly,
                    paperIntent,
                    liveAdapter) != "PaperLifecycleRecorded" ||
                liveAdapter.SubmissionAttempts != 0)
            {
                return 10;
            }

            var runtime = new OfficialFixtureStrategyRuntime(
                codec,
                router,
                liveAdapter);
            var paperResult = runtime.RunPaperCycle(
                manifest,
                parameters.Parameters.ToDictionary(
                    parameter => parameter.Key,
                    parameter => parameter.DefaultValue,
                    StringComparer.Ordinal));
            if (paperResult.Health != HealthState.Healthy ||
                paperResult.Signals.Count == 0 ||
                paperResult.Targets.Count == 0 ||
                paperResult.Intents.Count != 1 ||
                liveAdapter.SubmissionAttempts != 0)
            {
                return 11;
            }

            return 0;
        }
        catch
        {
            return 1;
        }
    }
}
