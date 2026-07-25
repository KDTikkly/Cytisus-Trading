using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum OrderSide
{
    Buy,
    Sell
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum RiskDecisionOutcome
{
    Accepted,
    Rejected
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum BrokerOrderState
{
    Accepted,
    Rejected,
    FullyFilled,
    PartiallyFilled,
    Expired,
    Ambiguous
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ReconciliationStatus
{
    Reconciled,
    Mismatch
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum LiveSubmissionState
{
    Disabled,
    CommandConstructed,
    Rejected,
    Submitted,
    Ambiguous
}

public sealed record TradeIntent(
    int SchemaVersion,
    string IntentId,
    string StrategyId,
    string StrategyVersion,
    string CycleId,
    string SettlementCycle,
    string Symbol,
    decimal RequestedQuantity,
    int Priority,
    bool AllowPartial,
    decimal MinimumEffectiveFill,
    int TimeToLiveSeconds,
    string ReasonCode,
    int ParameterVersion,
    DateTimeOffset CreatedAt)
{
    public OrderSide Side =>
        RequestedQuantity >= 0 ? OrderSide.Buy : OrderSide.Sell;
    public decimal AbsoluteQuantity => Math.Abs(RequestedQuantity);
}

public sealed record RiskDecision(
    int SchemaVersion,
    string DecisionId,
    string IntentId,
    string StrategyId,
    string Symbol,
    RiskDecisionOutcome Outcome,
    string Reason,
    string CorrelationId,
    DateTimeOffset CreatedAt);

public sealed record InternalTransfer(
    int SchemaVersion,
    string TransferId,
    string Symbol,
    string SettlementCycle,
    string BuyerStrategyId,
    string SellerStrategyId,
    decimal Quantity,
    decimal ReferencePrice,
    string ReferencePriceSource,
    string BuyerIntentId,
    string SellerIntentId,
    string CorrelationId,
    DateTimeOffset CreatedAt)
{
    public string Display =>
        $"{Symbol} | {SellerStrategyId} -> {BuyerStrategyId} | {Quantity:0.####} @ {ReferencePrice:0.00}";
}

public sealed record BrokerOrder(
    int SchemaVersion,
    string OrderId,
    string CorrelationId,
    string Symbol,
    OrderSide Side,
    decimal Quantity,
    decimal ReferencePrice,
    StrategyMode Mode,
    BrokerOrderState State,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt,
    int SubmissionAttempts,
    string StatusMessage)
{
    public string ModeLabel =>
        Mode == StrategyMode.PaperOnly ? "Local Paper" : "Live";
}

public sealed record BrokerFill(
    int SchemaVersion,
    string FillId,
    string OrderId,
    string CorrelationId,
    string Symbol,
    OrderSide Side,
    decimal Quantity,
    decimal Price,
    decimal SlippageEstimate,
    decimal FeeEstimate,
    DateTimeOffset FilledAt);

public sealed record VirtualAllocation(
    int SchemaVersion,
    string AllocationId,
    string FillId,
    string IntentId,
    string StrategyId,
    string Symbol,
    OrderSide Side,
    decimal Quantity,
    decimal Price,
    decimal Fee,
    string CorrelationId,
    DateTimeOffset CreatedAt);

public sealed record AllocationShortfall(
    int SchemaVersion,
    string ShortfallId,
    string IntentId,
    string StrategyId,
    string Symbol,
    decimal RequestedQuantity,
    decimal AllocatedQuantity,
    decimal UnfilledQuantity,
    string Reason,
    string CorrelationId,
    DateTimeOffset CreatedAt);

public sealed record VirtualLedgerPosition(
    int SchemaVersion,
    string StrategyId,
    string Symbol,
    decimal TargetPosition,
    decimal VirtualQuantity,
    decimal CostBasis,
    decimal RealizedPnl,
    decimal UnrealizedPnl,
    decimal CapitalUsage,
    decimal RiskContribution,
    IReadOnlyList<string> IntentIds,
    IReadOnlyList<string> AllocationIds,
    IReadOnlyList<string> InternalTransferIds,
    DateTimeOffset UpdatedAt)
{
    public string PositionKey => $"{StrategyId}|{Symbol}";
}

public sealed record ReconciliationEvent(
    int SchemaVersion,
    string ReconciliationId,
    string Symbol,
    decimal VirtualQuantity,
    decimal BrokerQuantity,
    decimal Difference,
    ReconciliationStatus Status,
    bool BlocksNewRisk,
    string Diagnostic,
    string CorrelationId,
    DateTimeOffset CreatedAt);

public sealed record CriticalRiskEvent(
    int SchemaVersion,
    string RiskEventId,
    string Symbol,
    string Severity,
    string Message,
    bool Persistent,
    string CorrelationId,
    DateTimeOffset CreatedAt);

public sealed record ExecutionStateSnapshot(
    int SchemaVersion,
    IReadOnlyList<TradeIntent> Intents,
    IReadOnlyList<RiskDecision> RiskDecisions,
    IReadOnlyList<InternalTransfer> InternalTransfers,
    IReadOnlyList<BrokerOrder> BrokerOrders,
    IReadOnlyList<BrokerFill> BrokerFills,
    IReadOnlyList<VirtualAllocation> VirtualAllocations,
    IReadOnlyList<AllocationShortfall> AllocationShortfalls,
    IReadOnlyList<VirtualLedgerPosition> LedgerPositions,
    IReadOnlyList<ReconciliationEvent> Reconciliations,
    IReadOnlyList<CriticalRiskEvent> RiskEvents,
    IReadOnlyList<string> BlockedSymbols)
{
    public static ExecutionStateSnapshot Empty { get; } = new(
        1,
        Array.Empty<TradeIntent>(),
        Array.Empty<RiskDecision>(),
        Array.Empty<InternalTransfer>(),
        Array.Empty<BrokerOrder>(),
        Array.Empty<BrokerFill>(),
        Array.Empty<VirtualAllocation>(),
        Array.Empty<AllocationShortfall>(),
        Array.Empty<VirtualLedgerPosition>(),
        Array.Empty<ReconciliationEvent>(),
        Array.Empty<CriticalRiskEvent>(),
        Array.Empty<string>());
}

public sealed record ExecutionGatewayContext(
    StrategyMode Mode,
    bool GlobalLiveLock,
    LiveAuthorization? Authorization,
    bool DataFresh,
    bool MarketAllowed,
    HealthState StrategyHealth,
    decimal CapitalBudget,
    decimal MaximumPositionExposure,
    bool CliReady,
    bool LiveAdapterEnabled,
    bool FixtureMode,
    int ParameterVersion,
    string Market,
    DateTimeOffset Now,
    decimal DailyLoss = 0,
    decimal Drawdown = 0,
    bool OutsideRegularHours = false,
    bool TransitionActive = false,
    LiveToPaperTransition TransitionPolicy =
        LiveToPaperTransition.StopOpeningRisk);

public sealed record GatewayBatchResult(
    ExecutionStateSnapshot State,
    IReadOnlyList<RiskDecision> Decisions,
    IReadOnlyList<InternalTransfer> Transfers,
    IReadOnlyList<BrokerOrder> Orders,
    IReadOnlyList<BrokerFill> Fills,
    IReadOnlyList<VirtualAllocation> Allocations,
    IReadOnlyList<AllocationShortfall> Shortfalls,
    IReadOnlyList<ReconciliationEvent> Reconciliations);

public sealed record PaperBrokerConfiguration(
    decimal FillRatio,
    decimal SlippageBasisPoints,
    decimal FeePerUnit,
    decimal MinimumFee,
    bool RejectOrders,
    bool ExpireOrders);

public sealed record BrokerSubmissionResult(
    BrokerOrder Order,
    BrokerFill? Fill);

public sealed record LongbridgeExecutionCapability(
    int SchemaVersion,
    string SourceVersion,
    bool SyntheticFixture,
    bool SupportsMachineReadableOutput,
    bool SupportsOrderSubmission,
    IReadOnlyList<string> ArgumentTemplate,
    string Message);

public sealed record LiveAdapterConfiguration(
    bool Enabled,
    bool FixtureMode,
    string ExecutablePath,
    TimeSpan Timeout,
    LongbridgeExecutionCapability Capability);

public sealed record LiveSubmissionResult(
    LiveSubmissionState State,
    BrokerOrder Order,
    IReadOnlyList<string> Arguments,
    bool RetryPermitted,
    string Message);

public sealed record FixtureLedgerSeed(
    string StrategyId,
    decimal VirtualQuantity,
    decimal CostBasis);

public sealed record PaperGatewayFixture(
    int SchemaVersion,
    DateTimeOffset AsOf,
    string Market,
    string Symbol,
    decimal ReferencePrice,
    string ReferencePriceSource,
    decimal StartingBrokerQuantity,
    decimal PaperFillRatio,
    IReadOnlyList<FixtureLedgerSeed> StartingLedger,
    IReadOnlyList<TradeIntent> Intents);

public sealed record ReconciliationFailureFixture(
    int SchemaVersion,
    DateTimeOffset AsOf,
    string Symbol,
    decimal VirtualQuantity,
    decimal BrokerQuantity,
    ReconciliationStatus ExpectedStatus,
    bool ExpectedBlocksNewRisk);
