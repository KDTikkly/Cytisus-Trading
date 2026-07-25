namespace CytisusTrading.Windows;

public enum ApplicationLogLevel
{
    Debug,
    Info,
    Warning,
    Error,
    Critical
}

public sealed record ApplicationLogEntry(
    string Id,
    DateTimeOffset Timestamp,
    ApplicationLogLevel Severity,
    string Module,
    string Message,
    string? CorrelationId,
    IReadOnlyDictionary<string, string> Context)
{
    public string? StrategyId { get; init; }
    public string? CycleId { get; init; }
}

public enum AuditEventCategory
{
    Application,
    Settings,
    StrategyLifecycle,
    FactorLifecycle,
    RiskRejection,
    LiveAuthorization,
    StrategyIntent,
    RiskDecision,
    InternalTransfer,
    BrokerOrder,
    BrokerFill,
    VirtualAllocation,
    AllocationShortfall,
    Reconciliation
}

public enum AuditResult
{
    Accepted,
    Rejected,
    Completed,
    Failed
}

public sealed record AuditEvent(
    string EventId,
    DateTimeOffset OccurredAt,
    AuditEventCategory Category,
    string Action,
    AuditResult Result,
    string Actor,
    string CorrelationId,
    IReadOnlyDictionary<string, string> Context)
{
    public int SchemaVersion { get; init; } = 1;
}
