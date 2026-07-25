using System.Globalization;

namespace CytisusTrading.Windows;

public interface IFactorSearchService
{
    FactorSearchResult RunTinySearch(
        NormalizedResearchDataset dataset,
        IReadOnlyList<FactorDefinition> existingDefinitions,
        FactorSearchConfiguration configuration);
}

public sealed class FactorSearchService : IFactorSearchService
{
    private const string SearchAlgorithm =
        "deterministic-constrained-beam-v1";
    private readonly IFactorDSLService _dsl;
    private readonly IFactorResearchStore _store;

    public FactorSearchService(
        IFactorDSLService dsl,
        IFactorResearchStore store)
    {
        _dsl = dsl;
        _store = store;
    }

    public FactorSearchResult RunTinySearch(
        NormalizedResearchDataset dataset,
        IReadOnlyList<FactorDefinition> existingDefinitions,
        FactorSearchConfiguration configuration)
    {
        var drafts = SeedDrafts().ToList();
        var evaluated = new List<CandidateEvaluation>();
        var attemptedExpressions = new HashSet<string>(
            StringComparer.Ordinal);

        foreach (var draft in drafts)
        {
            if (evaluated.Count >= configuration.MaximumCandidates)
            {
                break;
            }
            if (attemptedExpressions.Add(draft.Expression))
            {
                evaluated.Add(Evaluate(
                    draft,
                    dataset,
                    evaluated.Count,
                    configuration));
            }
        }

        for (var generation = 1;
             generation < configuration.MaximumGenerations &&
             evaluated.Count < configuration.MaximumCandidates;
             generation += 1)
        {
            var beam = evaluated
                .OrderByDescending(item => item.RawScore)
                .ThenBy(item => item.Draft.Expression, StringComparer.Ordinal)
                .Take(Math.Min(
                    configuration.BeamWidth,
                    configuration.TopK))
                .ToArray();
            var expansion = beam
                .SelectMany(item => Expand(item.Draft, generation))
                .OrderBy(item => item.Family, StringComparer.Ordinal)
                .ThenBy(item => item.Expression, StringComparer.Ordinal)
                .ToArray();
            foreach (var draft in expansion)
            {
                if (evaluated.Count >= configuration.MaximumCandidates)
                {
                    break;
                }
                if (attemptedExpressions.Add(draft.Expression))
                {
                    evaluated.Add(Evaluate(
                        draft,
                        dataset,
                        evaluated.Count,
                        configuration));
                }
            }
        }

        var stabilized = ApplyNeighboringHorizonStability(evaluated);
        foreach (var candidate in stabilized)
        {
            _store.AppendFactorTrial(candidate.Trial);
        }

        var summaries = BuildSummaries(
            existingDefinitions,
            stabilized);
        return new FactorSearchResult(
            $"Completed tiny deterministic beam search: {stabilized.Count} trials retained.",
            stabilized.Count,
            stabilized.Count(item =>
                item.Trial.Result == FactorTrialResult.Candidate),
            stabilized.Count(item =>
                item.Trial.Result == FactorTrialResult.Rejected),
            stabilized.Count(item =>
                item.Trial.Result == FactorTrialResult.Quarantined),
            stabilized.Select(item => item.Trial).ToArray(),
            summaries);
    }

    private CandidateEvaluation Evaluate(
        CandidateDraft draft,
        NormalizedResearchDataset dataset,
        int attemptIndex,
        FactorSearchConfiguration configuration)
    {
        ParsedFactorExpression? parsed = null;
        FactorEvaluation? evaluation = null;
        string? rejection = null;
        var trialResult = FactorTrialResult.Rejected;
        try
        {
            parsed = _dsl.Parse(
                draft.Expression,
                configuration.MaximumDepth,
                configuration.MaximumOperators);
            var maximumHistory = dataset.Observations
                .GroupBy(observation => observation.Symbol)
                .Select(group => group.Count())
                .DefaultIfEmpty(0)
                .Max();
            if (parsed.MinimumHistory > maximumHistory)
            {
                rejection =
                    $"Minimum history {parsed.MinimumHistory} exceeds available history {maximumHistory}.";
            }
            else
            {
                evaluation = _dsl.Evaluate(parsed, dataset);
            }
        }
        catch (FactorDSLException exception)
        {
            rejection = exception.Message;
            if (exception.Message.Contains(
                    "future",
                    StringComparison.OrdinalIgnoreCase) ||
                exception.Message.Contains(
                    "Temporal safety",
                    StringComparison.OrdinalIgnoreCase))
            {
                trialResult = FactorTrialResult.Quarantined;
            }
        }

        var metrics = evaluation is null || parsed is null
            ? EmptyMetrics(parsed?.OperatorCount ?? 0, attemptIndex)
            : Metrics(
                draft,
                parsed,
                evaluation,
                dataset,
                attemptIndex);
        if (evaluation is not null &&
            metrics["coverage"] >= 0.35 &&
            metrics["task_metric"] >= 0.15 &&
            metrics["marginal_contribution"] > 0)
        {
            trialResult = FactorTrialResult.Candidate;
        }
        else if (trialResult != FactorTrialResult.Quarantined)
        {
            trialResult = FactorTrialResult.Rejected;
            rejection ??=
                "Candidate failed data quality, task evidence, or marginal-contribution gates.";
        }

        var trial = new FactorTrial(
            1,
            $"trial-{StableHash($"{draft.Family}|{draft.Expression}|{draft.Generation}|{attemptIndex}")}",
            draft.Family,
            draft.Expression,
            new Dictionary<string, string>
            {
                ["horizon"] = draft.Horizon,
                ["factor_type"] = draft.Type.ToString(),
                ["normalization"] = draft.Normalization
            },
            dataset.DatasetVersion,
            dataset.UniverseVersion,
            SearchAlgorithm,
            draft.Generation,
            (int)metrics["oos_windows"],
            metrics,
            trialResult,
            trialResult == FactorTrialResult.Candidate
                ? null
                : rejection,
            dataset.CreatedAt.AddMilliseconds(attemptIndex));
        return new CandidateEvaluation(
            draft,
            trial,
            Evidence(trial),
            metrics["marginal_contribution"]);
    }

    private static Dictionary<string, double> Metrics(
        CandidateDraft draft,
        ParsedFactorExpression parsed,
        FactorEvaluation evaluation,
        NormalizedResearchDataset dataset,
        int attemptIndex)
    {
        var paired = PairedValues(
            evaluation.Values,
            Target(draft.Type, dataset));
        var basicTaskMetric = TaskMetric(draft.Type, paired);
        var purgedOos = PurgedWalkForward(draft.Type, paired);
        var taskMetric = purgedOos.Windows > 0
            ? purgedOos.Score
            : 0;
        var stability = Stability(paired);
        var turnover = Turnover(
            evaluation.Values,
            dataset);
        var costProxy = turnover * 0.002;
        var capacityProxy = Math.Clamp(
            Math.Log10(Math.Max(
                10,
                dataset.Observations.Average(item => item.Volume))) / 8,
            0,
            1);
        var existingCorrelation = Math.Abs(
            FactorDSLService.Correlation(
                paired.Select(pair => pair.Factor).ToArray(),
                paired.Select(pair => pair.Target).ToArray()) ?? 0);
        var penalty =
            Math.Log(2 + attemptIndex) * 0.006 +
            parsed.OperatorCount * 0.004;
        var marginal =
            taskMetric *
            evaluation.Coverage *
            stability -
            costProxy -
            Math.Max(0, existingCorrelation - 0.80) * 0.20 -
            penalty;
        return new Dictionary<string, double>(
            StringComparer.Ordinal)
        {
            ["coverage"] = evaluation.Coverage,
            ["missing_rate"] = 1 - evaluation.Coverage,
            ["task_metric"] = taskMetric,
            ["basic_task_metric"] = basicTaskMetric,
            ["purged_oos_score"] = purgedOos.Score,
            ["stability"] = stability,
            ["turnover"] = turnover,
            ["cost_proxy"] = costProxy,
            ["capacity_proxy"] = capacityProxy,
            ["existing_factor_correlation"] =
                existingCorrelation,
            ["neighboring_horizon_stability"] = 0,
            ["marginal_contribution"] = marginal,
            ["oos_windows"] = purgedOos.Windows,
            ["multiple_testing_penalty"] = penalty,
            ["complexity"] = parsed.OperatorCount
        };
    }

    private static Dictionary<string, double> EmptyMetrics(
        int complexity,
        int attemptIndex)
    {
        return new Dictionary<string, double>(
            StringComparer.Ordinal)
        {
            ["coverage"] = 0,
            ["missing_rate"] = 1,
            ["task_metric"] = 0,
            ["basic_task_metric"] = 0,
            ["purged_oos_score"] = 0,
            ["stability"] = 0,
            ["turnover"] = 0,
            ["cost_proxy"] = 0,
            ["capacity_proxy"] = 0,
            ["existing_factor_correlation"] = 0,
            ["neighboring_horizon_stability"] = 0,
            ["marginal_contribution"] = -0.01,
            ["oos_windows"] = 0,
            ["multiple_testing_penalty"] =
                Math.Log(2 + attemptIndex) * 0.006,
            ["complexity"] = complexity
        };
    }

    private static IReadOnlyList<CandidateEvaluation>
        ApplyNeighboringHorizonStability(
            IReadOnlyList<CandidateEvaluation> evaluated)
    {
        var output = new List<CandidateEvaluation>();
        foreach (var candidate in evaluated)
        {
            var days = FactorHorizons.Days(candidate.Draft.Horizon);
            var neighbor = evaluated
                .Where(item =>
                    item.Draft.Family == candidate.Draft.Family &&
                    item.Draft.Expression != candidate.Draft.Expression)
                .OrderBy(item => Math.Abs(
                    FactorHorizons.Days(item.Draft.Horizon) - days))
                .ThenBy(item => item.Draft.Expression, StringComparer.Ordinal)
                .FirstOrDefault();
            var stability = neighbor is null
                ? 0.35
                : Math.Clamp(
                    1 - Math.Abs(
                        candidate.RawScore -
                        neighbor.RawScore),
                    0,
                    1);
            var metrics = candidate.Trial.Metrics.ToDictionary(
                pair => pair.Key,
                pair => pair.Value,
                StringComparer.Ordinal);
            metrics["neighboring_horizon_stability"] = stability;
            metrics["marginal_contribution"] =
                metrics["marginal_contribution"] +
                stability * 0.05;
            var result = candidate.Trial.Result;
            var rejection = candidate.Trial.RejectionReason;
            if (result == FactorTrialResult.Candidate &&
                stability < 0.25)
            {
                result = FactorTrialResult.Rejected;
                rejection =
                    "An isolated horizon optimum lacked neighboring-horizon stability.";
            }
            var trial = candidate.Trial with
            {
                Metrics = metrics,
                Result = result,
                RejectionReason = result == FactorTrialResult.Candidate
                    ? null
                    : rejection
            };
            output.Add(candidate with
            {
                Trial = trial,
                Evidence = Evidence(trial),
                RawScore = metrics["marginal_contribution"]
            });
        }
        return output
            .OrderBy(item => item.Trial.Generation)
            .ThenBy(item => item.Trial.FactorFamily, StringComparer.Ordinal)
            .ThenBy(item => item.Trial.Expression, StringComparer.Ordinal)
            .ToArray();
    }

    private static IReadOnlyList<FactorResearchSummary> BuildSummaries(
        IReadOnlyList<FactorDefinition> definitions,
        IReadOnlyList<CandidateEvaluation> evaluated)
    {
        return definitions
            .OrderBy(definition => definition.FactorId, StringComparer.Ordinal)
            .Select(definition =>
            {
                var trials = evaluated
                    .Where(item =>
                        item.Draft.Family == definition.FactorId)
                    .OrderByDescending(item => item.RawScore)
                    .ToArray();
                var best = trials.FirstOrDefault();
                var evidence = best?.Evidence ??
                    DefaultEvidence(definition);
                var strategyState = definition.StrategyStates
                    .GetValueOrDefault(
                        "cross-sectional-multifactor",
                        definition.State);
                return new FactorResearchSummary(
                    definition,
                    definition.State,
                    strategyState,
                    trials.Length,
                    evidence,
                    best?.Trial.RejectionReason ??
                        $"Fixture definition is {definition.State}.");
            })
            .ToArray();
    }

    public static IReadOnlyList<FactorResearchSummary> InitialSummaries(
        IReadOnlyList<FactorDefinition> definitions,
        IReadOnlyList<FactorTrial> trials)
    {
        return definitions
            .OrderBy(definition => definition.FactorId, StringComparer.Ordinal)
            .Select(definition =>
            {
                var familyTrials = trials
                    .Where(trial =>
                        trial.FactorFamily == definition.FactorId)
                    .OrderByDescending(trial =>
                        trial.Metrics.GetValueOrDefault(
                            "marginal_contribution"))
                    .ToArray();
                var best = familyTrials.FirstOrDefault();
                return new FactorResearchSummary(
                    definition,
                    definition.State,
                    definition.StrategyStates.GetValueOrDefault(
                        "cross-sectional-multifactor",
                        definition.State),
                    familyTrials.Length,
                    best is null
                        ? DefaultEvidence(definition)
                        : Evidence(best),
                    best?.RejectionReason ??
                        $"Fixture definition is {definition.State}.");
            })
            .ToArray();
    }

    private static FactorEvidence Evidence(FactorTrial trial)
    {
        var metricName = trial.Parameters.GetValueOrDefault(
            "factor_type") switch
        {
            "Alpha" => "Rank IC",
            "Risk" => "Volatility accuracy",
            "Regime" => "Regime accuracy",
            "Liquidity" => "Capacity accuracy",
            "Execution" => "Fill accuracy",
            _ => "Task metric"
        };
        return new FactorEvidence(
            trial.Metrics.GetValueOrDefault("coverage"),
            trial.Metrics.GetValueOrDefault("missing_rate"),
            trial.Metrics.GetValueOrDefault("task_metric"),
            metricName,
            trial.Metrics.GetValueOrDefault("stability"),
            trial.Metrics.GetValueOrDefault("turnover"),
            trial.Metrics.GetValueOrDefault("cost_proxy"),
            trial.Metrics.GetValueOrDefault("capacity_proxy"),
            trial.Metrics.GetValueOrDefault(
                "existing_factor_correlation"),
            trial.Metrics.GetValueOrDefault(
                "neighboring_horizon_stability"),
            trial.Metrics.GetValueOrDefault(
                "marginal_contribution"),
            trial.OosWindows,
            trial.Metrics.GetValueOrDefault(
                "multiple_testing_penalty"),
            trial.Metrics.GetValueOrDefault("stability") >= 0.5
                ? "Stable across fixture regime slices"
                : "Regime evidence remains conditional");
    }

    private static FactorEvidence DefaultEvidence(
        FactorDefinition definition)
    {
        var taskMetricName = definition.FactorType switch
        {
            FactorTaskType.Alpha => "Rank IC",
            FactorTaskType.Risk => "Volatility accuracy",
            FactorTaskType.Regime => "Regime accuracy",
            FactorTaskType.Liquidity => "Capacity accuracy",
            FactorTaskType.Execution => "Fill accuracy",
            _ => "Task metric"
        };
        return new FactorEvidence(
            0,
            1,
            0,
            taskMetricName,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            "Fixture evidence pending");
    }

    private static IReadOnlyList<(double Factor, double Target)>
        PairedValues(
            IReadOnlyList<double?> factor,
            IReadOnlyList<double?> target)
    {
        return Enumerable.Range(0, factor.Count)
            .Where(index =>
                factor[index].HasValue &&
                target[index].HasValue)
            .Select(index => (
                factor[index]!.Value,
                target[index]!.Value))
            .ToArray();
    }

    private static IReadOnlyList<double?> Target(
        FactorTaskType type,
        NormalizedResearchDataset dataset)
    {
        var result = new double?[dataset.Observations.Count];
        var grouped = Enumerable.Range(0, dataset.Observations.Count)
            .GroupBy(index => dataset.Observations[index].Symbol);
        foreach (var group in grouped)
        {
            var indices = group
                .OrderBy(index => dataset.Observations[index].EventTime)
                .ToArray();
            for (var offset = 0; offset < indices.Length - 1; offset += 1)
            {
                var current = dataset.Observations[indices[offset]];
                var next = dataset.Observations[indices[offset + 1]];
                result[indices[offset]] = type switch
                {
                    FactorTaskType.Alpha => next.Returns,
                    FactorTaskType.Risk => Math.Abs(next.Returns),
                    FactorTaskType.Regime =>
                        next.Returns > next.MarketReturn ? 1 : -1,
                    FactorTaskType.Liquidity =>
                        Math.Log10(Math.Max(1, next.Volume)),
                    FactorTaskType.Execution =>
                        next.Volume /
                        Math.Max(0.01, next.High - next.Low),
                    _ => next.Returns
                };
            }
        }
        return result;
    }

    private static double TaskMetric(
        FactorTaskType type,
        IReadOnlyList<(double Factor, double Target)> paired)
    {
        if (paired.Count < 2)
        {
            return 0;
        }
        if (type == FactorTaskType.Regime)
        {
            return paired.Count(item =>
                Math.Sign(item.Factor) == Math.Sign(item.Target)) /
                (double)paired.Count;
        }
        var correlation = FactorDSLService.Correlation(
            paired.Select(item => item.Factor).ToArray(),
            paired.Select(item => item.Target).ToArray()) ?? 0;
        return Math.Abs(correlation);
    }

    private static (int Windows, double Score) PurgedWalkForward(
        FactorTaskType type,
        IReadOnlyList<(double Factor, double Target)> paired)
    {
        if (paired.Count < 4)
        {
            return (0, 0);
        }
        var starts = new[]
            {
                Math.Max(2, paired.Count / 2),
                Math.Max(3, paired.Count * 3 / 4)
            }
            .Where(start => start < paired.Count - 1)
            .Distinct()
            .OrderBy(start => start)
            .ToArray();
        var scores = new List<double>();
        foreach (var testStart in starts)
        {
            var trainingCount = testStart - 1;
            if (trainingCount < 1)
            {
                continue;
            }
            var test = paired.Skip(testStart).ToArray();
            if (test.Length < 2)
            {
                continue;
            }
            scores.Add(TaskMetric(type, test));
        }
        return scores.Count == 0
            ? (0, 0)
            : (scores.Count, scores.Average());
    }

    private static double Stability(
        IReadOnlyList<(double Factor, double Target)> paired)
    {
        if (paired.Count < 2)
        {
            return 0;
        }
        var midpoint = Math.Max(1, paired.Count / 2);
        var first = paired.Take(midpoint).ToArray();
        var second = paired.Skip(midpoint).ToArray();
        if (second.Length == 0)
        {
            return 0.5;
        }
        var firstDirection = first.Average(item =>
            Math.Sign(item.Factor * item.Target));
        var secondDirection = second.Average(item =>
            Math.Sign(item.Factor * item.Target));
        return Math.Clamp(
            1 - Math.Abs(firstDirection - secondDirection) / 2,
            0,
            1);
    }

    private static double Turnover(
        IReadOnlyList<double?> values,
        NormalizedResearchDataset dataset)
    {
        var changes = new List<double>();
        foreach (var group in Enumerable.Range(0, values.Count)
                     .GroupBy(index =>
                         dataset.Observations[index].Symbol))
        {
            var indices = group
                .OrderBy(index =>
                    dataset.Observations[index].EventTime)
                .Where(index => values[index].HasValue)
                .ToArray();
            for (var index = 1; index < indices.Length; index += 1)
            {
                var previous = values[indices[index - 1]]!.Value;
                var current = values[indices[index]]!.Value;
                changes.Add(
                    Math.Abs(current - previous) /
                    (1 + Math.Abs(previous)));
            }
        }
        return changes.Count == 0
            ? 0
            : Math.Clamp(changes.Average(), 0, 1);
    }

    private static IEnumerable<CandidateDraft> SeedDrafts()
    {
        yield return Draft(
            "short-term-reversal",
            FactorTaskType.Alpha,
            "forward_cross_sectional_return",
            "3d",
            "delta(close,{w})");
        yield return Draft(
            "medium-term-momentum",
            FactorTaskType.Alpha,
            "forward_cross_sectional_return",
            "20d",
            "delta(close,{w})");
        yield return Draft(
            "volatility-adjusted-momentum",
            FactorTaskType.Alpha,
            "forward_cross_sectional_return",
            "20d",
            "safe_divide(delta(close,{w}),rolling_std(returns,{w}))");
        yield return Draft(
            "volume-shock",
            FactorTaskType.Liquidity,
            "forward_capacity",
            "3d",
            "zscore(delta(volume,{w}))");
        yield return Draft(
            "volatility-contraction",
            FactorTaskType.Risk,
            "forward_realized_volatility",
            "20d",
            "signed_power(rolling_std(returns,{w}),-1)");
        yield return Draft(
            "liquidity",
            FactorTaskType.Liquidity,
            "forward_capacity",
            "5d",
            "safe_divide(volume,rolling_mean(volume,{w}))");
        yield return Draft(
            "capital-flow-persistence",
            FactorTaskType.Liquidity,
            "forward_capacity",
            "5d",
            "rolling_mean(capital_flow,{w})");
        yield return Draft(
            "market-relative-strength",
            FactorTaskType.Regime,
            "trend_regime_probability",
            "20d",
            "rolling_corr(returns,market_return,{w})");
        yield return Draft(
            "sector-relative-strength",
            FactorTaskType.Alpha,
            "forward_cross_sectional_return",
            "20d",
            "rolling_corr(returns,sector_return,{w})");
    }

    private static CandidateDraft Draft(
        string family,
        FactorTaskType type,
        string target,
        string horizon,
        string template)
    {
        return new CandidateDraft(
            family,
            type,
            target,
            horizon,
            template.Replace(
                "{w}",
                FactorHorizons.Days(horizon).ToString(
                    CultureInfo.InvariantCulture),
                StringComparison.Ordinal),
            0,
            "seed");
    }

    private static IEnumerable<CandidateDraft> Expand(
        CandidateDraft draft,
        int generation)
    {
        var currentIndex = FactorHorizons.Daily
            .Select((value, index) => (value, index))
            .Single(item => item.value == draft.Horizon)
            .index;
        foreach (var index in new[]
                 {
                     Math.Max(0, currentIndex - 1),
                     Math.Min(FactorHorizons.Daily.Count - 1, currentIndex + 1)
                 }
                 .Distinct())
        {
            var horizon = FactorHorizons.Daily[index];
            var oldWindow = FactorHorizons.Days(draft.Horizon)
                .ToString(CultureInfo.InvariantCulture);
            var newWindow = FactorHorizons.Days(horizon)
                .ToString(CultureInfo.InvariantCulture);
            yield return draft with
            {
                Horizon = horizon,
                Expression = draft.Expression.Replace(
                    $",{oldWindow})",
                    $",{newWindow})",
                    StringComparison.Ordinal),
                Generation = generation,
                Normalization = "horizon"
            };
        }
        yield return draft with
        {
            Expression = $"winsorize({draft.Expression})",
            Generation = generation,
            Normalization = "winsorize"
        };
        yield return draft with
        {
            Expression = $"zscore({draft.Expression})",
            Generation = generation,
            Normalization = "zscore"
        };
        yield return draft with
        {
            Expression = $"sector_neutralize({draft.Expression})",
            Generation = generation,
            Normalization = "sector_neutralize"
        };
        yield return draft with
        {
            Expression =
                $"safe_divide({draft.Expression},rolling_std(returns,{FactorHorizons.Days(draft.Horizon)}))",
            Generation = generation,
            Normalization = "volatility_scale"
        };
    }

    private static string StableHash(string value)
    {
        const ulong offset = 14695981039346656037;
        const ulong prime = 1099511628211;
        var hash = offset;
        foreach (var item in System.Text.Encoding.UTF8.GetBytes(value))
        {
            hash ^= item;
            hash *= prime;
        }
        return hash.ToString("x16", CultureInfo.InvariantCulture);
    }

    private static double StableUnit(string value)
    {
        var hash = StableHash(value);
        var tail = ulong.Parse(
            hash[^8..],
            NumberStyles.HexNumber,
            CultureInfo.InvariantCulture);
        return tail / (double)uint.MaxValue;
    }

    private sealed record CandidateDraft(
        string Family,
        FactorTaskType Type,
        string Target,
        string Horizon,
        string Expression,
        int Generation,
        string Normalization);

    private sealed record CandidateEvaluation(
        CandidateDraft Draft,
        FactorTrial Trial,
        FactorEvidence Evidence,
        double RawScore);
}
