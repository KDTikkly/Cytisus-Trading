import Foundation
import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case factors = "Factor Lifecycle"
    case lab = "Strategy Lab"
    case privacy = "Privacy and Sanitization"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "sparkles.rectangle.stack"
        case .factors: return "point.3.connected.trianglepath.dotted"
        case .lab: return "slider.horizontal.3"
        case .privacy: return "lock.shield"
        }
    }
}

enum FactorState: String, CaseIterable {
    case candidate = "Candidate"
    case shadow = "Shadow"
    case active = "Active"
    case probation = "Probation"
    case retired = "Retired"
    case quarantined = "Quarantined"

    var tint: Color {
        switch self {
        case .candidate: return .cyan
        case .shadow: return .indigo
        case .active: return .green
        case .probation: return .orange
        case .retired: return .secondary
        case .quarantined: return .red
        }
    }
}

struct FactorItem: Identifiable {
    let id: UUID
    let name: String
    let category: String
    var state: FactorState
    var ic: Double
    var ir: Double
    var coverage: Double
    var weight: Double
    var evidenceWindows: Int
    var reason: String

    init(
        id: UUID = UUID(),
        name: String,
        category: String,
        state: FactorState,
        ic: Double,
        ir: Double,
        coverage: Double,
        weight: Double,
        evidenceWindows: Int,
        reason: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.state = state
        self.ic = ic
        self.ir = ir
        self.coverage = coverage
        self.weight = weight
        self.evidenceWindows = evidenceWindows
        self.reason = reason
    }
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var selection: StudioSection = .overview
    @Published var reviewCount = 0
    @Published var lastReview: Date?
    @Published var riskBudget = 0.50
    @Published var coverageGate = 0.80
    @Published var maxFactorWeight = 0.35
    @Published var factors: [FactorItem] = StudioModel.sampleFactors

    static let sampleFactors: [FactorItem] = [
        FactorItem(
            name: "Medium-Term Momentum", category: "Directional", state: .active,
            ic: 0.041, ir: 0.61, coverage: 0.96, weight: 0.22,
            evidenceWindows: 8, reason: "Cleared every out-of-sample gate"
        ),
        FactorItem(
            name: "Low-Volatility Quality", category: "Defensive", state: .active,
            ic: 0.036, ir: 0.54, coverage: 0.92, weight: 0.18,
            evidenceWindows: 7, reason: "Stable contribution after costs"
        ),
        FactorItem(
            name: "Volatility Term Structure", category: "Derivatives", state: .shadow,
            ic: 0.029, ir: 0.41, coverage: 0.84, weight: 0.00,
            evidenceWindows: 5, reason: "Waiting for the sixth out-of-sample window"
        ),
        FactorItem(
            name: "Volume Impact", category: "Market Microstructure", state: .probation,
            ic: 0.014, ir: 0.21, coverage: 0.76, weight: 0.08,
            evidenceWindows: 9, reason: "One review below the IC threshold"
        ),
        FactorItem(
            name: "Short-Term Reversal", category: "Directional", state: .candidate,
            ic: 0.024, ir: 0.35, coverage: 0.82, weight: 0.00,
            evidenceWindows: 2, reason: "Continue collecting frozen OOS evidence"
        ),
        FactorItem(
            name: "Legacy Sentiment Proxy", category: "Alternative Data", state: .retired,
            ic: -0.008, ir: -0.12, coverage: 0.67, weight: 0.00,
            evidenceWindows: 11, reason: "Failed three reviews and entered cooldown"
        )
    ]

    var activeFactors: Int { factors.filter { $0.state == .active }.count }
    var shadowFactors: Int { factors.filter { $0.state == .shadow || $0.state == .candidate }.count }
    var weightedCoverage: Double {
        let active = factors.filter { $0.state == .active || $0.state == .probation }
        let totalWeight = active.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        return active.reduce(0) { $0 + $1.coverage * $1.weight } / totalWeight
    }

    func runReview() {
        reviewCount += 1
        lastReview = Date()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            for index in factors.indices {
                switch factors[index].name {
                case "Volatility Term Structure":
                    factors[index].evidenceWindows += 1
                    if factors[index].evidenceWindows >= 6 && reviewCount >= 2 {
                        factors[index].state = .active
                        factors[index].weight = min(0.05, maxFactorWeight)
                        factors[index].reason = "Passed twice; enable with a 5% cap"
                    } else {
                        factors[index].reason = "First pass complete; awaiting confirmation"
                    }
                case "Volume Impact":
                    factors[index].ic -= 0.003
                    if reviewCount >= 2 {
                        factors[index].state = .retired
                        factors[index].weight = 0
                        factors[index].reason = "Failed three reviews; 126-day cooldown"
                    } else {
                        factors[index].reason = "Second failure; probation continues"
                    }
                case "Short-Term Reversal":
                    factors[index].evidenceWindows += 1
                    factors[index].state = .shadow
                    factors[index].reason = "Candidate data gate passed; moved to shadow review"
                default:
                    break
                }
            }
        }
    }

    func resetDemo() {
        withAnimation(.easeInOut(duration: 0.35)) {
            factors = Self.sampleFactors
            reviewCount = 0
            lastReview = nil
        }
    }
}

