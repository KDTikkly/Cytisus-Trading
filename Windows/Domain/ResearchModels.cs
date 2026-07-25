using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FactorTaskType
{
    Alpha,
    Risk,
    Regime,
    Liquidity,
    Execution
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FactorTrialResult
{
    Candidate,
    Rejected,
    Quarantined
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FactorMissingValuePolicy
{
    Propagate,
    IgnoreWindowMissing,
    CrossSectionMedian
}

public static class FactorHorizons
{
    public static IReadOnlyList<string> Daily { get; } =
        new[] { "1d", "3d", "5d", "10d", "20d", "60d", "120d", "252d" };

    public static IReadOnlySet<string> ReservedIntraday { get; } =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "1m",
            "5m",
            "30m"
        };

    public static int Days(string horizon)
    {
        if (!Daily.Contains(horizon, StringComparer.Ordinal))
        {
            throw new ArgumentOutOfRangeException(
                nameof(horizon),
                "Only standard daily horizons are evaluated.");
        }
        return int.Parse(
            horizon[..^1],
            System.Globalization.CultureInfo.InvariantCulture);
    }
}

public sealed record FactorDefinition(
    int SchemaVersion,
    string FactorId,
    FactorTaskType FactorType,
    string Target,
    string Horizon,
    string Universe,
    IReadOnlyList<string> RequiredData,
    string UpdateFrequency,
    int Version,
    FactorState State,
    string Expression,
    IReadOnlyDictionary<string, FactorState> StrategyStates);

public sealed record FactorEvidence(
    double Coverage,
    double MissingRate,
    double TaskMetric,
    string TaskMetricName,
    double Stability,
    double Turnover,
    double CostProxy,
    double CapacityProxy,
    double ExistingFactorCorrelation,
    double NeighboringHorizonStability,
    double MarginalContribution,
    int OosWindows,
    double MultipleTestingPenalty,
    string RegimeEvidence);

public sealed record FactorTrial(
    int SchemaVersion,
    string TrialId,
    string FactorFamily,
    string Expression,
    IReadOnlyDictionary<string, string> Parameters,
    string DatasetVersion,
    string UniverseVersion,
    string SearchAlgorithm,
    int Generation,
    int OosWindows,
    IReadOnlyDictionary<string, double> Metrics,
    FactorTrialResult Result,
    string? RejectionReason,
    DateTimeOffset CreatedAt);

public sealed record FactorResearchSummary(
    FactorDefinition Definition,
    FactorState GlobalState,
    FactorState StrategyState,
    int TrialCount,
    FactorEvidence Evidence,
    string StateReason)
{
    public string FactorId => Definition.FactorId;
    public string Name => Definition.FactorId
        .Replace("-", " ", StringComparison.Ordinal);
    public string FactorType => Definition.FactorType.ToString();
    public string Horizon => Definition.Horizon;
    public string GlobalStateLabel => GlobalState.ToString();
    public string StrategyStateLabel => StrategyState.ToString();
    public string OosEvidence =>
        $"{Evidence.OosWindows} windows | {Evidence.TaskMetricName} {Evidence.TaskMetric:0.000}";
    public string RegimeEvidence => Evidence.RegimeEvidence;
    public string MarginalContribution =>
        Evidence.MarginalContribution.ToString(
            "0.000",
            System.Globalization.CultureInfo.InvariantCulture);
}

public sealed record ResearchObservation(
    string Symbol,
    string Industry,
    DateTimeOffset EventTime,
    DateTimeOffset AvailableTime,
    double Open,
    double High,
    double Low,
    double Close,
    double Volume,
    double Returns,
    double MarketReturn,
    double SectorReturn,
    double CapitalFlow)
{
    public double Field(string name)
    {
        return name switch
        {
            "open" => Open,
            "high" => High,
            "low" => Low,
            "close" => Close,
            "volume" => Volume,
            "returns" => Returns,
            "market_return" => MarketReturn,
            "sector_return" => SectorReturn,
            "capital_flow" => CapitalFlow,
            _ => throw new ArgumentOutOfRangeException(
                nameof(name),
                "Unknown research field.")
        };
    }
}

public sealed record NormalizedResearchDataset(
    string DatasetVersion,
    string UniverseVersion,
    DateTimeOffset CreatedAt,
    IReadOnlyList<ResearchObservation> Observations);

public sealed record FactorSearchConfiguration(
    int BeamWidth,
    int TopK,
    int MaximumGenerations,
    int MaximumCandidates,
    int MaximumDepth,
    int MaximumOperators)
{
    public static FactorSearchConfiguration Tiny { get; } =
        new(4, 3, 2, 24, 8, 16);
}

public sealed record FactorSearchResult(
    string Status,
    int EvaluatedCount,
    int CandidateCount,
    int RejectedCount,
    int QuarantinedCount,
    IReadOnlyList<FactorTrial> Trials,
    IReadOnlyList<FactorResearchSummary> Summaries);

public sealed record FactorLifecycleEvidence(
    bool DataContamination,
    bool LookAheadBias,
    bool TrainTestLeakage,
    bool UnreproducibleResult,
    bool DefinitionError,
    bool TrialRecordPresent,
    double ShortTermScore,
    double LongTermScore,
    bool RegimeSpecificFailure,
    int RepeatedOosFailures,
    double ChangePointProbability,
    double CounterfactualImprovement,
    bool RenewedEvidence);

public sealed record FactorLifecycleDecision(
    FactorState State,
    bool Global,
    bool BlocksRiskExpansion,
    double RiskMultiplier,
    string Reason);

public sealed record RegimeInput(
    double TrendStrength,
    double RangeScore,
    double RealizedVolatility,
    double CrossAssetRisk,
    IReadOnlyDictionary<string, double> StrategyReportedFit);

public sealed record RegimeSnapshot(
    int SchemaVersion,
    DateTimeOffset AsOf,
    IReadOnlyDictionary<string, double> Probabilities,
    double Uncertainty,
    double RiskMultiplier,
    IReadOnlyDictionary<string, double> Explanation)
{
    public double Trend => Probabilities.GetValueOrDefault("Trend");
    public double Range => Probabilities.GetValueOrDefault("Range");
    public double HighVolatility =>
        Probabilities.GetValueOrDefault("HighVolatility");
    public double Crisis => Probabilities.GetValueOrDefault("Crisis");
}

public sealed record StrategyAllocationInput(
    string StrategyId,
    HealthState Health,
    bool IsNew,
    double LongTermOos,
    double RecentLive,
    double RecentPaper,
    double SignalStrength,
    double RegimeFit,
    double ConfidenceCalibration,
    double DataQuality,
    double ModelUncertainty,
    double Volatility,
    double AverageCorrelation,
    double Drawdown,
    double Capacity,
    double Liquidity,
    double CurrentWeight);

public sealed record RegimeAllocationFixture(
    int SchemaVersion,
    RegimeInput RegimeInput,
    double TotalCapital,
    double BaseRiskFraction,
    IReadOnlyList<StrategyAllocationInput> Strategies);

public sealed record StrategyCapitalAllocation(
    int SchemaVersion,
    string StrategyId,
    double FinalWeight,
    double CapitalBudget,
    IReadOnlyDictionary<string, double> Explanation)
{
    public string ExplanationText =>
        $"Base {Explanation.GetValueOrDefault("base_weight"):P1} | " +
        $"Alpha {Explanation.GetValueOrDefault("alpha_tilt"):+0.000;-0.000;0.000} | " +
        $"Correlation {Explanation.GetValueOrDefault("correlation_penalty"):0.000} | " +
        $"Drawdown {Explanation.GetValueOrDefault("drawdown_penalty"):0.000} | " +
        $"Capacity {Explanation.GetValueOrDefault("capacity_penalty"):0.000} | " +
        $"Liquidity {Explanation.GetValueOrDefault("liquidity_penalty"):0.000}";
}

public sealed record CapitalAllocationResult(
    double TotalRiskBudget,
    RegimeSnapshot Regime,
    IReadOnlyList<StrategyCapitalAllocation> Allocations);
