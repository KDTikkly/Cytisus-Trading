namespace CytisusTrading.Windows;

public sealed record FactorReviewResult(
    IReadOnlyList<FactorItem> Factors,
    IReadOnlyList<string> ChangedFactorIds);

public interface IFactorGovernanceService
{
    FactorReviewResult RunReview(
        IReadOnlyList<FactorItem> factors,
        int reviewCount,
        double maxFactorWeight);
}

public sealed class FixtureFactorGovernanceService : IFactorGovernanceService
{
    public FactorReviewResult RunReview(
        IReadOnlyList<FactorItem> factors,
        int reviewCount,
        double maxFactorWeight)
    {
        var reviewed = factors.Select(factor => factor.Clone()).ToList();
        var changed = new List<string>();

        foreach (var factor in reviewed)
        {
            switch (factor.FactorId)
            {
                case "volatility-term-structure":
                    factor.EvidenceWindows += 1;
                    if (factor.EvidenceWindows >= 6 && reviewCount >= 2)
                    {
                        factor.State = FactorState.Active;
                        factor.Weight = Math.Min(0.05, maxFactorWeight);
                        factor.Reason = "Passed twice; enable with a 5% cap";
                    }
                    else
                    {
                        factor.Reason = "First pass complete; awaiting confirmation";
                    }
                    changed.Add(factor.FactorId);
                    break;

                case "volume-impact":
                    factor.Ic -= 0.003;
                    if (reviewCount >= 2)
                    {
                        factor.State = FactorState.Retired;
                        factor.Weight = 0;
                        factor.Reason = "Failed three reviews; 126-day cooldown";
                    }
                    else
                    {
                        factor.Reason = "Second failure; probation continues";
                    }
                    changed.Add(factor.FactorId);
                    break;

                case "short-term-reversal":
                    factor.EvidenceWindows += 1;
                    factor.State = FactorState.Shadow;
                    factor.Reason = "Candidate data gate passed; moved to shadow review";
                    changed.Add(factor.FactorId);
                    break;
            }
        }

        return new FactorReviewResult(reviewed, changed);
    }
}
