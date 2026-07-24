import Foundation
import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case factors = "Factor Lifecycle"
    case lab = "Strategy Lab"
    case data = "Data and Universe"
    case settings = "Settings"
    case logs = "Logs"
    case privacy = "Privacy and Sanitization"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "sparkles.rectangle.stack"
        case .factors: return "point.3.connected.trianglepath.dotted"
        case .lab: return "slider.horizontal.3"
        case .data: return "externaldrive.connected.to.line.below"
        case .settings: return "gearshape"
        case .logs: return "list.bullet.rectangle"
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
    @Published var fixtureMode: Bool {
        didSet { persistSettings() }
    }
    @Published var cliExecutablePath: String {
        didSet { persistSettings() }
    }
    @Published var defaultMarket: String {
        didSet { persistSettings() }
    }
    @Published var cacheDirectory: String {
        didSet { persistSettings() }
    }
    @Published var processTimeoutSeconds: Double {
        didSet { persistSettings() }
    }
    @Published var dataRetentionDays: Double {
        didSet { persistSettings() }
    }
    @Published var logRetentionDays: Double {
        didSet { persistSettings() }
    }
    @Published private(set) var factors: [FactorItem]
    @Published private(set) var universeEntries: [UniverseEntry] = []
    @Published private(set) var applicationLogs: [ApplicationLogEntry] = []
    @Published private(set) var cliStatusState: LongbridgeStatusState = .missing
    @Published private(set) var cliVersion = "Unavailable"
    @Published private(set) var lastCheckDisplay = "Not checked"
    @Published private(set) var dataFreshnessDisplay = "No market snapshot"
    @Published private(set) var dataPermissionsSummary =
        "No data permissions discovered"
    @Published private(set) var marketSession = "Unavailable"
    @Published private(set) var cacheSizeDisplay = "0 KB"
    @Published private(set) var cliStatusMessage =
        "Enable fixture mode or select an installed Longbridge CLI."
    @Published private(set) var cliPathDisplay = "Fixture mode (no executable)"

    let strategyMode: StrategyMode = .paperOnly
    let liveExecutionAvailable = false

    private let services: AppServices

    init(services: AppServices = .offlineFixture()) {
        self.services = services

        let settings = (try? services.settingsStore.loadSettings()) ?? AppSettings()
        riskBudget = settings.riskBudget
        coverageGate = settings.coverageGate
        maxFactorWeight = settings.maxFactorWeight
        fixtureMode = settings.fixtureMode
        cliExecutablePath = settings.cliExecutablePath
        defaultMarket = settings.defaultMarket.isEmpty ? "US" : settings.defaultMarket
        cacheDirectory = settings.cacheDirectory.isEmpty
            ? JSONMarketDataCache.defaultRootURL().path
            : settings.cacheDirectory
        processTimeoutSeconds = Double(max(2, settings.processTimeoutSeconds))
        dataRetentionDays = Double(max(7, settings.dataRetentionDays))
        logRetentionDays = Double(max(7, settings.logRetentionDays))
        factors = (try? services.factorRepository.loadFactors()) ?? []
        applicationLogs = (try? services.logStore.loadLogs(limit: 50)) ?? []

        appendLog(
            level: .info,
            module: "Application",
            message: fixtureMode
                ? "Started in offline fixture mode"
                : "Started with local CLI mode selected",
            context: ["fixture_mode": fixtureMode ? "true" : "false"]
        )
        if fixtureMode {
            refreshFixtureData()
        }
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

    var fixtureModeStatus: String {
        fixtureMode
            ? "Fixture mode is ON. No CLI, account, or network is used."
            : "Fixture mode is OFF. Only the selected local CLI may be inspected."
    }

    var processTimeoutDisplay: String {
        "\(Int(processTimeoutSeconds.rounded())) seconds"
    }

    var dataRetentionDisplay: String {
        "\(Int(dataRetentionDays.rounded())) days"
    }

    var logRetentionDisplay: String {
        "\(Int(logRetentionDays.rounded())) days"
    }

    func refreshLongbridge() {
        if fixtureMode {
            refreshFixtureData()
            return
        }

        universeEntries = []
        dataFreshnessDisplay = "No market snapshot"
        let timeout = min(120, max(2, processTimeoutSeconds))
        let inspection = services.cliAdapter.inspect(
            configuredPath: cliExecutablePath,
            timeout: timeout,
            cancellationRequested: { false }
        )
        cliStatusState = inspection.state
        cliVersion = inspection.cliVersion
        cliPathDisplay = inspection.executableURL?.path
            ?? "System PATH lookup did not resolve an executable"
        lastCheckDisplay = inspection.checkedAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
        dataPermissionsSummary = inspection.dataPermissions.isEmpty
            ? "No advertised market-data permissions"
            : inspection.dataPermissions.joined(separator: ", ")
        cliStatusMessage = inspection.message
        appendLog(
            level: inspection.state == .ready ? .info : .warning,
            module: "LongbridgeCLI",
            message: "Read-only capability check completed with state \(inspection.state.rawValue).",
            context: safeCLIContext(state: inspection.state.rawValue)
        )

        guard inspection.state == .ready,
              let executableURL = inspection.executableURL,
              let capabilities = inspection.capabilities else {
            return
        }
        do {
            try refreshRealMarketData(
                executableURL: executableURL,
                capabilities: capabilities,
                timeout: timeout
            )
        } catch {
            cliStatusState = .degraded
            cliStatusMessage =
                "The local CLI returned unsupported or invalid read-only data."
            appendLog(
                level: .error,
                module: "LongbridgeCLI",
                message: "Read-only market refresh failed without logging raw CLI output.",
                context: safeCLIContext(state: "Failed")
            )
        }
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
        if fixtureMode {
            refreshFixtureData()
        }
        appendAudit(action: "FixtureStateReset", context: ["fixture_mode": "true"])
    }

    private func refreshFixtureData() {
        do {
            let snapshot = try services.fixtureDataService.loadFixtureSnapshot()
            cliStatusState = snapshot.capabilities.statusState
            cliVersion = snapshot.capabilities.cliVersion
            cliPathDisplay = "Fixture mode (no executable)"
            lastCheckDisplay = snapshot.authorization.checkedAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
            dataFreshnessDisplay = "Available \(snapshot.currentSnapshot.availableTime.formatted(date: .abbreviated, time: .shortened))"
            dataPermissionsSummary = snapshot.authorization.permissions.joined(
                separator: ", "
            )
            marketSession = snapshot.marketStatus.session
            cliStatusMessage = snapshot.capabilities.message
            universeEntries = snapshot.universe.entries
            updateCacheSize()
            appendLog(
                level: .info,
                module: "LongbridgeFixture",
                message: "Loaded deterministic read-only market and universe fixtures.",
                context: safeCLIContext(state: "Ready")
            )
        } catch {
            cliStatusState = .degraded
            cliStatusMessage = "Fixture market data could not be loaded."
            appendLog(
                level: .error,
                module: "LongbridgeFixture",
                message: "Fixture market-data refresh failed.",
                context: safeCLIContext(state: "Failed")
            )
        }
    }

    private func refreshRealMarketData(
        executableURL: URL,
        capabilities: LongbridgeCapabilities,
        timeout: TimeInterval
    ) throws {
        let required: [LongbridgeOperation] = [
            .securityList,
            .currentSnapshot,
            .historicalBars,
            .marketStatus
        ]
        guard required.allSatisfy({ operation in
            capabilities.commands.contains(where: { $0.operation == operation })
        }) else {
            cliStatusState = .degraded
            cliStatusMessage =
                "The installed CLI does not advertise every required market-data command."
            return
        }

        let securities = try services.marketDataClient.fetchSecurityList(
            executableURL: executableURL,
            capabilities: capabilities,
            market: defaultMarket,
            timeout: timeout
        )
        guard let reference = securities.securities.first else {
            throw LongbridgeAdapterError.invalidJSON(.securityList)
        }
        let end = Date()
        let start = end.addingTimeInterval(-30 * 24 * 60 * 60)
        let bars = try services.marketDataClient.fetchHistoricalBars(
            executableURL: executableURL,
            capabilities: capabilities,
            symbol: reference.symbol,
            interval: "Daily",
            start: start,
            end: end,
            timeout: timeout
        )
        let current = try services.marketDataClient.fetchCurrentSnapshot(
            executableURL: executableURL,
            capabilities: capabilities,
            symbol: reference.symbol,
            timeout: timeout
        )
        let status = try services.marketDataClient.fetchMarketStatus(
            executableURL: executableURL,
            capabilities: capabilities,
            market: defaultMarket,
            timeout: timeout
        )
        let positions: BrokerPositionSnapshot
        if capabilities.commands.contains(where: {
            $0.operation == .brokerPositions
        }) {
            positions = try services.marketDataClient.fetchBrokerPositions(
                executableURL: executableURL,
                capabilities: capabilities,
                timeout: timeout
            )
        } else {
            positions = BrokerPositionSnapshot(
                schemaVersion: 1,
                collectedAt: Date(),
                sourceVersion: capabilities.sourceVersion,
                dataHash: "",
                positions: []
            )
        }
        let configuration = UniverseConfiguration(
            schemaVersion: 1,
            market: defaultMarket,
            minimumPrice: 5,
            minimumAverageDailyVolume: 1_000_000,
            minimumListingAgeDays: 252,
            minimumHistoryCoverageDays: 252,
            ruleVersion: "universe-rules-1.1.0"
        )
        let universe = services.universeService.buildDailySnapshot(
            snapshotTime: Date(),
            configuration: configuration,
            securities: securities,
            positions: positions
        )

        _ = try services.marketDataCache.storeHistoricalBars(bars)
        _ = try services.marketDataCache.storeCurrentSnapshot(current)
        _ = try services.marketDataCache.storeUniverseSnapshot(universe)
        universeEntries = universe.entries
        dataFreshnessDisplay = "Available \(current.availableTime.formatted(date: .abbreviated, time: .shortened))"
        marketSession = status.session
        updateCacheSize()
        cliStatusMessage =
            "Read-only market data and the daily universe were refreshed."
        appendLog(
            level: .info,
            module: "LongbridgeCLI",
            message: "Read-only market data and universe refresh completed.",
            context: safeCLIContext(state: "Ready")
        )
    }

    private func updateCacheSize() {
        let bytes = (try? services.marketDataCache.cacheSizeBytes()) ?? 0
        cacheSizeDisplay = bytes < 1024
            ? "\(bytes) bytes"
            : String(format: "%.1f KB", Double(bytes) / 1024)
    }

    private func persistSettings() {
        let settings = AppSettings(
            fixtureMode: fixtureMode,
            strategyMode: .paperOnly,
            health: .degraded,
            riskBudget: riskBudget,
            coverageGate: coverageGate,
            maxFactorWeight: maxFactorWeight,
            cliExecutablePath: cliExecutablePath,
            defaultMarket: defaultMarket,
            cacheDirectory: cacheDirectory,
            processTimeoutSeconds: Int(processTimeoutSeconds.rounded()),
            dataRetentionDays: Int(dataRetentionDays.rounded()),
            logRetentionDays: Int(logRetentionDays.rounded())
        )

        do {
            try services.settingsStore.saveSettings(settings)
        } catch {
            appendLog(
                level: .error,
                module: "Persistence",
                message: "Failed to save non-sensitive settings",
                context: [:]
            )
        }
    }

    private func appendLog(
        level: ApplicationLogLevel,
        module: String,
        message: String,
        context: [String: String]
    ) {
        let safeContext = context.mapValues {
            SensitiveDataRedactor.redact($0)
        }
        let entry = ApplicationLogEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            severity: level,
            module: module,
            message: SensitiveDataRedactor.redact(message),
            correlationID: nil,
            context: safeContext
        )
        try? services.logStore.appendLog(entry)
        applicationLogs.append(entry)
        if applicationLogs.count > 100 {
            applicationLogs.removeFirst(applicationLogs.count - 100)
        }
    }

    private func safeCLIContext(state: String) -> [String: String] {
        [
            "call_category": CLICallCategory.readOnlyData.rawValue,
            "state": state,
            "raw_authentication_output_logged": "false"
        ]
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
