using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum LongbridgeStatusState
{
    Missing,
    Unauthenticated,
    Degraded,
    Ready
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum LongbridgeOperation
{
    Status,
    Connectivity,
    HistoricalBars,
    CurrentSnapshot,
    MarketStatus,
    SecurityList,
    BrokerPositions
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CliCallCategory
{
    ReadOnlyData
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum UniverseDisposition
{
    Included,
    Excluded,
    ReduceOnly
}

public sealed record CliCommandTemplate(
    LongbridgeOperation Operation,
    IReadOnlyList<string> Arguments);

public sealed record LongbridgeCapabilities(
    int SchemaVersion,
    bool FixtureMode,
    string CliVersion,
    string SourceVersion,
    LongbridgeStatusState StatusState,
    bool SupportsJson,
    IReadOnlyList<CliCommandTemplate> Commands,
    IReadOnlyList<string> DataPermissions,
    DateTimeOffset DiscoveredAt,
    bool LiveExecutionAvailable,
    string Message);

public sealed record AuthorizationStatusSummary(
    int SchemaVersion,
    LongbridgeStatusState State,
    bool Authenticated,
    IReadOnlyList<string> Permissions,
    DateTimeOffset CheckedAt,
    string Message);

public sealed record ConnectivitySummary(
    int SchemaVersion,
    LongbridgeStatusState State,
    bool Reachable,
    DateTimeOffset CheckedAt,
    int LatencyMs,
    string Message);

public sealed record MarketBar(
    DateTimeOffset EventTime,
    DateTimeOffset AvailableTime,
    DateTimeOffset CollectedAt,
    string SourceVersion,
    string AdjustmentMode,
    string DataHash,
    decimal Open,
    decimal High,
    decimal Low,
    decimal Close,
    decimal Volume);

public sealed record HistoricalBarSeries(
    int SchemaVersion,
    string Symbol,
    string Interval,
    DateTimeOffset Start,
    DateTimeOffset End,
    IReadOnlyList<MarketBar> Bars,
    string DataHash);

public sealed record CurrentMarketSnapshot(
    int SchemaVersion,
    string Symbol,
    DateTimeOffset EventTime,
    DateTimeOffset AvailableTime,
    DateTimeOffset CollectedAt,
    string SourceVersion,
    string AdjustmentMode,
    string DataHash,
    decimal Last,
    decimal Open,
    decimal High,
    decimal Low,
    decimal PreviousClose,
    decimal Volume,
    string Currency);

public sealed record MarketStatusSnapshot(
    int SchemaVersion,
    string Market,
    string Session,
    DateTimeOffset EventTime,
    DateTimeOffset AvailableTime,
    DateTimeOffset CollectedAt,
    string SourceVersion,
    string AdjustmentMode,
    string DataHash,
    DateTimeOffset NextOpen);

public sealed record SecurityReference(
    string Symbol,
    string Name,
    string Industry,
    bool Tradable,
    decimal LastPrice,
    decimal AverageDailyVolume,
    decimal AverageDailyValue,
    int ListingAgeDays,
    int HistoryCoverageDays,
    bool Suspended,
    bool Delisted,
    bool Abnormal,
    bool StrategyEligible);

public sealed record SecurityListSnapshot(
    int SchemaVersion,
    string Market,
    DateTimeOffset CollectedAt,
    string SourceVersion,
    string DataHash,
    IReadOnlyList<SecurityReference> Securities);

public sealed record BrokerPosition(
    string Symbol,
    decimal Quantity);

public sealed record BrokerPositionSnapshot(
    int SchemaVersion,
    DateTimeOffset CollectedAt,
    string SourceVersion,
    string DataHash,
    IReadOnlyList<BrokerPosition> Positions);

public sealed record UniverseConfiguration(
    int SchemaVersion,
    string Market,
    decimal MinimumPrice,
    decimal MinimumAverageDailyVolume,
    int MinimumListingAgeDays,
    int MinimumHistoryCoverageDays,
    string RuleVersion);

public sealed record UniverseLiquidityMetrics(
    decimal LastPrice,
    decimal AverageDailyVolume,
    decimal AverageDailyValue);

public sealed record UniverseDataCoverage(
    int ListingAgeDays,
    int HistoryCoverageDays);

public sealed record UniverseEntry(
    string Date,
    string Symbol,
    bool Included,
    UniverseDisposition Disposition,
    string Reason,
    UniverseLiquidityMetrics LiquidityMetrics,
    UniverseDataCoverage DataCoverage,
    string Industry,
    string RuleVersion,
    string SourceVersion)
{
    public string DispositionLabel => Disposition == UniverseDisposition.ReduceOnly
        ? "Reduce Only"
        : Disposition.ToString();
}

public sealed record UniverseSnapshot(
    int SchemaVersion,
    string Date,
    string Market,
    string RuleVersion,
    string SourceVersion,
    DateTimeOffset CreatedAt,
    IReadOnlyList<UniverseEntry> Entries);

public sealed record LongbridgeDataSnapshot(
    LongbridgeCapabilities Capabilities,
    AuthorizationStatusSummary Authorization,
    ConnectivitySummary Connectivity,
    HistoricalBarSeries HistoricalBars,
    CurrentMarketSnapshot CurrentSnapshot,
    MarketStatusSnapshot MarketStatus,
    SecurityListSnapshot SecurityList,
    BrokerPositionSnapshot BrokerPositions,
    UniverseSnapshot Universe);

public sealed record CliCommand(
    string ExecutablePath,
    IReadOnlyList<string> Arguments,
    CliCallCategory Category,
    LongbridgeOperation Operation);

public sealed record CliProcessResult(
    int ExitCode,
    string StandardOutput,
    string StandardError,
    bool TimedOut,
    bool Cancelled,
    bool OutputTruncated,
    TimeSpan Duration)
{
    public bool Succeeded => ExitCode == 0 && !TimedOut && !Cancelled;
}

public sealed record LongbridgeInspection(
    LongbridgeStatusState State,
    string ExecutablePath,
    string CliVersion,
    DateTimeOffset CheckedAt,
    IReadOnlyList<string> DataPermissions,
    string Message,
    LongbridgeCapabilities? Capabilities);

public enum CacheWriteResult
{
    Created,
    Updated,
    Unchanged
}
