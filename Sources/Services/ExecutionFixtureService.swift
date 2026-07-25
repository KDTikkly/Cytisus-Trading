import Foundation

final class ExecutionFixtureService {
    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func loadPaperGatewayFixture() throws -> PaperGatewayFixture {
        try read("paper-gateway-cycle", as: PaperGatewayFixture.self)
    }

    func loadExecutionCapability() throws
        -> LongbridgeExecutionCapability {
        try read(
            "longbridge-execution-capability",
            as: LongbridgeExecutionCapability.self
        )
    }

    func loadReconciliationFailure() throws
        -> ReconciliationFailureFixture {
        try read(
            "reconciliation-failure",
            as: ReconciliationFailureFixture.self
        )
    }

    private func read<T: Decodable>(
        _ name: String,
        as type: T.Type
    ) throws -> T {
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "fixtures/execution"
        ) ?? bundle.resourceURL?
            .appendingPathComponent(
                "fixtures/execution",
                isDirectory: true
            )
            .appendingPathComponent("\(name).json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureDataError.missingResource(name)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
}
