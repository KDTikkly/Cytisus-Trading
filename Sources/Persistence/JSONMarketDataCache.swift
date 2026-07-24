import Foundation

final class JSONMarketDataCache: MarketDataCache {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateFormatter: ISO8601DateFormatter
    private let lock = NSLock()

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.dateFormatter = formatter
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        JSONFilePersistentStore.defaultRootURL(fileManager: fileManager)
            .appendingPathComponent("market-cache", isDirectory: true)
    }

    func storeHistoricalBars(_ series: HistoricalBarSeries) throws -> CacheWriteResult {
        try withLock {
            let url = historicalBarsURL(
                symbol: series.symbol,
                interval: series.interval,
                start: series.start,
                end: series.end
            )
            return try writeIdempotent(
                series,
                to: url,
                identity: { $0.dataHash },
                expectedIdentity: series.dataHash
            )
        }
    }

    func storeCurrentSnapshot(_ snapshot: CurrentMarketSnapshot) throws -> CacheWriteResult {
        try withLock {
            let directory = rootURL.appendingPathComponent(
                "market-snapshots",
                isDirectory: true
            )
            let url = directory.appendingPathComponent(
                "\(safeComponent(snapshot.symbol)).json"
            )
            return try writeIdempotent(
                snapshot,
                to: url,
                identity: { $0.dataHash },
                expectedIdentity: snapshot.dataHash
            )
        }
    }

    func storeUniverseSnapshot(_ snapshot: UniverseSnapshot) throws -> CacheWriteResult {
        try withLock {
            let directory = rootURL.appendingPathComponent(
                "universe",
                isDirectory: true
            )
            let url = directory.appendingPathComponent(
                "\(safeComponent(snapshot.date)).json"
            )
            let expected = "\(snapshot.ruleVersion):\(snapshot.sourceVersion):\(snapshot.entries.count)"
            return try writeIdempotent(
                snapshot,
                to: url,
                identity: {
                    "\($0.ruleVersion):\($0.sourceVersion):\($0.entries.count)"
                },
                expectedIdentity: expected
            )
        }
    }

    func loadHistoricalBars(
        symbol: String,
        interval: String,
        start: Date,
        end: Date
    ) throws -> HistoricalBarSeries? {
        try withLock {
            let url = historicalBarsURL(
                symbol: symbol,
                interval: interval,
                start: start,
                end: end
            )
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try read(HistoricalBarSeries.self, from: url)
        }
    }

    func loadUniverseSnapshot(date: String) throws -> UniverseSnapshot? {
        try withLock {
            let url = rootURL
                .appendingPathComponent("universe", isDirectory: true)
                .appendingPathComponent("\(safeComponent(date)).json")
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try read(UniverseSnapshot.self, from: url)
        }
    }

    func cacheSizeBytes() throws -> Int64 {
        try withLock {
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }

            var total: Int64 = 0
            for case let url as URL in enumerator where url.pathExtension == "json" {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(values.fileSize ?? 0)
            }
            return total
        }
    }

    private func historicalBarsURL(
        symbol: String,
        interval: String,
        start: Date,
        end: Date
    ) -> URL {
        let identity = [
            symbol.uppercased(),
            interval.uppercased(),
            dateFormatter.string(from: start),
            dateFormatter.string(from: end)
        ].map(safeComponent).joined(separator: "_")
        return rootURL
            .appendingPathComponent("market-bars", isDirectory: true)
            .appendingPathComponent("\(identity).json")
    }

    private func writeIdempotent<T: Codable>(
        _ value: T,
        to url: URL,
        identity: (T) -> String,
        expectedIdentity: String
    ) throws -> CacheWriteResult {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: url.path) {
            let existing = try read(T.self, from: url)
            if identity(existing) == expectedIdentity {
                return .unchanged
            }
            try encoder.encode(value).write(to: url, options: .atomic)
            return .updated
        }

        try encoder.encode(value).write(to: url, options: .atomic)
        return .created
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        })
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
