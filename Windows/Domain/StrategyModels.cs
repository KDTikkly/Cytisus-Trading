using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum StrategySource
{
    Official,
    ThirdParty
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum StrategyRuntimeState
{
    Stopped,
    Starting,
    Ready,
    Running,
    Paused,
    Unhealthy,
    Exited,
    Rejected
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ParameterType
{
    Number,
    Integer,
    Boolean,
    String
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum RiskTier
{
    Low,
    Medium,
    High
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ParameterActivationMode
{
    Immediate,
    NextCycle,
    SafeBoundary
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ParameterChangeResult
{
    Applied,
    PendingCycle,
    PendingConfirmation,
    PendingSafeBoundary,
    Rejected
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum LiveToPaperTransition
{
    StopOpeningRisk,
    Freeze,
    ControlledExit
}

public sealed record StrategyManifest(
    int SchemaVersion,
    int ProtocolVersion,
    string StrategyId,
    string Name,
    string Version,
    StrategySource Source,
    string Entrypoint,
    IReadOnlyList<StrategyMode> SupportedModes,
    IReadOnlyList<string> RequiredData,
    int ParameterSchemaVersion,
    string ParameterSchema,
    IReadOnlyList<string> RequestedCapabilities);

public sealed record ParameterSafetyOverride(
    string? HardMin,
    string? HardMax,
    RiskTier RiskTier,
    bool LiveMutable,
    bool RequiresPreview,
    bool RequiresPause,
    bool RequiresConfirmation,
    ParameterActivationMode ActivationMode,
    bool RollbackRequired);

public sealed record StrategyParameterDefinition(
    string Key,
    string Label,
    string Description,
    ParameterType Type,
    string DefaultValue,
    string? RecommendedMin,
    string? RecommendedMax,
    ParameterActivationMode RecommendedActivationMode,
    ParameterSafetyOverride SafetyOverride);

public sealed record StrategyParameterSchema(
    int SchemaVersion,
    string StrategyId,
    IReadOnlyList<StrategyParameterDefinition> Parameters);

public sealed record StrategyParameterChange(
    string ChangeId,
    string StrategyId,
    string ParameterKey,
    string OldValue,
    string NewValue,
    DateTimeOffset RequestedAt,
    DateTimeOffset? EffectiveAt,
    string RequestedBy,
    RiskTier RiskTier,
    int ParameterVersion,
    ParameterActivationMode ActivationMode,
    ParameterChangeResult Result,
    int RollbackVersion);

public sealed record StrategyMessageEnvelope(
    int SchemaVersion,
    string EventId,
    string CorrelationId,
    string StrategyId,
    string StrategyVersion,
    string CycleId,
    DateTimeOffset Timestamp,
    string MessageType,
    IReadOnlyDictionary<string, string> Payload);

public sealed record StrategySignal(
    string Symbol,
    double Score,
    string Reason,
    DateTimeOffset Timestamp);

public sealed record StrategyTarget(
    string Symbol,
    double TargetWeight,
    string Reason,
    DateTimeOffset Timestamp);

public sealed record StrategyIntentRecord(
    string IntentId,
    string Symbol,
    double TargetWeight,
    int Priority,
    bool AllowPartial,
    string ReasonCode,
    string CycleId,
    DateTimeOffset Timestamp,
    StrategyMode Mode);

public sealed record StrategyCycleSummary(
    string CycleId,
    DateTimeOffset CompletedAt,
    int SignalCount,
    int TargetCount,
    int IntentCount,
    string Result);

public sealed record StrategyPersistentState(
    string StrategyId,
    StrategyMode Mode,
    StrategyRuntimeState RuntimeState,
    HealthState Health,
    DateTimeOffset? LastHeartbeat,
    int ParameterVersion,
    IReadOnlyDictionary<string, string> ParameterValues,
    bool BlocksNewRisk,
    LiveToPaperTransition LiveToPaperTransition);

public sealed record LiveAuthorization(
    int SchemaVersion,
    string AuthorizationId,
    string StrategyId,
    IReadOnlyList<string> AllowedMarkets,
    IReadOnlyList<string> AllowedSymbolsOrUniverse,
    decimal MaximumCapital,
    decimal MaximumStrategyAllocation,
    decimal MaximumSinglePositionExposure,
    decimal MaximumDailyLoss,
    decimal MaximumDrawdown,
    int MaximumOrderFrequency,
    bool OutsideRegularHoursPermission,
    int ParameterVersion,
    DateTimeOffset ValidFrom,
    DateTimeOffset ExpiresAt,
    bool Enabled);

public sealed record ManifestValidationResult(
    bool IsValid,
    string Message)
{
    public static ManifestValidationResult Valid { get; } =
        new(true, "Manifest is valid.");

    public static ManifestValidationResult Invalid(string message)
    {
        return new ManifestValidationResult(false, message);
    }
}

public sealed record ModeSelectionResult(
    bool Accepted,
    StrategyMode Mode,
    string Message);

public sealed record ParameterChangeDecision(
    StrategyParameterChange Change,
    bool BlocksNewRisk,
    string ImpactPreview);

public sealed record PaperCycleResult(
    StrategyCycleSummary Cycle,
    DateTimeOffset LastHeartbeat,
    HealthState Health,
    IReadOnlyList<StrategySignal> Signals,
    IReadOnlyList<StrategyTarget> Targets,
    IReadOnlyList<StrategyIntentRecord> Intents,
    IReadOnlyList<StrategyMessageEnvelope> Messages);

public static class StrategyProtocolMessageTypes
{
    public static IReadOnlySet<string> CoreToStrategy { get; } =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "initialize",
            "load_parameters",
            "apply_parameters",
            "market_snapshot",
            "allocation_budget",
            "start_cycle",
            "pause",
            "resume",
            "shutdown"
        };

    public static IReadOnlySet<string> StrategyToCore { get; } =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "ready",
            "heartbeat",
            "log",
            "health",
            "signal",
            "factor_observation",
            "target_position",
            "trade_intent",
            "cycle_complete",
            "error"
        };
}
