import Foundation
import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case factors = "因子生命周期"
    case lab = "策略实验室"
    case privacy = "隐私与脱敏"

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
    case candidate = "候选"
    case shadow = "影子观察"
    case active = "已启用"
    case probation = "观察降级"
    case retired = "已淘汰"
    case quarantined = "已隔离"

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
            name: "中期动量", category: "方向", state: .active,
            ic: 0.041, ir: 0.61, coverage: 0.96, weight: 0.22,
            evidenceWindows: 8, reason: "连续通过全部样本外门槛"
        ),
        FactorItem(
            name: "低波动质量", category: "防御", state: .active,
            ic: 0.036, ir: 0.54, coverage: 0.92, weight: 0.18,
            evidenceWindows: 7, reason: "成本后贡献稳定"
        ),
        FactorItem(
            name: "波动率期限结构", category: "衍生品", state: .shadow,
            ic: 0.029, ir: 0.41, coverage: 0.84, weight: 0.00,
            evidenceWindows: 5, reason: "等待第 6 个样本外窗口"
        ),
        FactorItem(
            name: "成交量冲击", category: "微观结构", state: .probation,
            ic: 0.014, ir: 0.21, coverage: 0.76, weight: 0.08,
            evidenceWindows: 9, reason: "连续一次低于 IC 门槛"
        ),
        FactorItem(
            name: "短期反转", category: "方向", state: .candidate,
            ic: 0.024, ir: 0.35, coverage: 0.82, weight: 0.00,
            evidenceWindows: 2, reason: "继续积累冻结样本外证据"
        ),
        FactorItem(
            name: "旧版情绪代理", category: "替代数据", state: .retired,
            ic: -0.008, ir: -0.12, coverage: 0.67, weight: 0.00,
            evidenceWindows: 11, reason: "连续三次失败，进入冷却期"
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
                case "波动率期限结构":
                    factors[index].evidenceWindows += 1
                    if factors[index].evidenceWindows >= 6 && reviewCount >= 2 {
                        factors[index].state = .active
                        factors[index].weight = min(0.05, maxFactorWeight)
                        factors[index].reason = "连续两次通过，建议以 5% 上限启用"
                    } else {
                        factors[index].reason = "首轮通过，等待连续复核"
                    }
                case "成交量冲击":
                    factors[index].ic -= 0.003
                    if reviewCount >= 2 {
                        factors[index].state = .retired
                        factors[index].weight = 0
                        factors[index].reason = "连续三次失败，冷却 126 天"
                    } else {
                        factors[index].reason = "第二次失败，维持观察降级"
                    }
                case "短期反转":
                    factors[index].evidenceWindows += 1
                    factors[index].state = .shadow
                    factors[index].reason = "候选数据门槛通过，进入影子观察"
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

