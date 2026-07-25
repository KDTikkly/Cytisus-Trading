namespace CytisusTrading.Windows;

public interface IRegimeEngine
{
    RegimeSnapshot Evaluate(
        RegimeInput input,
        DateTimeOffset asOf);
}

public sealed class RegimeEngine : IRegimeEngine
{
    private static readonly string[] Labels =
    {
        "Trend",
        "Range",
        "HighVolatility",
        "Crisis"
    };

    public RegimeSnapshot Evaluate(
        RegimeInput input,
        DateTimeOffset asOf)
    {
        var trend = Clamp(input.TrendStrength);
        var range = Clamp(input.RangeScore);
        var volatility = Clamp(input.RealizedVolatility);
        var crossAssetRisk = Clamp(input.CrossAssetRisk);

        var ruleScores = new Dictionary<string, double>(
            StringComparer.Ordinal)
        {
            ["Trend"] =
                1.20 * trend +
                0.40 * (1 - volatility),
            ["Range"] =
                1.20 * range +
                0.30 * (1 - trend),
            ["HighVolatility"] =
                1.20 * volatility +
                0.50 * crossAssetRisk,
            ["Crisis"] =
                1.50 * crossAssetRisk +
                1.00 * volatility -
                0.40 * trend
        };
        var distanceScores = new Dictionary<string, double>(
            StringComparer.Ordinal)
        {
            ["Trend"] =
                1 - MeanDistance(
                    new[] { trend, volatility, crossAssetRisk },
                    new[] { 0.80, 0.25, 0.20 }),
            ["Range"] =
                1 - MeanDistance(
                    new[] { range, trend, volatility },
                    new[] { 0.80, 0.25, 0.25 }),
            ["HighVolatility"] =
                1 - MeanDistance(
                    new[] { volatility, crossAssetRisk, trend },
                    new[] { 0.80, 0.55, 0.40 }),
            ["Crisis"] =
                1 - MeanDistance(
                    new[] { crossAssetRisk, volatility, trend },
                    new[] { 0.90, 0.90, 0.20 })
        };
        var combined = Labels.ToDictionary(
            label => label,
            label =>
                ruleScores[label] +
                0.70 * distanceScores[label] +
                0.50 * Clamp(
                    input.StrategyReportedFit.GetValueOrDefault(
                        label)),
            StringComparer.Ordinal);
        var probabilities = Softmax(combined);
        var uncertainty = -probabilities.Values
            .Where(value => value > 0)
            .Sum(value => value * Math.Log(value)) /
            Math.Log(Labels.Length);
        var riskMultiplier = Math.Clamp(
            1 -
            0.55 * uncertainty -
            0.45 * probabilities["Crisis"],
            0.20,
            1);
        return new RegimeSnapshot(
            1,
            asOf,
            probabilities,
            uncertainty,
            riskMultiplier,
            new Dictionary<string, double>(
                StringComparer.Ordinal)
            {
                ["rule_trend"] = ruleScores["Trend"],
                ["rule_range"] = ruleScores["Range"],
                ["rule_high_volatility"] =
                    ruleScores["HighVolatility"],
                ["rule_crisis"] = ruleScores["Crisis"],
                ["feature_distance_trend"] =
                    distanceScores["Trend"],
                ["cross_asset_risk"] = crossAssetRisk,
                ["strategy_reported_fit"] =
                    input.StrategyReportedFit.Values
                        .DefaultIfEmpty(0)
                        .Average()
            });
    }

    private static IReadOnlyDictionary<string, double> Softmax(
        IReadOnlyDictionary<string, double> scores)
    {
        var maximum = scores.Values.Max();
        var exponentials = scores.ToDictionary(
            pair => pair.Key,
            pair => Math.Exp(pair.Value - maximum),
            StringComparer.Ordinal);
        var total = exponentials.Values.Sum();
        return exponentials.ToDictionary(
            pair => pair.Key,
            pair => pair.Value / total,
            StringComparer.Ordinal);
    }

    private static double MeanDistance(
        IReadOnlyList<double> values,
        IReadOnlyList<double> prototype)
    {
        return values
            .Select((value, index) =>
                Math.Abs(value - prototype[index]))
            .Average();
    }

    private static double Clamp(double value)
    {
        return Math.Clamp(value, 0, 1);
    }
}

public interface IDynamicCapitalAllocator
{
    CapitalAllocationResult Allocate(
        double totalCapital,
        double baseRiskFraction,
        RegimeSnapshot regime,
        IReadOnlyList<StrategyAllocationInput> strategies);
}

public sealed class DynamicCapitalAllocator :
    IDynamicCapitalAllocator
{
    public const double MaximumAlphaTilt = 0.15;
    private const double SmoothingRate = 0.30;

    public CapitalAllocationResult Allocate(
        double totalCapital,
        double baseRiskFraction,
        RegimeSnapshot regime,
        IReadOnlyList<StrategyAllocationInput> strategies)
    {
        var totalRiskBudget =
            Math.Max(0, totalCapital) *
            Math.Clamp(baseRiskFraction, 0, 1) *
            regime.RiskMultiplier;
        var eligible = strategies
            .Where(strategy =>
                strategy.Health != HealthState.Unhealthy)
            .OrderBy(strategy => strategy.StrategyId, StringComparer.Ordinal)
            .ToArray();
        if (eligible.Length == 0)
        {
            return new CapitalAllocationResult(
                totalRiskBudget,
                regime,
                Array.Empty<StrategyCapitalAllocation>());
        }

        var inverseVolatility = eligible.ToDictionary(
            strategy => strategy.StrategyId,
            strategy => 1 / Math.Max(0.01, strategy.Volatility),
            StringComparer.Ordinal);
        var inverseTotal = inverseVolatility.Values.Sum();
        var drafts = eligible.Select(strategy =>
        {
            var baseWeight =
                inverseVolatility[strategy.StrategyId] /
                inverseTotal;
            var expectedAlpha =
                0.32 * Clamp(strategy.LongTermOos) +
                0.18 * Clamp(strategy.RecentLive) +
                0.10 * Clamp(strategy.RecentPaper) +
                0.10 * Clamp(strategy.SignalStrength) +
                0.10 * Clamp(strategy.RegimeFit) +
                0.06 * Clamp(strategy.ConfidenceCalibration) +
                0.14 * Clamp(strategy.DataQuality) -
                0.20 * Clamp(strategy.ModelUncertainty);
            if (strategy.IsNew)
            {
                expectedAlpha =
                    0.50 * expectedAlpha +
                    0.25;
            }
            var alphaTilt = Math.Clamp(
                (expectedAlpha - 0.50) * 0.30,
                -MaximumAlphaTilt,
                MaximumAlphaTilt);
            var correlationPenalty =
                1 - 0.45 * Clamp(strategy.AverageCorrelation);
            var drawdownPenalty =
                1 - 0.70 * Clamp(strategy.Drawdown);
            var capacityPenalty =
                0.35 + 0.65 * Clamp(strategy.Capacity);
            var liquidityPenalty =
                0.35 + 0.65 * Clamp(strategy.Liquidity);
            var raw =
                baseWeight *
                (1 + alphaTilt) *
                correlationPenalty *
                drawdownPenalty *
                capacityPenalty *
                liquidityPenalty;
            return new AllocationDraft(
                strategy,
                baseWeight,
                alphaTilt,
                correlationPenalty,
                drawdownPenalty,
                capacityPenalty,
                liquidityPenalty,
                Math.Max(0, raw));
        }).ToArray();

        var rawTotal = drafts.Sum(draft => draft.RawWeight);
        var smoothed = drafts.Select(draft =>
        {
            var target = rawTotal <= 0
                ? 1.0 / drafts.Length
                : draft.RawWeight / rawTotal;
            var current = Math.Max(
                0,
                draft.Input.CurrentWeight);
            return (
                Draft: draft,
                Weight:
                    (1 - SmoothingRate) * current +
                    SmoothingRate * target,
                Target: target);
        }).ToArray();
        var smoothedTotal = smoothed.Sum(item => item.Weight);
        var allocations = smoothed.Select(item =>
        {
            var finalWeight = smoothedTotal <= 0
                ? 1.0 / smoothed.Length
                : item.Weight / smoothedTotal;
            return new StrategyCapitalAllocation(
                1,
                item.Draft.Input.StrategyId,
                finalWeight,
                totalRiskBudget * finalWeight,
                new Dictionary<string, double>(
                    StringComparer.Ordinal)
                {
                    ["base_weight"] =
                        item.Draft.BaseWeight,
                    ["expected_alpha_tilt"] =
                        item.Draft.AlphaTilt,
                    ["alpha_tilt"] =
                        item.Draft.AlphaTilt,
                    ["correlation_penalty"] =
                        item.Draft.CorrelationPenalty,
                    ["drawdown_penalty"] =
                        item.Draft.DrawdownPenalty,
                    ["capacity_penalty"] =
                        item.Draft.CapacityPenalty,
                    ["liquidity_penalty"] =
                        item.Draft.LiquidityPenalty,
                    ["turnover_target"] = item.Target,
                    ["turnover_smoothed_weight"] =
                        finalWeight,
                    ["regime_uncertainty"] =
                        regime.Uncertainty,
                    ["regime_risk_multiplier"] =
                        regime.RiskMultiplier,
                    ["new_strategy_prior"] =
                        item.Draft.Input.IsNew ? 0.50 : 1
                });
        }).ToArray();

        return new CapitalAllocationResult(
            totalRiskBudget,
            regime,
            allocations);
    }

    private static double Clamp(double value)
    {
        return Math.Clamp(value, 0, 1);
    }

    private sealed record AllocationDraft(
        StrategyAllocationInput Input,
        double BaseWeight,
        double AlphaTilt,
        double CorrelationPenalty,
        double DrawdownPenalty,
        double CapacityPenalty,
        double LiquidityPenalty,
        double RawWeight);
}
