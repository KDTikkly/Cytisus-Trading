import Foundation

enum PersistentStoreError: Error {
    case unsupportedSchemaVersion(Int)
    case invalidJSONLine
}

final class JSONFilePersistentStore: SettingsStore, ApplicationLogStore, AuditEventStore, MigrationStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let lineEncoder: JSONEncoder
    private let decoder: JSONDecoder

    private var settingsURL: URL { rootURL.appendingPathComponent("settings.json") }
    private var schemaURL: URL { rootURL.appendingPathComponent("schema-version.json") }
    private var migrationsURL: URL { rootURL.appendingPathComponent("migrations.json") }
    private var logsURL: URL { rootURL.appendingPathComponent("application-logs.ndjson") }
    private var auditURL: URL { rootURL.appendingPathComponent("audit-events.ndjson") }

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        lineEncoder.outputFormatting = [.sortedKeys]
        self.lineEncoder = lineEncoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Cytisus-Trading", isDirectory: true)
    }

    func initializeSchema() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: schemaURL.path) else {
            try write(StoreSchemaVersion.current, to: schemaURL)
            try write([MigrationRecord](), to: migrationsURL)
            return
        }

        let existing: StoreSchemaVersion = try read(StoreSchemaVersion.self, from: schemaURL)
        if existing.version > StoreSchemaVersion.current.version {
            throw PersistentStoreError.unsupportedSchemaVersion(existing.version)
        }

        guard existing.version < StoreSchemaVersion.current.version else { return }

        var records = (try? read([MigrationRecord].self, from: migrationsURL)) ?? []
        records.append(
            MigrationRecord(
                id: UUID().uuidString,
                fromVersion: existing.version,
                toVersion: StoreSchemaVersion.current.version,
                appliedAt: Date()
            )
        )
        try write(records, to: migrationsURL)
        try write(StoreSchemaVersion.current, to: schemaURL)
    }

    func schemaVersion() throws -> StoreSchemaVersion {
        try read(StoreSchemaVersion.self, from: schemaURL)
    }

    func migrationRecords() throws -> [MigrationRecord] {
        (try? read([MigrationRecord].self, from: migrationsURL)) ?? []
    }

    func loadSettings() throws -> AppSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return AppSettings()
        }
        return try read(AppSettings.self, from: settingsURL)
    }

    func saveSettings(_ settings: AppSettings) throws {
        try write(settings, to: settingsURL)
    }

    func appendLog(_ entry: ApplicationLogEntry) throws {
        try appendLine(entry, to: logsURL)
    }

    func loadLogs(limit: Int) throws -> [ApplicationLogEntry] {
        guard fileManager.fileExists(atPath: logsURL.path) else { return [] }
        let content = try String(contentsOf: logsURL, encoding: .utf8)
        let lines = content.split(separator: "\n").suffix(max(0, limit))
        return try lines.map { line in
            guard let data = String(line).data(using: .utf8) else {
                throw PersistentStoreError.invalidJSONLine
            }
            return try decoder.decode(ApplicationLogEntry.self, from: data)
        }
    }

    func appendAuditEvent(_ event: AuditEvent) throws {
        try appendLine(event, to: auditURL)
    }

    func loadAuditEvents(limit: Int) throws -> [AuditEvent] {
        guard fileManager.fileExists(atPath: auditURL.path) else { return [] }
        let content = try String(contentsOf: auditURL, encoding: .utf8)
        let lines = content.split(separator: "\n").suffix(max(0, limit))
        return try lines.map { line in
            guard let data = String(line).data(using: .utf8) else {
                throw PersistentStoreError.invalidJSONLine
            }
            return try decoder.decode(AuditEvent.self, from: data)
        }
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func appendLine<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var data = try lineEncoder.encode(value)
        data.append(0x0A)

        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
