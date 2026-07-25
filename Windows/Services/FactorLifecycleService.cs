namespace CytisusTrading.Windows;

public interface IFactorLifecycleService
{
    FactorLifecycleDecision Evaluate(
        FactorState currentState,
        FactorLifecycleEvidence evidence);
}

public sealed class FactorLifecycleService : IFactorLifecycleService
{
    public FactorLifecycleDecision Evaluate(
        FactorState currentState,
        FactorLifecycleEvidence evidence)
    {
        if (evidence.DataContamination ||
            evidence.LookAheadBias ||
            evidence.TrainTestLeakage ||
            evidence.UnreproducibleResult ||
            evidence.DefinitionError ||
            !evidence.TrialRecordPresent)
        {
            return new FactorLifecycleDecision(
                FactorState.Quarantined,
                true,
                true,
                0,
                evidence.DataContamination
                    ? "Global quarantine: data contamination."
                    : evidence.LookAheadBias
                        ? "Global quarantine: look-ahead bias."
                        : evidence.TrainTestLeakage
                            ? "Global quarantine: train-test leakage."
                            : evidence.UnreproducibleResult
                                ? "Global quarantine: unreproducible result."
                                : evidence.DefinitionError
                                    ? "Global quarantine: definition error."
                                    : "Global quarantine: missing trial record.");
        }

        if (currentState == FactorState.Quarantined)
        {
            return new FactorLifecycleDecision(
                FactorState.Quarantined,
                true,
                true,
                0,
                "Quarantine is global and requires a new reviewed definition.");
        }

        if (currentState == FactorState.Retired)
        {
            return evidence.RenewedEvidence
                ? new FactorLifecycleDecision(
                    FactorState.Shadow,
                    false,
                    true,
                    0,
                    "Renewed evidence permits Shadow observation, never a direct jump to Active.")
                : new FactorLifecycleDecision(
                    FactorState.Retired,
                    false,
                    true,
                    0,
                    "Retired factor remains blocked without renewed evidence.");
        }

        if (evidence.ChangePointProbability >= 0.80 &&
            evidence.CounterfactualImprovement >= 0.02)
        {
            return new FactorLifecycleDecision(
                FactorState.Retired,
                false,
                true,
                0,
                "Retired after a high change-point probability and sustained counterfactual improvement after removal.");
        }

        if (evidence.RepeatedOosFailures >= 2)
        {
            return new FactorLifecycleDecision(
                FactorState.Probation,
                false,
                true,
                0.15,
                "Repeated purged OOS deterioration triggered Probation.");
        }

        if (evidence.RegimeSpecificFailure)
        {
            return new FactorLifecycleDecision(
                currentState,
                false,
                true,
                Math.Min(0.50, RiskMultiplier(currentState)),
                "Regime Conditional evidence recorded; global retirement was not triggered.");
        }

        if (evidence.ShortTermScore < 0.35 &&
            evidence.LongTermScore >= 0.60)
        {
            return new FactorLifecycleDecision(
                FactorState.Reduced,
                false,
                true,
                0.50,
                "Short-term deterioration with stable long-term evidence triggered automatic risk contraction.");
        }

        if (currentState is FactorState.Reduced or FactorState.Probation)
        {
            if (evidence.RenewedEvidence &&
                evidence.ShortTermScore >= 0.60 &&
                evidence.LongTermScore >= 0.65)
            {
                return new FactorLifecycleDecision(
                    FactorState.Shadow,
                    false,
                    true,
                    0.25,
                    "Renewed evidence permits Shadow review; risk expansion still requires promotion evidence.");
            }
            return new FactorLifecycleDecision(
                currentState,
                false,
                true,
                RiskMultiplier(currentState),
                "Risk expansion remains blocked pending renewed evidence.");
        }

        return new FactorLifecycleDecision(
            currentState,
            false,
            currentState != FactorState.Active,
            RiskMultiplier(currentState),
            "Evidence is stable; no lifecycle contraction is required.");
    }

    private static double RiskMultiplier(FactorState state)
    {
        return state switch
        {
            FactorState.Active => 1,
            FactorState.Shadow => 0,
            FactorState.Candidate => 0,
            FactorState.Reduced => 0.50,
            FactorState.Probation => 0.15,
            FactorState.Retired => 0,
            FactorState.Quarantined => 0,
            _ => 0
        };
    }
}
