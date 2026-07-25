import Foundation

enum ResearchFixtureError: Error, LocalizedError {
    case missingResource(String)
    case invalidTemporalOrder
    case symbolOutsideUniverse

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Research fixture is missing: \(name)"
        case .invalidTemporalOrder:
            return "Research data violates available-time ordering."
        case .symbolOutsideUniverse:
            return "The research symbol is outside the current universe."
        }
    }
}

final class ResearchFixtureService {
    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func buildDataset(
        from snapshot: LongbridgeDataSnapshot
    ) throws -> NormalizedResearchDataset {
        let included = Set(
            snapshot.universe.entries
                .filter(\.included)
                .map(\.symbol)
        )
        guard included.contains(snapshot.historicalBars.symbol),
              let reference = snapshot.securityList.securities.first(
                where: { $0.symbol == snapshot.historicalBars.symbol }
              ) else {
            throw ResearchFixtureError.symbolOutsideUniverse
        }
        var previousClose: Double?
        let observations = try snapshot.historicalBars.bars
            .sorted { $0.eventTime < $1.eventTime }
            .map { bar -> ResearchObservation in
                guard bar.availableTime >= bar.eventTime else {
                    throw ResearchFixtureError.invalidTemporalOrder
                }
                let dailyReturn = previousClose.map {
                    abs($0) < 1e-12 ? 0 : bar.close / $0 - 1
                } ?? 0
                previousClose = bar.close
                return ResearchObservation(
                    symbol: snapshot.historicalBars.symbol,
                    industry: reference.industry,
                    eventTime: bar.eventTime,
                    availableTime: bar.availableTime,
                    open: bar.open,
                    high: bar.high,
                    low: bar.low,
                    close: bar.close,
                    volume: bar.volume,
                    returns: dailyReturn,
                    marketReturn: dailyReturn * 0.82,
                    sectorReturn: dailyReturn * 0.91,
                    capitalFlow: dailyReturn * bar.volume / 1_000_000
                )
            }
        let collectedAt = snapshot.historicalBars.bars
            .map(\.collectedAt)
            .max() ?? snapshot.universe.createdAt
        return NormalizedResearchDataset(
            datasetVersion: "longbridge:\(snapshot.historicalBars.dataHash)",
            universeVersion: "\(snapshot.universe.ruleVersion):\(snapshot.universe.sourceVersion)",
            createdAt: collectedAt,
            observations: observations
        )
    }

    func loadFactorDefinitions() throws -> [FactorDefinition] {
        try read(
            "research-factor-definitions",
            as: [FactorDefinition].self
        )
    }

    func loadRegimeAllocationFixture() throws -> RegimeAllocationFixture {
        try read(
            "regime-allocation-input",
            as: RegimeAllocationFixture.self
        )
    }

    private func read<T: Decodable>(
        _ name: String,
        as type: T.Type
    ) throws -> T {
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "fixtures/factors"
        ) ?? bundle.resourceURL?
            .appendingPathComponent("fixtures/factors", isDirectory: true)
            .appendingPathComponent("\(name).json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw ResearchFixtureError.missingResource(name)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
}
