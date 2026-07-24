import Foundation

struct FactorReviewResult {
    let factors: [FactorItem]
    let changedFactorIDs: [String]
}

protocol FactorGovernanceServicing {
    func runReview(
        factors: [FactorItem],
        reviewCount: Int,
        maxFactorWeight: Double
    ) -> FactorReviewResult
}

struct FixtureFactorGovernanceService: FactorGovernanceServicing {
    func runReview(
        factors: [FactorItem],
        reviewCount: Int,
        maxFactorWeight: Double
    ) -> FactorReviewResult {
        var reviewed = factors
        var changed: [String] = []

        for index in reviewed.indices {
            switch reviewed[index].factorID {
            case "volatility-term-structure":
                reviewed[index].evidenceWindows += 1
                if reviewed[index].evidenceWindows >= 6 && reviewCount >= 2 {
                    reviewed[index].state = .active
                    reviewed[index].weight = min(0.05, maxFactorWeight)
                    reviewed[index].reason = "Passed twice; enable with a 5% cap"
                } else {
                    reviewed[index].reason = "First pass complete; awaiting confirmation"
                }
                changed.append(reviewed[index].factorID)

            case "volume-impact":
                reviewed[index].ic -= 0.003
                if reviewCount >= 2 {
                    reviewed[index].state = .retired
                    reviewed[index].weight = 0
                    reviewed[index].reason = "Failed three reviews; 126-day cooldown"
                } else {
                    reviewed[index].reason = "Second failure; probation continues"
                }
                changed.append(reviewed[index].factorID)

            case "short-term-reversal":
                reviewed[index].evidenceWindows += 1
                reviewed[index].state = .shadow
                reviewed[index].reason = "Candidate data gate passed; moved to shadow review"
                changed.append(reviewed[index].factorID)

            default:
                break
            }
        }

        return FactorReviewResult(factors: reviewed, changedFactorIDs: changed)
    }
}
