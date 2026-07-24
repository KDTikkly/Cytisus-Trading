import Foundation

protocol LongbridgeMarketDataClient {
    func fetchHistoricalBars(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        symbol: String,
        interval: String,
        start: Date,
        end: Date,
        timeout: TimeInterval
    ) throws -> HistoricalBarSeries
    func fetchCurrentSnapshot(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        symbol: String,
        timeout: TimeInterval
    ) throws -> CurrentMarketSnapshot
    func fetchMarketStatus(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        market: String,
        timeout: TimeInterval
    ) throws -> MarketStatusSnapshot
    func fetchSecurityList(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        market: String,
        timeout: TimeInterval
    ) throws -> SecurityListSnapshot
    func fetchBrokerPositions(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        timeout: TimeInterval
    ) throws -> BrokerPositionSnapshot
}

final class CLILongbridgeMarketDataClient: LongbridgeMarketDataClient {
    private let adapter: LongbridgeCLIAdapting
    private let decoder: JSONDecoder
    private let formatter: ISO8601DateFormatter

    init(adapter: LongbridgeCLIAdapting) {
        self.adapter = adapter
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.formatter = ISO8601DateFormatter()
    }

    func fetchHistoricalBars(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        symbol: String,
        interval: String,
        start: Date,
        end: Date,
        timeout: TimeInterval
    ) throws -> HistoricalBarSeries {
        try executeAndParse(
            CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .historicalBars,
                values: [
                    "symbol": symbol,
                    "interval": interval,
                    "start": formatter.string(from: start),
                    "end": formatter.string(from: end)
                ]
            ),
            timeout: timeout
        )
    }

    func fetchCurrentSnapshot(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        symbol: String,
        timeout: TimeInterval
    ) throws -> CurrentMarketSnapshot {
        try executeAndParse(
            CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .currentSnapshot,
                values: ["symbol": symbol]
            ),
            timeout: timeout
        )
    }

    func fetchMarketStatus(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        market: String,
        timeout: TimeInterval
    ) throws -> MarketStatusSnapshot {
        try executeAndParse(
            CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .marketStatus,
                values: ["market": market]
            ),
            timeout: timeout
        )
    }

    func fetchSecurityList(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        market: String,
        timeout: TimeInterval
    ) throws -> SecurityListSnapshot {
        try executeAndParse(
            CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .securityList,
                values: ["market": market]
            ),
            timeout: timeout
        )
    }

    func fetchBrokerPositions(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        timeout: TimeInterval
    ) throws -> BrokerPositionSnapshot {
        try executeAndParse(
            CapabilityAwareCommandFactory.build(
                executableURL: executableURL,
                capabilities: capabilities,
                operation: .brokerPositions
            ),
            timeout: timeout
        )
    }

    private func executeAndParse<T: Decodable>(
        _ command: CLICommand,
        timeout: TimeInterval
    ) throws -> T {
        let result = try adapter.executeReadOnly(
            command: command,
            timeout: timeout,
            cancellationRequested: { false }
        )
        guard result.succeeded else {
            throw LongbridgeAdapterError.processFailed(command.operation)
        }
        do {
            return try decoder.decode(
                T.self,
                from: Data(result.standardOutput.utf8)
            )
        } catch {
            throw LongbridgeAdapterError.invalidJSON(command.operation)
        }
    }
}
