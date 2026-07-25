using System.IO;

namespace CytisusTrading.Windows;

public static class Prompt4Smoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            Directory.CreateDirectory(rootDirectory);
            var store = new JsonFilePersistentStore(
                Path.Combine(rootDirectory, "store-one"));
            store.InitializeSchema();
            var cache = new JsonMarketDataCache(
                Path.Combine(rootDirectory, "market-cache"));
            var universe = new UniverseService();
            var source = new FixtureLongbridgeDataService(
                cache,
                universe).LoadFixtureSnapshot();
            var fixtures = new ResearchFixtureService();
            var dataset = fixtures.BuildDataset(source);
            var definitions = fixtures.LoadFactorDefinitions();
            if (definitions.Select(item => item.FactorType).Distinct().Count() != 5 ||
                FactorHorizons.Daily.Count != 8)
            {
                return 2;
            }

            var dsl = new FactorDSLService();
            try
            {
                _ = dsl.Parse("lag(close,-1)");
                return 3;
            }
            catch (FactorDSLException exception)
            {
                if (!exception.Message.Contains(
                        "future",
                        StringComparison.OrdinalIgnoreCase))
                {
                    return 4;
                }
            }

            var expression = dsl.Parse("safe_divide(delta(close,1),lag(volume,1))");
            var firstEvaluation = dsl.Evaluate(expression, dataset);
            var secondEvaluation = dsl.Evaluate(expression, dataset);
            if (!firstEvaluation.Values.SequenceEqual(secondEvaluation.Values) ||
                firstEvaluation.Coverage <= 0)
            {
                return 5;
            }

            var search = new FactorSearchService(dsl, store);
            var firstSearch = search.RunTinySearch(
                dataset,
                definitions,
                FactorSearchConfiguration.Tiny);
            if (firstSearch.EvaluatedCount >
                    FactorSearchConfiguration.Tiny.MaximumCandidates ||
                firstSearch.Trials.Any(trial =>
                    trial.Generation >=
                    FactorSearchConfiguration.Tiny.MaximumGenerations) ||
                firstSearch.RejectedCount == 0 ||
                store.LoadFactorTrials(1000).Count !=
                    firstSearch.EvaluatedCount)
            {
                return 6;
            }

            var secondStore = new JsonFilePersistentStore(
                Path.Combine(rootDirectory, "store-two"));
            secondStore.InitializeSchema();
            var secondSearch = new FactorSearchService(
                new FactorDSLService(),
                secondStore).RunTinySearch(
                    dataset,
                    definitions,
                    FactorSearchConfiguration.Tiny);
            if (!firstSearch.Trials.Select(ComparableTrial)
                .SequenceEqual(secondSearch.Trials.Select(ComparableTrial)))
            {
                return 7;
            }

            var lifecycle = new FactorLifecycleService();
            var baseline = new FactorLifecycleEvidence(
                false,
                false,
                false,
                false,
                false,
                true,
                0.70,
                0.75,
                false,
                0,
                0.10,
                0,
                false);
            if (lifecycle.Evaluate(
                    FactorState.Active,
                    baseline with { LookAheadBias = true }).State !=
                    FactorState.Quarantined ||
                lifecycle.Evaluate(
                    FactorState.Active,
                    baseline with
                    {
                        ShortTermScore = 0.20,
                        LongTermScore = 0.72
                    }).State != FactorState.Reduced ||
                lifecycle.Evaluate(
                    FactorState.Active,
                    baseline with { RepeatedOosFailures = 2 }).State !=
                    FactorState.Probation ||
                lifecycle.Evaluate(
                    FactorState.Active,
                    baseline with
                    {
                        ChangePointProbability = 0.85,
                        CounterfactualImprovement = 0.03
                    }).State != FactorState.Retired ||
                lifecycle.Evaluate(
                    FactorState.Retired,
                    baseline with { RenewedEvidence = true }).State !=
                    FactorState.Shadow ||
                lifecycle.Evaluate(
                    FactorState.Quarantined,
                    baseline with { RenewedEvidence = true }).State !=
                    FactorState.Quarantined)
            {
                return 8;
            }

            var regimeEngine = new RegimeEngine();
            var allocationFixture =
                fixtures.LoadRegimeAllocationFixture();
            var regime = regimeEngine.Evaluate(
                allocationFixture.RegimeInput,
                dataset.CreatedAt);
            if (Math.Abs(regime.Probabilities.Values.Sum() - 1) >
                    0.000000001 ||
                regime.Probabilities.Values.Any(value =>
                    value < 0 || value > 1))
            {
                return 9;
            }
            var uncertain = regimeEngine.Evaluate(
                new RegimeInput(
                    0.5,
                    0.5,
                    0.5,
                    0.5,
                    new Dictionary<string, double>
                    {
                        ["Trend"] = 0.5,
                        ["Range"] = 0.5,
                        ["HighVolatility"] = 0.5,
                        ["Crisis"] = 0.5
                    }),
                dataset.CreatedAt);
            var decisive = regimeEngine.Evaluate(
                new RegimeInput(
                    1,
                    0,
                    0.05,
                    0.05,
                    new Dictionary<string, double>
                    {
                        ["Trend"] = 1,
                        ["Range"] = 0,
                        ["HighVolatility"] = 0,
                        ["Crisis"] = 0
                    }),
                dataset.CreatedAt);
            if (uncertain.Uncertainty <= decisive.Uncertainty ||
                uncertain.RiskMultiplier >= decisive.RiskMultiplier)
            {
                return 10;
            }

            var allocator = new DynamicCapitalAllocator();
            var allocationOne = allocator.Allocate(
                allocationFixture.TotalCapital,
                allocationFixture.BaseRiskFraction,
                regime,
                allocationFixture.Strategies);
            var allocationTwo = allocator.Allocate(
                allocationFixture.TotalCapital,
                allocationFixture.BaseRiskFraction,
                regime,
                allocationFixture.Strategies);
            if (allocationOne.Allocations.Any(allocation =>
                    Math.Abs(allocation.Explanation["alpha_tilt"]) >
                    DynamicCapitalAllocator.MaximumAlphaTilt +
                    0.000000001) ||
                !allocationOne.Allocations.SequenceEqual(
                    allocationTwo.Allocations,
                    StrategyAllocationComparer.Instance) ||
                Math.Abs(
                    allocationOne.Allocations.Sum(item =>
                        item.CapitalBudget) -
                    allocationOne.TotalRiskBudget) > 0.01)
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

    private static string ComparableTrial(FactorTrial trial)
    {
        return string.Join(
            "|",
            trial.FactorFamily,
            trial.Expression,
            trial.Generation,
            trial.Result,
            trial.RejectionReason ?? "",
            string.Join(
                ",",
                trial.Metrics
                    .OrderBy(pair => pair.Key, StringComparer.Ordinal)
                    .Select(pair =>
                        $"{pair.Key}={pair.Value:R}")));
    }

    private sealed class StrategyAllocationComparer :
        IEqualityComparer<StrategyCapitalAllocation>
    {
        public static StrategyAllocationComparer Instance { get; } = new();

        public bool Equals(
            StrategyCapitalAllocation? left,
            StrategyCapitalAllocation? right)
        {
            if (ReferenceEquals(left, right))
            {
                return true;
            }
            if (left is null || right is null)
            {
                return false;
            }
            return left.StrategyId == right.StrategyId &&
                left.FinalWeight == right.FinalWeight &&
                left.CapitalBudget == right.CapitalBudget &&
                left.Explanation.OrderBy(pair => pair.Key)
                    .SequenceEqual(
                        right.Explanation.OrderBy(pair => pair.Key));
        }

        public int GetHashCode(StrategyCapitalAllocation value)
        {
            return HashCode.Combine(
                value.StrategyId,
                value.FinalWeight,
                value.CapitalBudget);
        }
    }
}
