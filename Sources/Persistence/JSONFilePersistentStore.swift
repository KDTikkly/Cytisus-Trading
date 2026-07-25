import Foundation

enum PersistentStoreError: Error {
    case unsupportedSchemaVersion(Int)
    case invalidJSONLine
}

final class JSONFilePersistentStore: SettingsStore, ApplicationLogStore, AuditEventStore, MigrationStore, StrategyStateStore, FactorResearchStore, ExecutionStore, ModelProviderStore, LocalStudioStore, LongbridgeConnectionStore {
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
    private var manifestsURL: URL { rootURL.appendingPathComponent("strategy-manifests.json") }
    private var strategyStatesURL: URL { rootURL.appendingPathComponent("strategy-states.json") }
    private var parameterChangesURL: URL { rootURL.appendingPathComponent("strategy-parameter-changes.ndjson") }
    private var liveAuthorizationsURL: URL { rootURL.appendingPathComponent("live-authorizations.json") }
    private var factorDefinitionsURL: URL {
        rootURL.appendingPathComponent("factor-definitions.json")
    }
    private var factorTrialsURL: URL {
        rootURL.appendingPathComponent("factor-trials.ndjson")
    }
    private var executionStateURL: URL {
        rootURL.appendingPathComponent("execution-state.json")
    }
    private var modelProvidersURL: URL {
        rootURL.appendingPathComponent("model-providers.json")
    }
    private var providerModelsURL: URL {
        rootURL.appendingPathComponent("provider-models.json")
    }
    private var modelRoleAssignmentsURL: URL {
        rootURL.appendingPathComponent("model-role-assignments.json")
    }
    private var providerTestEventsURL: URL {
        rootURL.appendingPathComponent("provider-test-events.ndjson")
    }
    private var localStudioStateURL: URL {
        rootURL.appendingPathComponent("local-studio-state.json")
    }
    private var longbridgeConnectionURL: URL {
        rootURL.appendingPathComponent("longbridge-connection.json")
    }

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

    func loadStrategyManifests() throws -> [StrategyManifest] {
        guard fileManager.fileExists(atPath: manifestsURL.path) else { return [] }
        return try read([StrategyManifest].self, from: manifestsURL)
    }

    func saveStrategyManifest(_ manifest: StrategyManifest) throws {
        var values = try loadStrategyManifests()
        values.removeAll { $0.strategyId == manifest.strategyId }
        values.append(manifest)
        try write(values.sorted { $0.strategyId < $1.strategyId }, to: manifestsURL)
    }

    func loadStrategyStates() throws -> [StrategyPersistentState] {
        guard fileManager.fileExists(atPath: strategyStatesURL.path) else { return [] }
        return try read([StrategyPersistentState].self, from: strategyStatesURL)
    }

    func saveStrategyState(_ state: StrategyPersistentState) throws {
        var values = try loadStrategyStates()
        values.removeAll { $0.strategyId == state.strategyId }
        values.append(state)
        try write(values.sorted { $0.strategyId < $1.strategyId }, to: strategyStatesURL)
    }

    func loadParameterChanges(
        strategyId: String,
        limit: Int
    ) throws -> [StrategyParameterChange] {
        guard fileManager.fileExists(atPath: parameterChangesURL.path) else {
            return []
        }
        let content = try String(contentsOf: parameterChangesURL, encoding: .utf8)
        return try content.split(separator: "\n").reversed().compactMap { line in
            guard let data = String(line).data(using: .utf8) else {
                throw PersistentStoreError.invalidJSONLine
            }
            return try decoder.decode(StrategyParameterChange.self, from: data)
        }
        .filter { $0.strategyId == strategyId }
        .prefix(max(0, limit))
        .map { $0 }
    }

    func appendParameterChange(_ change: StrategyParameterChange) throws {
        try appendLine(change, to: parameterChangesURL)
    }

    func loadLiveAuthorizations() throws -> [LiveAuthorization] {
        guard fileManager.fileExists(atPath: liveAuthorizationsURL.path) else {
            return []
        }
        return try read([LiveAuthorization].self, from: liveAuthorizationsURL)
    }

    func saveLiveAuthorization(_ authorization: LiveAuthorization) throws {
        var values = try loadLiveAuthorizations()
        values.removeAll { $0.authorizationId == authorization.authorizationId }
        values.append(authorization)
        try write(
            values.sorted { $0.authorizationId < $1.authorizationId },
            to: liveAuthorizationsURL
        )
    }

    func loadFactorDefinitions() throws -> [FactorDefinition] {
        guard fileManager.fileExists(atPath: factorDefinitionsURL.path) else {
            return []
        }
        return try read([FactorDefinition].self, from: factorDefinitionsURL)
    }

    func saveFactorDefinitions(_ definitions: [FactorDefinition]) throws {
        try write(
            definitions.sorted { $0.factorId < $1.factorId },
            to: factorDefinitionsURL
        )
    }

    func loadFactorTrials(limit: Int) throws -> [FactorTrial] {
        guard fileManager.fileExists(atPath: factorTrialsURL.path) else {
            return []
        }
        let content = try String(contentsOf: factorTrialsURL, encoding: .utf8)
        return try content.split(separator: "\n").suffix(max(0, limit)).map {
            line in
            guard let data = String(line).data(using: .utf8) else {
                throw PersistentStoreError.invalidJSONLine
            }
            return try decoder.decode(FactorTrial.self, from: data)
        }
    }

    func appendFactorTrial(_ trial: FactorTrial) throws {
        try appendLine(trial, to: factorTrialsURL)
    }

    func loadExecutionState() throws -> ExecutionStateSnapshot {
        guard fileManager.fileExists(atPath: executionStateURL.path) else {
            return .empty
        }
        return try read(
            ExecutionStateSnapshot.self,
            from: executionStateURL
        )
    }

    func saveExecutionState(_ state: ExecutionStateSnapshot) throws {
        try write(state, to: executionStateURL)
    }

    func loadModelProviders() throws -> [ModelProviderProfile] {
        guard fileManager.fileExists(atPath: modelProvidersURL.path) else {
            return []
        }
        return try read([ModelProviderProfile].self, from: modelProvidersURL)
    }

    func saveModelProviders(_ providers: [ModelProviderProfile]) throws {
        try write(
            providers.sorted { $0.displayName < $1.displayName },
            to: modelProvidersURL
        )
    }

    func loadProviderModels() throws -> [ProviderModelRecord] {
        guard fileManager.fileExists(atPath: providerModelsURL.path) else {
            return []
        }
        return try read([ProviderModelRecord].self, from: providerModelsURL)
    }

    func saveProviderModels(_ models: [ProviderModelRecord]) throws {
        try write(
            models.sorted {
                ($0.providerId, $0.modelId) < ($1.providerId, $1.modelId)
            },
            to: providerModelsURL
        )
    }

    func loadModelRoleAssignments() throws -> [ModelRoleAssignment] {
        guard fileManager.fileExists(atPath: modelRoleAssignmentsURL.path) else {
            return []
        }
        return try read(
            [ModelRoleAssignment].self,
            from: modelRoleAssignmentsURL
        )
    }

    func saveModelRoleAssignments(
        _ assignments: [ModelRoleAssignment]
    ) throws {
        try write(
            assignments.sorted { $0.position < $1.position },
            to: modelRoleAssignmentsURL
        )
    }

    func loadProviderTestEvents(limit: Int) throws -> [ProviderTestEvent] {
        guard fileManager.fileExists(atPath: providerTestEventsURL.path) else {
            return []
        }
        let content = try String(
            contentsOf: providerTestEventsURL,
            encoding: .utf8
        )
        return try content.split(separator: "\n").suffix(max(0, limit)).map {
            line in
            guard let data = String(line).data(using: .utf8) else {
                throw PersistentStoreError.invalidJSONLine
            }
            return try decoder.decode(ProviderTestEvent.self, from: data)
        }
    }

    func appendProviderTestEvent(_ event: ProviderTestEvent) throws {
        try appendLine(event, to: providerTestEventsURL)
    }

    func loadLocalStudioState() throws -> LocalStudioState {
        guard fileManager.fileExists(atPath: localStudioStateURL.path) else {
            return .empty
        }
        return try read(LocalStudioState.self, from: localStudioStateURL)
    }

    func saveLocalStudioState(_ state: LocalStudioState) throws {
        try write(state, to: localStudioStateURL)
    }

    func loadLongbridgeConnection() throws -> LongbridgeConnectionMetadata {
        guard fileManager.fileExists(atPath: longbridgeConnectionURL.path) else {
            return .empty
        }
        return try read(LongbridgeConnectionMetadata.self, from: longbridgeConnectionURL)
    }

    func saveLongbridgeConnection(_ metadata: LongbridgeConnectionMetadata) throws {
        try write(metadata, to: longbridgeConnectionURL)
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
