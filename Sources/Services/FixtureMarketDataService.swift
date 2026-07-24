import Foundation

protocol LongbridgeDataServicing {
    func loadFixtureSnapshot() throws -> LongbridgeDataSnapshot
}

enum FixtureDataError: Error {
    case missingResource(String)
}

final class FixtureLongbridgeDataService: LongbridgeDataServicing {
    private let cache: MarketDataCache
    private let universeService: UniverseServicing
    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(
        cache: MarketDataCache,
        universeService: UniverseServicing,
        bundle: Bundle = .main
    ) {
        self.cache = cache
        self.universeService = universeService
        self.bundle = bundle

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadFixtureSnapshot() throws -> LongbridgeDataSnapshot {
        let capabilities: LongbridgeCapabilities = try read("cli-capabilities")
        let authorization: AuthorizationStatusSummary = try read(
            "authorization-status"
        )
        let connectivity: ConnectivitySummary = try read("connectivity-check")
        let historicalBars: HistoricalBarSeries = try read(
            "historical-daily-bars"
        )
        let currentSnapshot: CurrentMarketSnapshot = try read(
            "current-market-snapshot"
        )
        let marketStatus: MarketStatusSnapshot = try read("market-status")
        let securityList: SecurityListSnapshot = try read("security-list")
        let positions: BrokerPositionSnapshot = try read("broker-positions")
        let configuration: UniverseConfiguration = try read("universe-config")
        let universe = universeService.buildDailySnapshot(
            snapshotTime: securityList.collectedAt,
            configuration: configuration,
            securities: securityList,
            positions: positions
        )

        _ = try cache.storeHistoricalBars(historicalBars)
        _ = try cache.storeCurrentSnapshot(currentSnapshot)
        _ = try cache.storeUniverseSnapshot(universe)

        return LongbridgeDataSnapshot(
            capabilities: capabilities,
            authorization: authorization,
            connectivity: connectivity,
            historicalBars: historicalBars,
            currentSnapshot: currentSnapshot,
            marketStatus: marketStatus,
            securityList: securityList,
            brokerPositions: positions,
            universe: universe
        )
    }

    private func read<T: Decodable>(_ name: String) throws -> T {
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "fixtures/longbridge"
        ) ?? bundle.resourceURL?
            .appendingPathComponent("fixtures/longbridge", isDirectory: true)
            .appendingPathComponent("\(name).json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureDataError.missingResource(name)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
}
