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

@MainActor
final class StudioModel: ObservableObject {
    @Published var selection: StudioSection = .overview
    @Published private(set) var reviewCount = 0
    @Published private(set) var lastReview: Date?
    @Published var riskBudget: Double {
        didSet { persistSettings() }
    }
    @Published var coverageGate: Double {
        didSet { persistSettings() }
    }
    @Published var maxFactorWeight: Double {
        didSet { persistSettings() }
    }
    @Published private(set) var factors: [FactorItem]

    let fixtureMode = true
    let strategyMode: StrategyMode = .paperOnly
    let liveExecutionAvailable = false

    private let services: AppServices

    init(services: AppServices = .offlineFixture()) {
        self.services = services

        let settings = (try? services.settingsStore.loadSettings()) ?? AppSettings()
        riskBudget = settings.riskBudget
        coverageGate = settings.coverageGate
        maxFactorWeight = settings.maxFactorWeight
        factors = (try? services.factorRepository.loadFactors()) ?? []

        appendLog(
            level: .info,
            module: "Application",
            message: "Started in offline fixture mode"
        )
    }

    var activeFactors: Int {
        factors.filter { $0.state == .active }.count
    }

    var shadowFactors: Int {
        factors.filter { $0.state == .shadow || $0.state == .candidate }.count
    }

    var weightedCoverage: Double {
        let active = factors.filter { $0.state == .active || $0.state == .probation }
        let totalWeight = active.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        return active.reduce(0) { $0 + $1.coverage * $1.weight } / totalWeight
    }

    func runReview() {
        reviewCount += 1
        lastReview = Date()

        let result = services.governanceService.runReview(
            factors: factors,
            reviewCount: reviewCount,
            maxFactorWeight: maxFactorWeight
        )

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            factors = result.factors
        }

        try? services.factorRepository.saveFactors(factors)
        appendAudit(
            action: "FixtureFactorReview",
            context: [
                "changed_factor_ids": result.changedFactorIDs.joined(separator: ","),
                "review_count": String(reviewCount)
            ]
        )
    }

    func resetDemo() {
        let resetFactors = (try? services.factorRepository.resetToFixtures()) ?? []
        withAnimation(.easeInOut(duration: 0.35)) {
            factors = resetFactors
            reviewCount = 0
            lastReview = nil
        }

        appendAudit(action: "FixtureStateReset", context: ["fixture_mode": "true"])
    }

    private func persistSettings() {
        let settings = AppSettings(
            fixtureMode: true,
            strategyMode: .paperOnly,
            health: .degraded,
            riskBudget: riskBudget,
            coverageGate: coverageGate,
            maxFactorWeight: maxFactorWeight
        )

        do {
            try services.settingsStore.saveSettings(settings)
        } catch {
            appendLog(
                level: .error,
                module: "Persistence",
                message: "Failed to save non-sensitive settings"
            )
        }
    }

    private func appendLog(level: ApplicationLogLevel, module: String, message: String) {
        let entry = ApplicationLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            severity: level,
            module: module,
            message: message,
            correlationID: nil,
            context: ["fixture_mode": "true"]
        )
        try? services.logStore.appendLog(entry)
    }

    private func appendAudit(action: String, context: [String: String]) {
        let correlationID = UUID().uuidString
        let event = AuditEvent(
            id: UUID().uuidString,
            occurredAt: Date(),
            category: .factorLifecycle,
            action: action,
            result: .completed,
            actor: "local-user",
            correlationID: correlationID,
            context: context
        )
        try? services.auditStore.appendAuditEvent(event)
    }
}
