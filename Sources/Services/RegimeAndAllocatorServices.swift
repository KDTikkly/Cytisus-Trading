import Foundation

final class RegimeEngine {
    private let names = ["Trend", "Range", "HighVolatility", "Crisis"]

    func evaluate(_ input: RegimeInput, asOf: Date) -> RegimeSnapshot {
        let trend = clamp(input.trendStrength)
        let range = clamp(input.rangeScore)
        let volatility = clamp(input.realizedVolatility)
        let crossAssetRisk = clamp(input.crossAssetRisk)
        let ruleScores = [
            "Trend": 1.20 * trend + 0.40 * (1 - volatility),
            "Range": 1.20 * range + 0.30 * (1 - trend),
            "HighVolatility":
                1.20 * volatility + 0.50 * crossAssetRisk,
            "Crisis":
                1.50 * crossAssetRisk + 1.00 * volatility -
                0.40 * trend
        ]
        let distanceScores = [
            "Trend": 1 - meanDistance(
                [trend, volatility, crossAssetRisk],
                [0.80, 0.25, 0.20]
            ),
            "Range": 1 - meanDistance(
                [range, trend, volatility],
                [0.80, 0.25, 0.25]
            ),
            "HighVolatility": 1 - meanDistance(
                [volatility, crossAssetRisk, trend],
                [0.80, 0.55, 0.40]
            ),
            "Crisis": 1 - meanDistance(
                [crossAssetRisk, volatility, trend],
                [0.90, 0.90, 0.20]
            )
        ]
        let raw = names.map { name in
            (ruleScores[name] ?? 0) +
                0.70 * (distanceScores[name] ?? 0) +
                0.50 * clamp(
                    input.strategyReportedFit[name] ?? 0
                )
        }
        let maximum = raw.max() ?? 0
        let exponentials = raw.map { exp($0 - maximum) }
        let total = exponentials.reduce(0, +)
        let probabilities = Dictionary(
            uniqueKeysWithValues: names.indices.map {
                (names[$0], exponentials[$0] / total)
            }
        )
        let entropy = -probabilities.values.map {
            $0 <= 0 ? 0 : $0 * log($0)
        }.reduce(0, +) / log(Double(names.count))
        let uncertainty = clamp(entropy)
        let crisis = probabilities["Crisis"] ?? 0
        let riskMultiplier = clamp(
            1 - 0.55 * uncertainty - 0.45 * crisis,
            minimum: 0.20,
            maximum: 1
        )
        return RegimeSnapshot(
            schemaVersion: 1,
            asOf: asOf,
            probabilities: probabilities,
            uncertainty: uncertainty,
            riskMultiplier: riskMultiplier,
            explanation: [
                "rule_trend": ruleScores["Trend"] ?? 0,
                "rule_range": ruleScores["Range"] ?? 0,
                "rule_high_volatility":
                    ruleScores["HighVolatility"] ?? 0,
                "rule_crisis": ruleScores["Crisis"] ?? 0,
                "feature_distance_trend":
                    distanceScores["Trend"] ?? 0,
                "cross_asset_risk": crossAssetRisk,
                "strategy_reported_fit":
                    input.strategyReportedFit.values.reduce(0, +) /
                    Double(max(1, input.strategyReportedFit.count))
            ]
        )
    }

    private func meanDistance(
        _ values: [Double],
        _ prototype: [Double]
    ) -> Double {
        zip(values, prototype).map {
            abs($0.0 - $0.1)
        }.reduce(0, +) / Double(values.count)
    }

    private func clamp(
        _ value: Double,
        minimum: Double = 0,
        maximum: Double = 1
    ) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

final class DynamicCapitalAllocator {
    static let maximumAlphaTilt = 0.15

    func allocate(
        totalCapital: Double,
        baseRiskFraction: Double,
        regime: RegimeSnapshot,
        strategies: [StrategyAllocationInput]
    ) -> CapitalAllocationResult {
        let eligible = strategies.filter {
            $0.health != .unhealthy
        }.sorted { $0.strategyId < $1.strategyId }
        let budget = max(
            0,
            totalCapital * clamp(baseRiskFraction) *
                regime.riskMultiplier
        )
        guard !eligible.isEmpty else {
            return CapitalAllocationResult(
                totalRiskBudget: budget,
                regime: regime,
                allocations: []
            )
        }
        let inverseVolatility = eligible.map {
            1 / max(0.01, $0.volatility)
        }
        let inverseTotal = inverseVolatility.reduce(0, +)
        var provisional: [(StrategyAllocationInput, Double, [String: Double])] =
            []
        for (index, strategy) in eligible.enumerated() {
            let base = inverseVolatility[index] / inverseTotal
            var expectedAlpha =
                0.32 * clamp(strategy.longTermOos) +
                0.18 * clamp(strategy.recentLive) +
                0.10 * clamp(strategy.recentPaper) +
                0.10 * clamp(strategy.signalStrength) +
                0.10 * clamp(strategy.regimeFit) +
                0.06 * clamp(strategy.confidenceCalibration) +
                0.14 * clamp(strategy.dataQuality) -
                0.20 * clamp(strategy.modelUncertainty)
            if strategy.isNew {
                expectedAlpha = 0.50 * expectedAlpha + 0.25
            }
            let alphaTilt = clamp(
                (expectedAlpha - 0.50) * 0.30,
                minimum: -Self.maximumAlphaTilt,
                maximum: Self.maximumAlphaTilt
            )
            let correlationPenalty =
                1 - 0.45 * clamp(strategy.averageCorrelation)
            let drawdownPenalty =
                1 - 0.70 * clamp(strategy.drawdown)
            let capacityPenalty =
                0.35 + 0.65 * clamp(strategy.capacity)
            let liquidityPenalty =
                0.35 + 0.65 * clamp(strategy.liquidity)
            let penalized = max(
                0,
                base *
                    (1 + alphaTilt) *
                    correlationPenalty *
                    drawdownPenalty *
                    capacityPenalty *
                    liquidityPenalty
            )
            provisional.append((
                strategy,
                penalized,
                [
                    "base_weight": base,
                    "alpha_tilt": alphaTilt,
                    "expected_alpha_tilt": alphaTilt,
                    "correlation_penalty": correlationPenalty,
                    "drawdown_penalty": drawdownPenalty,
                    "capacity_penalty": capacityPenalty,
                    "liquidity_penalty": liquidityPenalty,
                    "new_strategy_prior": strategy.isNew ? 0.50 : 1
                ]
            ))
        }
        let rawTotal = provisional.map(\.1).reduce(0, +)
        let smoothed = provisional.map { item in
            let target = rawTotal > 0
                ? item.1 / rawTotal
                : 1 / Double(provisional.count)
            let weight =
                0.70 * max(0, item.0.currentWeight) +
                0.30 * target
            return (item.0, weight, target, item.2)
        }
        let total = smoothed.map(\.1).reduce(0, +)
        let allocations = smoothed.map { item in
            let strategy = item.0
            let value = item.1
            let target = item.2
            var explanation = item.3
            let weight = total > 0
                ? value / total
                : 1 / Double(smoothed.count)
            explanation["turnover_target"] = target
            explanation["turnover_smoothed_weight"] = weight
            explanation["regime_uncertainty"] = regime.uncertainty
            explanation["regime_risk_multiplier"] =
                regime.riskMultiplier
            return StrategyCapitalAllocation(
                schemaVersion: 1,
                strategyId: strategy.strategyId,
                finalWeight: weight,
                capitalBudget: budget * weight,
                explanation: explanation
            )
        }.sorted { $0.strategyId < $1.strategyId }
        return CapitalAllocationResult(
            totalRiskBudget: budget,
            regime: regime,
            allocations: allocations
        )
    }

    private func clamp(
        _ value: Double,
        minimum: Double = 0,
        maximum: Double = 1
    ) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
