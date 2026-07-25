import Foundation

final class FactorLifecycleService {
    func evaluate(
        currentState: FactorState,
        evidence: FactorLifecycleEvidence
    ) -> FactorLifecycleDecision {
        if evidence.dataContamination || evidence.lookAheadBias ||
            evidence.trainTestLeakage ||
            evidence.unreproducibleResult ||
            evidence.definitionError || !evidence.trialRecordPresent {
            return decision(
                .quarantined,
                global: true,
                blocks: true,
                multiplier: 0,
                reason: "Immediate global quarantine: temporal, definition, data, or trial-record integrity failed."
            )
        }
        if currentState == .quarantined {
            return decision(
                .quarantined,
                global: true,
                blocks: true,
                multiplier: 0,
                reason: "Quarantine is global and requires a new reviewed definition."
            )
        }
        if currentState == .retired {
            if evidence.renewedEvidence {
                return decision(
                    .shadow,
                    global: false,
                    blocks: true,
                    multiplier: 0,
                    reason: "Renewed evidence permits Shadow observation, never a direct jump to Active."
                )
            }
            return decision(
                .retired,
                global: false,
                blocks: true,
                multiplier: 0,
                reason: "Retired factor remains blocked without renewed evidence."
            )
        }
        if evidence.changePointProbability >= 0.80 &&
            evidence.counterfactualImprovement >= 0.02 {
            return decision(
                .retired,
                global: false,
                blocks: true,
                multiplier: 0,
                reason: "Retired after change-point and counterfactual replacement evidence."
            )
        }
        if evidence.repeatedOosFailures >= 2 {
            return decision(
                .probation,
                global: false,
                blocks: true,
                multiplier: 0.15,
                reason: "Repeated purged OOS deterioration triggered Probation."
            )
        }
        if evidence.regimeSpecificFailure {
            return decision(
                currentState,
                global: false,
                blocks: true,
                multiplier: min(0.50, riskMultiplier(currentState)),
                reason: "Regime Conditional evidence recorded; global retirement was not triggered."
            )
        }
        if evidence.shortTermScore < 0.35 &&
            evidence.longTermScore >= 0.60 {
            return decision(
                .reduced,
                global: false,
                blocks: true,
                multiplier: 0.50,
                reason: "Short-term deterioration with stable long-term evidence triggered automatic risk contraction."
            )
        }
        if currentState == .reduced || currentState == .probation {
            if evidence.renewedEvidence &&
                evidence.shortTermScore >= 0.60 &&
                evidence.longTermScore >= 0.65 {
                return decision(
                    .shadow,
                    global: false,
                    blocks: true,
                    multiplier: 0.25,
                    reason: "Renewed evidence permits Shadow review; risk expansion still requires promotion evidence."
                )
            }
            return decision(
                currentState,
                global: false,
                blocks: true,
                multiplier: riskMultiplier(currentState),
                reason: "Risk expansion remains blocked pending renewed evidence."
            )
        }
        return decision(
            currentState,
            global: false,
            blocks: currentState != .active,
            multiplier: riskMultiplier(currentState),
            reason: "Evidence is stable; no lifecycle contraction is required."
        )
    }

    private func decision(
        _ state: FactorState,
        global: Bool,
        blocks: Bool,
        multiplier: Double,
        reason: String
    ) -> FactorLifecycleDecision {
        FactorLifecycleDecision(
            state: state,
            global: global,
            blocksRiskExpansion: blocks,
            riskMultiplier: multiplier,
            reason: reason
        )
    }

    private func riskMultiplier(_ state: FactorState) -> Double {
        switch state {
        case .active: return 1
        case .reduced: return 0.50
        case .probation: return 0.15
        case .candidate, .shadow, .retired, .quarantined: return 0
        }
    }
}
