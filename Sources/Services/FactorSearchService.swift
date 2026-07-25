import Foundation

final class FactorSearchService {
    private let dsl: FactorDSLService
    private let store: FactorResearchStore
    private let searchAlgorithm = "deterministic-constrained-beam-v1"

    init(dsl: FactorDSLService, store: FactorResearchStore) {
        self.dsl = dsl
        self.store = store
    }

    func runTinySearch(
        dataset: NormalizedResearchDataset,
        existingDefinitions: [FactorDefinition],
        configuration: FactorSearchConfiguration = .tiny
    ) throws -> FactorSearchResult {
        var evaluated: [CandidateEvaluation] = []
        var attempted = Set<String>()
        for draft in seedDrafts()
            where evaluated.count < configuration.maximumCandidates {
            if attempted.insert(draft.expression).inserted {
                evaluated.append(
                    evaluate(
                        draft,
                        dataset: dataset,
                        attempt: evaluated.count,
                        configuration: configuration
                    )
                )
            }
        }
        if configuration.maximumGenerations > 1 {
            for generation in 1..<configuration.maximumGenerations
                where evaluated.count < configuration.maximumCandidates {
                let sortedEvaluated: [CandidateEvaluation] =
                    evaluated.sorted {
                    $0.rawScore == $1.rawScore
                        ? $0.draft.expression < $1.draft.expression
                        : $0.rawScore > $1.rawScore
                }
                let beamLimit = min(
                    configuration.beamWidth,
                    configuration.topK
                )
                let beam: [CandidateEvaluation] = Array(
                    sortedEvaluated.prefix(beamLimit)
                )
                var expansions: [CandidateDraft] = []
                for candidate in beam {
                    expansions.append(
                        contentsOf: expand(
                            candidate.draft,
                            generation: generation
                        )
                    )
                }
                expansions.sort {
                    $0.family == $1.family
                        ? $0.expression < $1.expression
                        : $0.family < $1.family
                }
                for draft in expansions
                    where evaluated.count < configuration.maximumCandidates {
                    if attempted.insert(draft.expression).inserted {
                        evaluated.append(
                            evaluate(
                                draft,
                                dataset: dataset,
                                attempt: evaluated.count,
                                configuration: configuration
                            )
                        )
                    }
                }
            }
        }
        let stabilized = applyNeighborStability(evaluated)
        for candidate in stabilized {
            try store.appendFactorTrial(candidate.trial)
        }
        let summaries = buildSummaries(
            definitions: existingDefinitions,
            candidates: stabilized
        )
        return FactorSearchResult(
            status: "Completed tiny deterministic beam search: \(stabilized.count) trials retained.",
            evaluatedCount: stabilized.count,
            candidateCount: stabilized.filter {
                $0.trial.result == .candidate
            }.count,
            rejectedCount: stabilized.filter {
                $0.trial.result == .rejected
            }.count,
            quarantinedCount: stabilized.filter {
                $0.trial.result == .quarantined
            }.count,
            trials: stabilized.map(\.trial),
            summaries: summaries
        )
    }

    func initialSummaries(
        definitions: [FactorDefinition],
        trials: [FactorTrial]
    ) -> [FactorResearchSummary] {
        buildSummaries(
            definitions: definitions,
            candidates: trials.map {
                CandidateEvaluation(
                    draft: CandidateDraft(
                        family: $0.factorFamily,
                        type: FactorTaskType(
                            rawValue: $0.parameters["factor_type"] ?? ""
                        ) ?? .alpha,
                        target: "",
                        horizon: $0.parameters["horizon"] ?? "1d",
                        expression: $0.expression,
                        generation: $0.generation,
                        normalization: $0.parameters["normalization"] ?? ""
                    ),
                    trial: $0,
                    evidence: evidence($0),
                    rawScore: $0.metrics["marginal_contribution"] ?? 0
                )
            }
        )
    }

    private func evaluate(
        _ draft: CandidateDraft,
        dataset: NormalizedResearchDataset,
        attempt: Int,
        configuration: FactorSearchConfiguration
    ) -> CandidateEvaluation {
        var parsed: ParsedFactorExpression?
        var output: FactorEvaluation?
        var rejection: String?
        var result = FactorTrialResult.rejected
        do {
            let expression = try dsl.parse(
                draft.expression,
                maximumDepth: configuration.maximumDepth,
                maximumOperators: configuration.maximumOperators
            )
            parsed = expression
            let maximumHistory = Dictionary(
                grouping: dataset.observations,
                by: \.symbol
            ).values.map(\.count).max() ?? 0
            if expression.minimumHistory > maximumHistory {
                rejection =
                    "Minimum history \(expression.minimumHistory) exceeds available history \(maximumHistory)."
            } else {
                output = try dsl.evaluate(expression, dataset: dataset)
            }
        } catch {
            rejection = error.localizedDescription
            if error.localizedDescription.localizedCaseInsensitiveContains(
                "future"
            ) || error.localizedDescription.localizedCaseInsensitiveContains(
                "temporal safety"
            ) {
                result = .quarantined
            }
        }
        let values = output.map {
            metrics(
                draft,
                parsed: parsed,
                evaluation: $0,
                dataset: dataset,
                attempt: attempt
            )
        } ?? emptyMetrics(
            complexity: parsed?.operatorCount ?? 0,
            attempt: attempt
        )
        if output != nil,
           (values["coverage"] ?? 0) >= 0.35,
           (values["task_metric"] ?? 0) >= 0.15,
           (values["marginal_contribution"] ?? 0) > 0 {
            result = .candidate
        } else if result != .quarantined {
            result = .rejected
            rejection = rejection ??
                "Candidate failed data quality, task evidence, or marginal-contribution gates."
        }
        let identifier = stableHash(
            "\(draft.family)|\(draft.expression)|\(draft.generation)|\(attempt)"
        )
        let trial = FactorTrial(
            schemaVersion: 1,
            trialId: "trial-\(identifier)",
            factorFamily: draft.family,
            expression: draft.expression,
            parameters: [
                "horizon": draft.horizon,
                "factor_type": draft.type.rawValue,
                "normalization": draft.normalization
            ],
            datasetVersion: dataset.datasetVersion,
            universeVersion: dataset.universeVersion,
            searchAlgorithm: searchAlgorithm,
            generation: draft.generation,
            oosWindows: Int(values["oos_windows"] ?? 0),
            metrics: values,
            result: result,
            rejectionReason: result == .candidate ? nil : rejection,
            createdAt: dataset.createdAt.addingTimeInterval(
                Double(attempt) / 1000
            )
        )
        return CandidateEvaluation(
            draft: draft,
            trial: trial,
            evidence: evidence(trial),
            rawScore: values["marginal_contribution"] ?? 0
        )
    }

    private func metrics(
        _ draft: CandidateDraft,
        parsed: ParsedFactorExpression?,
        evaluation: FactorEvaluation,
        dataset: NormalizedResearchDataset,
        attempt: Int
    ) -> [String: Double] {
        let pairs = paired(
            evaluation.values,
            target: target(for: draft.type, dataset: dataset)
        )
        let basicTaskMetric = taskMetric(draft.type, pairs: pairs)
        let purgedOos = purgedWalkForward(
            draft.type,
            pairs: pairs
        )
        let taskMetric = purgedOos.windows > 0
            ? purgedOos.score
            : 0
        let stability = evidenceStability(pairs)
        let turnover = turnover(
            evaluation.values,
            dataset: dataset
        )
        let cost = turnover * 0.002
        let averageVolume = dataset.observations
            .map(\.volume).reduce(0, +) /
            Double(max(1, dataset.observations.count))
        let capacity = min(
            max(log10(max(10, averageVolume)) / 8, 0),
            1
        )
        let complexity = parsed?.operatorCount ?? 0
        let multipleTesting =
            log(Double(2 + attempt)) * 0.006 +
            Double(complexity) * 0.004
        let marginal = taskMetric * evaluation.coverage * stability -
            cost -
            max(0, taskMetric - 0.80) * 0.20 -
            multipleTesting
        return [
            "coverage": evaluation.coverage,
            "missing_rate": 1 - evaluation.coverage,
            "task_metric": taskMetric,
            "basic_task_metric": basicTaskMetric,
            "purged_oos_score": purgedOos.score,
            "stability": stability,
            "turnover": turnover,
            "cost_proxy": cost,
            "capacity_proxy": capacity,
            "existing_factor_correlation": basicTaskMetric,
            "neighboring_horizon_stability": 0,
            "marginal_contribution": marginal,
            "oos_windows": Double(purgedOos.windows),
            "multiple_testing_penalty": multipleTesting,
            "complexity": Double(complexity)
        ]
    }

    private func emptyMetrics(
        complexity: Int,
        attempt: Int
    ) -> [String: Double] {
        [
            "coverage": 0,
            "missing_rate": 1,
            "task_metric": 0,
            "basic_task_metric": 0,
            "purged_oos_score": 0,
            "stability": 0,
            "turnover": 0,
            "cost_proxy": 0,
            "capacity_proxy": 0,
            "existing_factor_correlation": 0,
            "neighboring_horizon_stability": 0,
            "marginal_contribution": -0.01,
            "oos_windows": 0,
            "multiple_testing_penalty":
                log(Double(2 + attempt)) * 0.006,
            "complexity": Double(complexity)
        ]
    }

    private func applyNeighborStability(
        _ values: [CandidateEvaluation]
    ) -> [CandidateEvaluation] {
        values.map { item in
            let days = (try? FactorHorizons.days(
                item.draft.horizon
            )) ?? 1
            let neighbor = values.filter {
                $0.draft.family == item.draft.family &&
                    $0.draft.expression != item.draft.expression
            }.sorted {
                let leftDays = (try? FactorHorizons.days(
                    $0.draft.horizon
                )) ?? 1
                let rightDays = (try? FactorHorizons.days(
                    $1.draft.horizon
                )) ?? 1
                let leftDistance = abs(leftDays - days)
                let rightDistance = abs(rightDays - days)
                return leftDistance == rightDistance
                    ? $0.draft.expression < $1.draft.expression
                    : leftDistance < rightDistance
            }.first
            let score = neighbor.map {
                min(max(1 - abs($0.rawScore - item.rawScore), 0), 1)
            } ?? 0.35
            var updatedMetrics = item.trial.metrics
            updatedMetrics["neighboring_horizon_stability"] = score
            updatedMetrics["marginal_contribution"] =
                (updatedMetrics["marginal_contribution"] ?? 0) +
                score * 0.05
            let isolated = item.trial.result == .candidate && score < 0.25
            let updatedTrial = FactorTrial(
                schemaVersion: item.trial.schemaVersion,
                trialId: item.trial.trialId,
                factorFamily: item.trial.factorFamily,
                expression: item.trial.expression,
                parameters: item.trial.parameters,
                datasetVersion: item.trial.datasetVersion,
                universeVersion: item.trial.universeVersion,
                searchAlgorithm: item.trial.searchAlgorithm,
                generation: item.trial.generation,
                oosWindows: item.trial.oosWindows,
                metrics: updatedMetrics,
                result: isolated ? .rejected : item.trial.result,
                rejectionReason: isolated
                    ? "Candidate was isolated across neighboring horizons."
                    : item.trial.rejectionReason,
                createdAt: item.trial.createdAt
            )
            return CandidateEvaluation(
                draft: item.draft,
                trial: updatedTrial,
                evidence: evidence(updatedTrial),
                rawScore:
                    updatedMetrics["marginal_contribution"] ?? item.rawScore
            )
        }.sorted {
            if $0.trial.generation != $1.trial.generation {
                return $0.trial.generation < $1.trial.generation
            }
            if $0.trial.factorFamily != $1.trial.factorFamily {
                return $0.trial.factorFamily < $1.trial.factorFamily
            }
            return $0.trial.expression < $1.trial.expression
        }
    }

    private func buildSummaries(
        definitions: [FactorDefinition],
        candidates: [CandidateEvaluation]
    ) -> [FactorResearchSummary] {
        definitions.sorted { $0.factorId < $1.factorId }.map { definition in
            let matching = candidates.filter {
                $0.draft.family == definition.factorId
            }
            let best = matching.max {
                $0.rawScore < $1.rawScore
            }
            let currentEvidence = best?.evidence ?? FactorEvidence(
                coverage: 0,
                missingRate: 1,
                taskMetric: 0,
                taskMetricName: metricName(definition.factorType),
                stability: 0,
                turnover: 0,
                costProxy: 0,
                capacityProxy: 0,
                existingFactorCorrelation: 0,
                neighboringHorizonStability: 0,
                marginalContribution: 0,
                oosWindows: 0,
                multipleTestingPenalty: 0,
                regimeEvidence: "Fixture evidence pending"
            )
            let strategyState = definition.strategyStates[
                "cross-sectional-multifactor"
            ] ?? definition.state
            return FactorResearchSummary(
                definition: definition,
                globalState: definition.state,
                strategyState: strategyState,
                trialCount: matching.count,
                evidence: currentEvidence,
                stateReason: best?.trial.rejectionReason ??
                    "Persisted fixture definition; no promotion is implied."
            )
        }
    }

    private func evidence(_ trial: FactorTrial) -> FactorEvidence {
        let type = FactorTaskType(
            rawValue: trial.parameters["factor_type"] ?? ""
        ) ?? .alpha
        return FactorEvidence(
            coverage: trial.metrics["coverage"] ?? 0,
            missingRate: trial.metrics["missing_rate"] ?? 1,
            taskMetric: trial.metrics["task_metric"] ?? 0,
            taskMetricName: metricName(type),
            stability: trial.metrics["stability"] ?? 0,
            turnover: trial.metrics["turnover"] ?? 0,
            costProxy: trial.metrics["cost_proxy"] ?? 0,
            capacityProxy: trial.metrics["capacity_proxy"] ?? 0,
            existingFactorCorrelation:
                trial.metrics["existing_factor_correlation"] ?? 0,
            neighboringHorizonStability:
                trial.metrics["neighboring_horizon_stability"] ?? 0,
            marginalContribution:
                trial.metrics["marginal_contribution"] ?? 0,
            oosWindows: trial.oosWindows,
            multipleTestingPenalty:
                trial.metrics["multiple_testing_penalty"] ?? 0,
            regimeEvidence: "Deterministic fixture regime ensemble"
        )
    }

    private func metricName(_ type: FactorTaskType) -> String {
        switch type {
        case .alpha: return "Rank IC"
        case .risk: return "Volatility correlation"
        case .regime: return "Regime fit"
        case .liquidity: return "Capacity correlation"
        case .execution: return "Fill-quality correlation"
        }
    }

    private func target(
        for type: FactorTaskType,
        dataset: NormalizedResearchDataset
    ) -> [Double?] {
        var result = Array<Double?>(
            repeating: nil,
            count: dataset.observations.count
        )
        let groups = Dictionary(grouping: dataset.observations.indices) {
            dataset.observations[$0].symbol
        }
        for indices in groups.values {
            let ordered = indices.sorted {
                dataset.observations[$0].eventTime <
                    dataset.observations[$1].eventTime
            }
            guard ordered.count > 1 else { continue }
            for offset in 0..<(ordered.count - 1) {
                let index = ordered[offset]
                let next = dataset.observations[ordered[offset + 1]]
                switch type {
                case .alpha:
                    result[index] = next.returns
                case .risk:
                    result[index] = abs(next.returns)
                case .regime:
                    result[index] =
                        next.returns > next.marketReturn ? 1 : -1
                case .liquidity:
                    result[index] = log10(max(1, next.volume))
                case .execution:
                    result[index] =
                        next.volume / max(0.01, next.high - next.low)
                }
            }
        }
        return result
    }

    private func paired(
        _ factors: [Double?],
        target: [Double?]
    ) -> [(Double, Double)] {
        zip(factors, target).compactMap { first, second in
            guard let first, let second else { return nil }
            return (first, second)
        }
    }

    private func evidenceStability(
        _ pairs: [(Double, Double)]
    ) -> Double {
        guard pairs.count >= 2 else { return 0 }
        let midpoint = pairs.count / 2
        let first = pairs[..<midpoint].map {
            direction($0.0 * $0.1)
        }.reduce(0, +) / Double(midpoint)
        let secondValues = pairs[midpoint...]
        guard !secondValues.isEmpty else { return 0.5 }
        let second = secondValues.map {
            direction($0.0 * $0.1)
        }.reduce(0, +) / Double(secondValues.count)
        return min(max(1 - abs(first - second) / 2, 0), 1)
    }

    private func purgedWalkForward(
        _ type: FactorTaskType,
        pairs: [(Double, Double)]
    ) -> (windows: Int, score: Double) {
        guard pairs.count >= 4 else { return (0, 0) }
        let starts = Set([
            max(2, pairs.count / 2),
            max(3, pairs.count * 3 / 4)
        ]).filter { $0 < pairs.count - 1 }.sorted()
        var scores: [Double] = []
        for testStart in starts {
            let trainingCount = testStart - 1
            guard trainingCount >= 1 else { continue }
            let test = Array(pairs[testStart...])
            guard test.count >= 2 else { continue }
            scores.append(taskMetric(type, pairs: test))
        }
        guard !scores.isEmpty else { return (0, 0) }
        return (
            scores.count,
            scores.reduce(0, +) / Double(scores.count)
        )
    }

    private func taskMetric(
        _ type: FactorTaskType,
        pairs: [(Double, Double)]
    ) -> Double {
        guard pairs.count >= 2 else { return 0 }
        if type == .regime {
            let matches = pairs.filter {
                direction($0.0) == direction($0.1)
            }.count
            return Double(matches) / Double(pairs.count)
        }
        return abs(
            FactorDSLService.correlation(
                pairs.map(\.0),
                pairs.map(\.1)
            ) ?? 0
        )
    }

    private func direction(_ value: Double) -> Double {
        value > 0 ? 1 : value < 0 ? -1 : 0
    }

    private func turnover(
        _ values: [Double?],
        dataset: NormalizedResearchDataset
    ) -> Double {
        let groups = Dictionary(grouping: values.indices) {
            dataset.observations[$0].symbol
        }
        var changes: [Double] = []
        for indices in groups.values {
            let ordered = indices.sorted {
                dataset.observations[$0].eventTime <
                    dataset.observations[$1].eventTime
            }
            for pair in zip(ordered, ordered.dropFirst()) {
                if let first = values[pair.0],
                   let second = values[pair.1] {
                    changes.append(
                        abs(second - first) / (1 + abs(first))
                    )
                }
            }
        }
        guard !changes.isEmpty else { return 0 }
        return min(max(
            changes.reduce(0, +) / Double(changes.count),
            0
        ), 1)
    }

    private func seedDrafts() -> [CandidateDraft] {
        [
            draft("short-term-reversal", .alpha, "forward_cross_sectional_return", "3d", "delta(close,{w})"),
            draft("medium-term-momentum", .alpha, "forward_cross_sectional_return", "20d", "delta(close,{w})"),
            draft("volatility-adjusted-momentum", .alpha, "forward_cross_sectional_return", "20d", "safe_divide(delta(close,{w}),rolling_std(returns,{w}))"),
            draft("volume-shock", .liquidity, "forward_capacity", "3d", "zscore(delta(volume,{w}))"),
            draft("volatility-contraction", .risk, "forward_realized_volatility", "20d", "signed_power(rolling_std(returns,{w}),-1)"),
            draft("liquidity", .liquidity, "forward_capacity", "5d", "safe_divide(volume,rolling_mean(volume,{w}))"),
            draft("capital-flow-persistence", .liquidity, "forward_capacity", "5d", "rolling_mean(capital_flow,{w})"),
            draft("market-relative-strength", .regime, "trend_regime_probability", "20d", "rolling_corr(returns,market_return,{w})"),
            draft("sector-relative-strength", .alpha, "forward_cross_sectional_return", "20d", "rolling_corr(returns,sector_return,{w})")
        ]
    }

    private func draft(
        _ family: String,
        _ type: FactorTaskType,
        _ target: String,
        _ horizon: String,
        _ template: String
    ) -> CandidateDraft {
        let days = (try? FactorHorizons.days(horizon)) ?? 1
        return CandidateDraft(
            family: family,
            type: type,
            target: target,
            horizon: horizon,
            expression: template.replacingOccurrences(
                of: "{w}",
                with: String(days)
            ),
            generation: 0,
            normalization: "seed"
        )
    }

    private func expand(
        _ draft: CandidateDraft,
        generation: Int
    ) -> [CandidateDraft] {
        guard let index = FactorHorizons.daily.firstIndex(
            of: draft.horizon
        ) else { return [] }
        let neighborIndices = Set([
            max(0, index - 1),
            min(FactorHorizons.daily.count - 1, index + 1)
        ])
        let oldWindow = String((try? FactorHorizons.days(
            draft.horizon
        )) ?? 1)
        var values = neighborIndices.sorted().map { neighbor in
            let horizon = FactorHorizons.daily[neighbor]
            let window = String((try? FactorHorizons.days(horizon)) ?? 1)
            return CandidateDraft(
                family: draft.family,
                type: draft.type,
                target: draft.target,
                horizon: horizon,
                expression: draft.expression.replacingOccurrences(
                    of: ",\(oldWindow))",
                    with: ",\(window))"
                ),
                generation: generation,
                normalization: "horizon"
            )
        }
        for (name, expression) in [
            ("winsorize", "winsorize(\(draft.expression))"),
            ("zscore", "zscore(\(draft.expression))"),
            (
                "sector_neutralize",
                "sector_neutralize(\(draft.expression))"
            ),
            (
                "volatility_scale",
                "safe_divide(\(draft.expression),rolling_std(returns,\(oldWindow)))"
            )
        ] {
            values.append(
                CandidateDraft(
                    family: draft.family,
                    type: draft.type,
                    target: draft.target,
                    horizon: draft.horizon,
                    expression: expression,
                    generation: generation,
                    normalization: name
                )
            )
        }
        return values
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private struct CandidateDraft {
    let family: String
    let type: FactorTaskType
    let target: String
    let horizon: String
    let expression: String
    let generation: Int
    let normalization: String
}

private struct CandidateEvaluation {
    let draft: CandidateDraft
    let trial: FactorTrial
    let evidence: FactorEvidence
    let rawScore: Double
}
