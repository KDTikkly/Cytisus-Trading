using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;

namespace CytisusTrading.Windows;

public interface IOfficialStrategyRuntime
{
    PaperCycleResult RunPaperCycle(
        StrategyManifest manifest,
        IReadOnlyDictionary<string, string> parameterValues);
}

public sealed class OfficialFixtureStrategyRuntime :
    IOfficialStrategyRuntime
{
    private readonly Assembly _assembly;
    private readonly StrategyMessageCodec _codec;
    private readonly StrategyIntentRouter _intentRouter;
    private readonly ILiveBrokerAdapter _liveAdapter;

    public OfficialFixtureStrategyRuntime(
        StrategyMessageCodec codec,
        StrategyIntentRouter intentRouter,
        ILiveBrokerAdapter liveAdapter,
        Assembly? assembly = null)
    {
        _codec = codec;
        _intentRouter = intentRouter;
        _liveAdapter = liveAdapter;
        _assembly = assembly ?? typeof(OfficialFixtureStrategyRuntime).Assembly;
    }

    public PaperCycleResult RunPaperCycle(
        StrategyManifest manifest,
        IReadOnlyDictionary<string, string> parameterValues)
    {
        var correlationId = "corr-paper-0001";
        var cycleId = "cycle-paper-0001";
        var initialize = CoreMessage(
            manifest,
            cycleId,
            correlationId,
            "initialize",
            new Dictionary<string, string>
            {
                ["mode"] = StrategyMode.PaperOnly.ToString(),
                ["fixture_mode"] = "true"
            });
        var loadParameters = CoreMessage(
            manifest,
            cycleId,
            correlationId,
            "load_parameters",
            parameterValues);
        var startCycle = CoreMessage(
            manifest,
            cycleId,
            correlationId,
            "start_cycle",
            new Dictionary<string, string>
            {
                ["source"] = "deterministic_fixture"
            });
        _ = _codec.Encode(
            initialize,
            StrategyMessageDirection.CoreToStrategy);
        _ = _codec.Encode(
            loadParameters,
            StrategyMessageDirection.CoreToStrategy);
        _ = _codec.Encode(
            startCycle,
            StrategyMessageDirection.CoreToStrategy);

        var messages = LoadOutputMessages(manifest);
        var duplicateEvents = messages
            .GroupBy(message => message.EventId, StringComparer.Ordinal)
            .Any(group => group.Count() > 1);
        if (duplicateEvents)
        {
            throw new StrategyProtocolException(
                "The official fixture emitted a duplicate event ID.");
        }

        var lastHeartbeat = messages
            .Where(message => message.MessageType == "heartbeat")
            .Select(message => message.Timestamp)
            .DefaultIfEmpty()
            .Max();
        var completed = messages.SingleOrDefault(message =>
            message.MessageType == "cycle_complete")
            ?? throw new StrategyProtocolException(
                "The official fixture did not complete its cycle.");
        var heartbeatMonitor = new StrategyHeartbeatMonitor(
            TimeSpan.FromSeconds(10));
        var health = heartbeatMonitor.IsTimedOut(
                lastHeartbeat == default ? null : lastHeartbeat,
                completed.Timestamp)
            ? HealthState.Unhealthy
            : HealthState.Healthy;

        var signals = messages
            .Where(message => message.MessageType == "signal")
            .Select(message => new StrategySignal(
                Required(message, "symbol"),
                ParseDouble(message, "score"),
                Required(message, "reason"),
                message.Timestamp))
            .ToArray();
        var targets = messages
            .Where(message => message.MessageType == "target_position")
            .Select(message => new StrategyTarget(
                Required(message, "symbol"),
                ParseDouble(message, "target_weight"),
                Required(message, "reason"),
                message.Timestamp))
            .ToArray();
        var intents = messages
            .Where(message => message.MessageType == "trade_intent")
            .Select(message => new StrategyIntentRecord(
                Required(message, "intent_id"),
                Required(message, "symbol"),
                ParseDouble(message, "target_weight"),
                ParseInt(message, "priority"),
                ParseBool(message, "allow_partial"),
                Required(message, "reason_code"),
                message.CycleId,
                message.Timestamp,
                StrategyMode.PaperOnly))
            .ToArray();
        foreach (var intent in intents)
        {
            var routed = _intentRouter.Route(
                StrategyMode.PaperOnly,
                intent,
                _liveAdapter);
            if (!string.Equals(
                    routed,
                    "PaperLifecycleRecorded",
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Local Paper reached a Live adapter.");
            }
        }

        var cycle = new StrategyCycleSummary(
            completed.CycleId,
            completed.Timestamp,
            signals.Length,
            targets.Length,
            intents.Length,
            Required(completed, "result"));
        return new PaperCycleResult(
            cycle,
            lastHeartbeat,
            health,
            signals,
            targets,
            intents,
            messages);
    }

    private IReadOnlyList<StrategyMessageEnvelope> LoadOutputMessages(
        StrategyManifest manifest)
    {
        var resourceName = _assembly.GetManifestResourceNames()
            .SingleOrDefault(name => name.EndsWith(
                "official-paper-cycle.ndjson",
                StringComparison.OrdinalIgnoreCase))
            ?? throw new FileNotFoundException(
                "Official Local Paper cycle fixture is unavailable.");
        using var stream = _assembly.GetManifestResourceStream(resourceName)
            ?? throw new FileNotFoundException(
                "Official Local Paper cycle fixture stream is unavailable.");
        using var reader = new StreamReader(
            stream,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: true);
        var messages = new List<StrategyMessageEnvelope>();
        while (reader.ReadLine() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }
            messages.Add(_codec.Decode(
                line,
                StrategyMessageDirection.StrategyToCore,
                manifest.StrategyId,
                manifest.Version));
        }
        return messages;
    }

    private static StrategyMessageEnvelope CoreMessage(
        StrategyManifest manifest,
        string cycleId,
        string correlationId,
        string messageType,
        IReadOnlyDictionary<string, string> payload)
    {
        return new StrategyMessageEnvelope(
            1,
            Guid.NewGuid().ToString("D"),
            correlationId,
            manifest.StrategyId,
            manifest.Version,
            cycleId,
            DateTimeOffset.Parse("2026-07-24T21:09:59Z"),
            messageType,
            payload);
    }

    private static string Required(
        StrategyMessageEnvelope message,
        string key)
    {
        return message.Payload.TryGetValue(key, out var value) &&
            !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new StrategyProtocolException(
                $"Strategy message is missing payload field {key}.");
    }

    private static double ParseDouble(
        StrategyMessageEnvelope message,
        string key)
    {
        return double.TryParse(
            Required(message, key),
            NumberStyles.Float,
            CultureInfo.InvariantCulture,
            out var value)
            ? value
            : throw new StrategyProtocolException(
                $"Strategy payload field {key} is not numeric.");
    }

    private static int ParseInt(
        StrategyMessageEnvelope message,
        string key)
    {
        return int.TryParse(
            Required(message, key),
            NumberStyles.Integer,
            CultureInfo.InvariantCulture,
            out var value)
            ? value
            : throw new StrategyProtocolException(
                $"Strategy payload field {key} is not an integer.");
    }

    private static bool ParseBool(
        StrategyMessageEnvelope message,
        string key)
    {
        return bool.TryParse(Required(message, key), out var value)
            ? value
            : throw new StrategyProtocolException(
                $"Strategy payload field {key} is not a Boolean.");
    }
}
