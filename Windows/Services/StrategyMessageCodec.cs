using System.Text;
using System.Text.Json;

namespace CytisusTrading.Windows;

public enum StrategyMessageDirection
{
    CoreToStrategy,
    StrategyToCore
}

public sealed class StrategyProtocolException : Exception
{
    public StrategyProtocolException(string message)
        : base(message)
    {
    }
}

public sealed class StrategyMessageCodec
{
    public const int DefaultMaximumMessageBytes = 64 * 1024;
    private readonly int _maximumMessageBytes;
    private readonly JsonSerializerOptions _options;

    public StrategyMessageCodec(
        int maximumMessageBytes = DefaultMaximumMessageBytes)
    {
        _maximumMessageBytes = maximumMessageBytes;
        _options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
    }

    public string Encode(
        StrategyMessageEnvelope message,
        StrategyMessageDirection direction)
    {
        Validate(message, direction);
        var line = JsonSerializer.Serialize(message, _options);
        if (Encoding.UTF8.GetByteCount(line) > _maximumMessageBytes)
        {
            throw new StrategyProtocolException(
                "Strategy message exceeds the configured size limit.");
        }
        return line + "\n";
    }

    public StrategyMessageEnvelope Decode(
        string line,
        StrategyMessageDirection direction,
        string? expectedStrategyId = null,
        string? expectedStrategyVersion = null)
    {
        if (string.IsNullOrWhiteSpace(line) ||
            line.Contains('\n', StringComparison.Ordinal) ||
            line.Contains('\r', StringComparison.Ordinal) ||
            Encoding.UTF8.GetByteCount(line) > _maximumMessageBytes)
        {
            throw new StrategyProtocolException(
                "Malformed or oversized NDJSON strategy message.");
        }

        StrategyMessageEnvelope message;
        try
        {
            message = JsonSerializer.Deserialize<StrategyMessageEnvelope>(
                    line,
                    _options)
                ?? throw new StrategyProtocolException(
                    "Strategy message is empty.");
        }
        catch (JsonException exception)
        {
            throw new StrategyProtocolException(
                $"Malformed strategy JSON: {exception.Message}");
        }
        Validate(message, direction);
        if (expectedStrategyId is not null &&
            !string.Equals(
                message.StrategyId,
                expectedStrategyId,
                StringComparison.Ordinal))
        {
            throw new StrategyProtocolException(
                "Strategy message identity mismatch.");
        }
        if (expectedStrategyVersion is not null &&
            !string.Equals(
                message.StrategyVersion,
                expectedStrategyVersion,
                StringComparison.Ordinal))
        {
            throw new StrategyProtocolException(
                "Strategy message version mismatch.");
        }
        return message;
    }

    private static void Validate(
        StrategyMessageEnvelope message,
        StrategyMessageDirection direction)
    {
        if (message.SchemaVersion != 1 ||
            string.IsNullOrWhiteSpace(message.EventId) ||
            message.EventId.Length > 128 ||
            string.IsNullOrWhiteSpace(message.CorrelationId) ||
            message.CorrelationId.Length > 128 ||
            string.IsNullOrWhiteSpace(message.StrategyId) ||
            string.IsNullOrWhiteSpace(message.StrategyVersion) ||
            string.IsNullOrWhiteSpace(message.CycleId) ||
            message.Timestamp == default ||
            message.Payload is null)
        {
            throw new StrategyProtocolException(
                "Strategy message is missing a required envelope field.");
        }

        var allowed = direction == StrategyMessageDirection.CoreToStrategy
            ? StrategyProtocolMessageTypes.CoreToStrategy
            : StrategyProtocolMessageTypes.StrategyToCore;
        if (!allowed.Contains(message.MessageType))
        {
            throw new StrategyProtocolException(
                "Unknown or directionally invalid strategy message type.");
        }
        if (message.Payload.Keys.Any(SensitivePayloadKey))
        {
            throw new StrategyProtocolException(
                "Strategy payload contains a prohibited sensitive field.");
        }
    }

    private static bool SensitivePayloadKey(string key)
    {
        var normalized = key
            .Replace("-", "_", StringComparison.Ordinal)
            .ToLowerInvariant();
        return normalized.Contains("token", StringComparison.Ordinal) ||
            normalized.Contains("secret", StringComparison.Ordinal) ||
            normalized.Contains("credential", StringComparison.Ordinal) ||
            normalized.Contains("authorization_code", StringComparison.Ordinal) ||
            normalized.Contains("account_number", StringComparison.Ordinal);
    }
}

public sealed class StrategyHeartbeatMonitor
{
    private readonly TimeSpan _timeout;

    public StrategyHeartbeatMonitor(TimeSpan timeout)
    {
        _timeout = timeout > TimeSpan.Zero
            ? timeout
            : throw new ArgumentOutOfRangeException(nameof(timeout));
    }

    public bool IsTimedOut(DateTimeOffset? lastHeartbeat, DateTimeOffset now)
    {
        return !lastHeartbeat.HasValue ||
            now - lastHeartbeat.Value > _timeout;
    }
}
