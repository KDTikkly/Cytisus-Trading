import Foundation

final class FixtureFactorRepository: FactorRepository {
    private let decoder = JSONDecoder()
    private let fileManager: FileManager
    private var current: [FactorItem]?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadFactors() throws -> [FactorItem] {
        if let current {
            return current
        }

        let loaded = try loadFixture()
        current = loaded
        return loaded
    }

    func saveFactors(_ factors: [FactorItem]) throws {
        current = factors
    }

    func resetToFixtures() throws -> [FactorItem] {
        current = nil
        return try loadFactors()
    }

    private func loadFixture() throws -> [FactorItem] {
        let relativePath = "fixtures/factors/demo-factors.json"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(relativePath)
        ].compactMap { $0 }

        if let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return try decoder.decode([FactorItem].self, from: Data(contentsOf: url))
        }

        return Self.fallbackFactors
    }

    private static let fallbackFactors: [FactorItem] = [
        FactorItem(
            factorID: "medium-term-momentum",
            name: "Medium-Term Momentum",
            category: "Directional",
            state: .active,
            ic: 0.041,
            ir: 0.61,
            coverage: 0.96,
            weight: 0.22,
            evidenceWindows: 8,
            reason: "Cleared every out-of-sample gate"
        ),
        FactorItem(
            factorID: "low-volatility-quality",
            name: "Low-Volatility Quality",
            category: "Defensive",
            state: .active,
            ic: 0.036,
            ir: 0.54,
            coverage: 0.92,
            weight: 0.18,
            evidenceWindows: 7,
            reason: "Stable contribution after costs"
        ),
        FactorItem(
            factorID: "volatility-term-structure",
            name: "Volatility Term Structure",
            category: "Derivatives",
            state: .shadow,
            ic: 0.029,
            ir: 0.41,
            coverage: 0.84,
            weight: 0,
            evidenceWindows: 5,
            reason: "Waiting for the sixth out-of-sample window"
        ),
        FactorItem(
            factorID: "volume-impact",
            name: "Volume Impact",
            category: "Market Microstructure",
            state: .probation,
            ic: 0.014,
            ir: 0.21,
            coverage: 0.76,
            weight: 0.08,
            evidenceWindows: 9,
            reason: "One review below the IC threshold"
        ),
        FactorItem(
            factorID: "short-term-reversal",
            name: "Short-Term Reversal",
            category: "Directional",
            state: .candidate,
            ic: 0.024,
            ir: 0.35,
            coverage: 0.82,
            weight: 0,
            evidenceWindows: 2,
            reason: "Continue collecting frozen OOS evidence"
        ),
        FactorItem(
            factorID: "legacy-sentiment-proxy",
            name: "Legacy Sentiment Proxy",
            category: "Alternative Data",
            state: .retired,
            ic: -0.008,
            ir: -0.12,
            coverage: 0.67,
            weight: 0,
            evidenceWindows: 11,
            reason: "Failed three reviews and entered cooldown"
        )
    ]
}
