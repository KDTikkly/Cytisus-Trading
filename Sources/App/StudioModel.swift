import Foundation
import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable {
    case overview = "Dashboard"
    case factors = "Factor Lifecycle"
    case lab = "Strategies"
    case portfolio = "Portfolio"
    case execution = "Execution"
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
        case .portfolio: return "chart.pie"
        case .execution: return "arrow.left.arrow.right.square"
        case .data: return "externaldrive.connected.to.line.below"
        case .settings: return "gearshape"
        case .logs: return "list.bullet.rectangle"
        case .privacy: return "lock.shield"
        }
    }
}

struct BrokerNetPositionSnapshot: Identifiable {
    let symbol: String
    let quantity: Double
    let status: ReconciliationStatus

    var id: String { symbol }
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
    @Published var globalLiveLock: Bool {
        didSet {
            if !globalLiveLock {
                for strategy in strategies where strategy.mode == .live {
                    strategy.mode = .paperOnly
                    strategy.liveToPaperTransition = .stopOpeningRisk
                    strategy.blocksNewRisk = true
                    saveStrategy(strategy)
                }
                latestStrategyAlert =
                    "Global Live Lock is OFF. All strategies use Local Paper."
            }
            persistSettings()
            appendAudit(
                action: "GlobalLiveLockChanged",
                context: ["enabled": globalLiveLock ? "true" : "false"],
                category: .settings
            )
        }
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
    @Published private(set) var strategies: [StrategyItemModel] = []
    @Published var selectedStrategyID = ""
    @Published var strategyManifestPath = ""
    @Published private(set) var strategyStatusMessage =
        "Official fixture strategy is ready in Local Paper."
    @Published private(set) var latestStrategyAlert =
        "Local Paper is available without Longbridge CLI. Live remains rejecting."
    @Published var selectedTransition: LiveToPaperTransition = .stopOpeningRisk
    @Published var logSearchText = ""
    @Published var selectedLogSeverity: ApplicationLogLevel?
    @Published private(set) var researchFactors: [FactorResearchSummary] = []
    @Published private(set) var recentFactorTrials: [FactorTrial] = []
    @Published private(set) var factorSearchStatus =
        "Tiny deterministic research search is ready."
    @Published private(set) var regimeSnapshot: RegimeSnapshot?
    @Published private(set) var capitalAllocation: CapitalAllocationResult?
    @Published private(set) var executionState = ExecutionStateSnapshot.empty

    let liveExecutionAvailable = false

    private let services: AppServices
    private var externalRuntimes: [String: ExternalStrategyRuntime] = [:]
    private var researchDataset: NormalizedResearchDataset?

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
        globalLiveLock = settings.globalLiveLock
        factors = (try? services.factorRepository.loadFactors()) ?? []
        applicationLogs = (try? services.logStore.loadLogs(limit: 50)) ?? []
        initializeStrategies()
        initializeResearch()
        initializeExecution()

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

    var selectedStrategy: StrategyItemModel? {
        strategies.first { $0.strategyId == selectedStrategyID }
    }

    var strategyMode: StrategyMode {
        selectedStrategy?.mode ?? .paperOnly
    }

    var paperStrategyCount: Int {
        strategies.filter { $0.mode == .paperOnly }.count
    }

    var liveStrategyCount: Int {
        strategies.filter { $0.mode == .live }.count
    }

    var healthyStrategyCount: Int {
        strategies.filter { $0.health == .healthy }.count
    }

    var globalLiveLockStatus: String {
        globalLiveLock
            ? "ON: authorized strategies may select Live mode"
            : "OFF: every strategy remains in Local Paper"
    }

    var latestCycleDisplay: String {
        guard let cycle = strategies
            .flatMap(\.cycles)
            .max(by: { $0.completedAt < $1.completedAt }) else {
            return "No completed strategy cycle"
        }
        return "\(cycle.cycleId) | \(cycle.intentCount) intent"
    }

    var liveAuthorizationSummary: String {
        guard let strategy = selectedStrategy else {
            return "No strategy selected."
        }
        let authorization = try? services.strategyStore
            .loadLiveAuthorizations()
            .first { $0.strategyId == strategy.strategyId }
        guard let authorization else {
            return "No Live authorization is stored."
        }
        return "Authorization expires \(authorization.expiresAt.formatted(date: .abbreviated, time: .shortened)) | Capital \(authorization.maximumCapital) | Orders \(authorization.maximumOrderFrequency)/period"
    }

    var filteredApplicationLogs: [ApplicationLogEntry] {
        Array(applicationLogs.filter { entry in
            let matchesSeverity = selectedLogSeverity == nil ||
                entry.severity == selectedLogSeverity
            let query = logSearchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let matchesQuery = query.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(query) ||
                entry.module.localizedCaseInsensitiveContains(query) ||
                (entry.strategyID?.localizedCaseInsensitiveContains(query) ??
                    false) ||
                (entry.correlationID?.localizedCaseInsensitiveContains(query) ??
                    false) ||
                (entry.cycleID?.localizedCaseInsensitiveContains(query) ??
                    false)
            return matchesSeverity && matchesQuery
        }
        .reversed())
    }

    var fixtureModeStatus: String {
        fixtureMode
            ? "Fixture mode is ON. No CLI, account, or network is used."
            : "Fixture mode is OFF. Only the selected local CLI may be inspected."
    }

    var regimeTrendDisplay: String {
        (regimeSnapshot?.trend ?? 0).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var regimeRangeDisplay: String {
        (regimeSnapshot?.range ?? 0).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var regimeHighVolatilityDisplay: String {
        (regimeSnapshot?.highVolatility ?? 0).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var regimeCrisisDisplay: String {
        (regimeSnapshot?.crisis ?? 0).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var regimeUncertaintyDisplay: String {
        (regimeSnapshot?.uncertainty ?? 0).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var regimeRiskDisplay: String {
        (regimeSnapshot?.riskMultiplier ?? 0).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    var allocatorSummary: String {
        guard let allocation = capitalAllocation else {
            return "No allocator result is available."
        }
        return "Risk budget \(allocation.totalRiskBudget.formatted(.currency(code: "USD").precision(.fractionLength(0)))) after regime uncertainty and capacity controls."
    }

    var brokerNetPositions: [BrokerNetPositionSnapshot] {
        Dictionary(
            grouping: executionState.ledgerPositions,
            by: \.symbol
        ).map { symbol, positions in
            let latest = executionState.reconciliations
                .last(where: { $0.symbol == symbol })
            return BrokerNetPositionSnapshot(
                symbol: symbol,
                quantity: latest?.brokerQuantity ??
                    positions.map(\.virtualQuantity).reduce(0, +),
                status: latest?.status ?? .reconciled
            )
        }
        .sorted { $0.symbol < $1.symbol }
    }

    var persistentExecutionAlert: String {
        guard !executionState.blockedSymbols.isEmpty else {
            return "No unresolved reconciliation risk event."
        }
        return executionState.riskEvents.last(where: {
            executionState.blockedSymbols.contains($0.symbol)
        })?.message ??
            "An unresolved reconciliation risk event blocks new risk."
    }

    var executionSafetyStatus: String {
        "Local Paper is independent from Longbridge CLI. Live submission is intentionally rejecting."
    }

    func runTinyFactorSearch() {
        guard let dataset = researchDataset else {
            factorSearchStatus =
                "Research fixtures are unavailable; no trial was run."
            return
        }
        do {
            let definitions = try services.factorResearchStore
                .loadFactorDefinitions()
            let result = try services.factorSearch.runTinySearch(
                dataset: dataset,
                existingDefinitions: definitions,
                configuration: .tiny
            )
            researchFactors = result.summaries
            recentFactorTrials = Array(result.trials.reversed())
            factorSearchStatus = result.status
            appendAudit(
                action: "TinyFactorSearchCompleted",
                context: [
                    "evaluated": String(result.evaluatedCount),
                    "candidates": String(result.candidateCount),
                    "rejected": String(result.rejectedCount),
                    "quarantined": String(result.quarantinedCount),
                    "network_used": "false",
                    "cli_used": "false"
                ],
                category: .factorLifecycle
            )
        } catch {
            factorSearchStatus =
                "Factor search failed: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
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

    func registerThirdPartyStrategy() {
        do {
            let registration = try services.strategyRegistry.loadThirdParty(
                manifestPath: strategyManifestPath,
                existingStrategyIds: Set(strategies.map(\.strategyId))
            )
            let state = defaultStrategyState(
                manifest: registration.manifest,
                parameters: registration.parameters
            )
            try services.strategyStore.saveStrategyManifest(
                registration.manifest
            )
            try services.strategyStore.saveStrategyState(state)
            let item = StrategyItemModel(
                manifest: registration.manifest,
                parameterSchema: registration.parameters,
                state: state
            )
            strategies.append(item)
            selectedStrategyID = item.strategyId
            strategyStatusMessage =
                "Registered third-party strategy \(item.name)."
            appendAudit(
                action: "ThirdPartyStrategyRegistered",
                context: [
                    "strategy_id": item.strategyId,
                    "source": item.sourceLabel
                ],
                category: .strategyLifecycle
            )
        } catch {
            strategyStatusMessage =
                "Strategy registration rejected: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
    }

    func startSelectedStrategy() {
        guard let strategy = selectedStrategy else { return }
        if strategy.manifest.source == .official {
            strategy.runtimeState = .ready
            strategyStatusMessage =
                "Official strategy is ready. Run a deterministic Local Paper cycle."
            saveStrategy(strategy)
            return
        }
        guard externalRuntimes[strategy.strategyId] == nil else {
            strategyStatusMessage = "The strategy process is already running."
            return
        }
        let runtime = ExternalStrategyRuntime(
            manifest: strategy.manifest,
            codec: services.strategyMessageCodec,
            messageHandler: { [weak self, weak strategy] message in
                DispatchQueue.main.async {
                    guard let self, let strategy else { return }
                    self.handleExternalMessage(message, strategy: strategy)
                }
            },
            logHandler: { [weak self] entry in
                DispatchQueue.main.async {
                    self?.appendExistingLog(entry)
                }
            }
        )
        do {
            try runtime.start(
                initialize: coreMessage(
                    strategy: strategy,
                    cycleId: "runtime-start",
                    type: "initialize",
                    payload: [
                        "mode": strategy.mode.rawValue,
                        "parameter_version": String(
                            strategy.parameterVersion
                        )
                    ]
                )
            )
            externalRuntimes[strategy.strategyId] = runtime
            strategy.runtimeState = .starting
            strategyStatusMessage =
                "Third-party strategy process started with NDJSON transport."
        } catch {
            strategy.runtimeState = .rejected
            strategyStatusMessage =
                "Strategy process rejected: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
        saveStrategy(strategy)
    }

    func pauseSelectedStrategy() {
        sendRuntimeControl(type: "pause", resultingState: .paused)
    }

    func resumeSelectedStrategy() {
        sendRuntimeControl(type: "resume", resultingState: .running)
    }

    func stopSelectedStrategy() {
        guard let strategy = selectedStrategy else { return }
        if let runtime = externalRuntimes.removeValue(
            forKey: strategy.strategyId
        ) {
            runtime.shutdown(
                coreMessage(
                    strategy: strategy,
                    cycleId: "runtime-stop",
                    type: "shutdown",
                    payload: ["reason": "user_requested_strategy_shutdown"]
                )
            )
        }
        strategy.runtimeState = .stopped
        strategyStatusMessage = "Strategy runtime stopped gracefully."
        saveStrategy(strategy)
    }

    func runSelectedPaperCycle() {
        guard let strategy = selectedStrategy else { return }
        guard strategy.mode == .paperOnly else {
            latestStrategyAlert =
                "The Local Paper cycle cannot run while Live mode is selected."
            return
        }
        guard strategy.manifest.source == .official else {
            latestStrategyAlert =
                "Use Start, Pause, Resume, and Stop for third-party processes."
            return
        }
        applyPendingParameterChanges(strategy)
        do {
            let result = try services.officialStrategyRuntime.runPaperCycle(
                manifest: strategy.manifest,
                parameterValues: Dictionary(
                    uniqueKeysWithValues: strategy.parameters.map {
                        ($0.key, $0.value)
                    }
                )
            )
            strategy.runtimeState = .running
            strategy.health = result.health
            strategy.lastHeartbeat = result.lastHeartbeat
            strategy.signals = result.signals
            strategy.targets = result.targets
            strategy.intents = result.intents
            strategy.cycles.insert(result.cycle, at: 0)
            strategy.cycles = Array(strategy.cycles.prefix(20))
            for message in result.messages where message.messageType == "log" {
                appendLog(
                    level: parseLogLevel(message.payload["level"]),
                    module: message.payload["module"] ?? "OfficialStrategy",
                    message: message.payload["message"] ??
                        "Strategy log event.",
                    strategyID: strategy.strategyId,
                    correlationID: message.correlationId,
                    cycleID: message.cycleId,
                    context: [
                        "message_type": message.messageType,
                        "mode": StrategyMode.paperOnly.rawValue
                    ]
                )
            }
            strategyStatusMessage =
                "Deterministic Local Paper cycle completed through the NDJSON protocol and execution gateway."
            latestStrategyAlert =
                "Local Paper intents were risk-checked, filled, allocated, and reconciled without invoking Longbridge CLI."
            try processOfficialLocalPaperIntents(
                strategy: strategy,
                records: result.intents
            )
            appendAudit(
                action: "PaperStrategyCycleCompleted",
                context: [
                    "strategy_id": strategy.strategyId,
                    "cycle_id": result.cycle.cycleId,
                    "intent_count": String(result.intents.count),
                    "live_submission_attempts": String(
                        services.liveBrokerAdapter.submissionAttempts
                    )
                ],
                category: .strategyLifecycle
            )
        } catch {
            strategy.runtimeState = .rejected
            strategy.health = .unhealthy
            strategy.blocksNewRisk = true
            latestStrategyAlert =
                "Local Paper cycle rejected: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
        saveStrategy(strategy)
    }

    func runReconciliationDiagnostic() {
        let brokerPositions = Dictionary(
            grouping: executionState.ledgerPositions,
            by: \.symbol
        ).mapValues { positions in
            positions.map(\.virtualQuantity).reduce(0, +)
        }
        let result = services.reconciliation.reconcile(
            positions: executionState.ledgerPositions,
            brokerPositions: brokerPositions,
            correlationId: "diagnostic-local-paper",
            now: Date()
        )
        let mismatches = result.events.filter {
            $0.status == .mismatch
        }.count
        latestStrategyAlert = mismatches == 0
            ? "Local Paper reconciliation diagnostic passed without trading."
            : "Reconciliation diagnostic found \(mismatches) mismatch(es)."
        appendAudit(
            action: "LocalPaperReconciliationDiagnostic",
            context: [
                "mismatch_count": String(mismatches),
                "trading_action": "false"
            ],
            category: .reconciliation
        )
    }

    func applyParameterChange(_ parameter: StrategyParameterModel) {
        guard let strategy = selectedStrategy else { return }
        let decision = services.parameterGovernance.requestChange(
            strategyId: strategy.strategyId,
            definition: parameter.definition,
            oldValue: parameter.value,
            newValue: parameter.draftValue,
            currentVersion: strategy.parameterVersion,
            requestedBy: "local-user",
            confirmed: parameter.confirmationChecked,
            requestedAt: Date()
        )
        try? services.strategyStore.appendParameterChange(decision.change)
        if parameter.confirmationChecked {
            strategy.parameterChanges.removeAll {
                $0.parameterKey == parameter.key &&
                    $0.result == .pendingConfirmation
            }
        }
        strategy.parameterChanges.insert(decision.change, at: 0)
        parameter.previewText = decision.impactPreview
        parameter.status = decision.change.result.rawValue
        strategy.blocksNewRisk = decision.blocksNewRisk
        if decision.change.result == .applied {
            parameter.value = decision.change.newValue
            strategy.parameterVersion = decision.change.parameterVersion
        } else if decision.change.result == .pendingSafeBoundary {
            strategy.runtimeState = .paused
        }
        parameter.confirmationChecked = false
        saveStrategy(strategy)
        appendAudit(
            action: "StrategyParameterChange",
            context: [
                "change_id": decision.change.changeId,
                "strategy_id": decision.change.strategyId,
                "parameter_key": decision.change.parameterKey,
                "old_value": decision.change.oldValue,
                "new_value": decision.change.newValue,
                "requested_at": ISO8601DateFormatter().string(
                    from: decision.change.requestedAt
                ),
                "effective_at": decision.change.effectiveAt.map {
                    ISO8601DateFormatter().string(from: $0)
                } ?? "",
                "requested_by": decision.change.requestedBy,
                "risk_tier": decision.change.riskTier.rawValue,
                "parameter_version": String(
                    decision.change.parameterVersion
                ),
                "activation_mode":
                    decision.change.activationMode.rawValue,
                "result": decision.change.result.rawValue,
                "rollback_version": String(
                    decision.change.rollbackVersion
                )
            ],
            category: .settings
        )
    }

    func requestLiveMode() {
        guard let strategy = selectedStrategy else { return }
        let authorization = try? services.strategyStore
            .loadLiveAuthorizations()
            .first { $0.strategyId == strategy.strategyId }
        let result = services.strategyModeService.selectMode(
            requestedMode: .live,
            globalLiveLock: globalLiveLock,
            manifest: strategy.manifest,
            parameterVersion: strategy.parameterVersion,
            authorization: authorization,
            market: defaultMarket,
            now: Date()
        )
        strategy.mode = result.mode
        strategyStatusMessage = result.message
        latestStrategyAlert = result.accepted
            ? "Live selected, but the Longbridge adapter remains intentionally rejecting."
            : result.message
        saveStrategy(strategy)
        appendModeAudit(strategy: strategy, result: result)
    }

    func requestPaperMode() {
        guard let strategy = selectedStrategy else { return }
        let wasLive = strategy.mode == .live
        let result = services.strategyModeService.selectMode(
            requestedMode: .paperOnly,
            globalLiveLock: globalLiveLock,
            manifest: strategy.manifest,
            parameterVersion: strategy.parameterVersion,
            authorization: nil,
            market: defaultMarket,
            now: Date()
        )
        strategy.mode = .paperOnly
        strategy.liveToPaperTransition = selectedTransition
        strategy.blocksNewRisk = true
        if selectedTransition == .freeze {
            strategy.runtimeState = .paused
        }
        switch selectedTransition {
        case .stopOpeningRisk:
            latestStrategyAlert =
                "Local Paper: new risk is blocked while existing virtual positions remain manageable."
        case .freeze:
            latestStrategyAlert =
                "Local Paper: the strategy is frozen and no order was generated."
        case .controlledExit:
            latestStrategyAlert =
                "Local Paper: controlled exit policy is ready."
        }
        if wasLive && selectedTransition == .controlledExit {
            do {
                try runControlledLocalPaperExit(strategy: strategy)
            } catch {
                latestStrategyAlert =
                    "Local Paper controlled exit failed safely: \(SensitiveDataRedactor.redact(error.localizedDescription))"
            }
        }
        strategyStatusMessage = result.message
        saveStrategy(strategy)
        appendModeAudit(strategy: strategy, result: result)
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

    private func initializeExecution() {
        do {
            executionState = try services.executionStore.loadExecutionState()
            if executionState.intents.isEmpty &&
                executionState.ledgerPositions.isEmpty {
                let fixture = try services.executionFixtures
                    .loadPaperGatewayFixture()
                var seeded = ExecutionStateSnapshot.empty
                seeded.ledgerPositions = fixture.startingLedger.map {
                    VirtualLedgerPosition(
                        schemaVersion: 1,
                        strategyId: $0.strategyId,
                        symbol: fixture.symbol,
                        targetPosition: $0.virtualQuantity,
                        virtualQuantity: $0.virtualQuantity,
                        costBasis: $0.costBasis,
                        realizedPnl: 0,
                        unrealizedPnl:
                            (fixture.referencePrice - $0.costBasis) *
                            $0.virtualQuantity,
                        capitalUsage:
                            $0.virtualQuantity * fixture.referencePrice,
                        riskContribution: 0,
                        intentIds: [],
                        allocationIds: [],
                        internalTransferIds: [],
                        updatedAt: fixture.asOf
                    )
                }
                try services.executionStore.saveExecutionState(seeded)
                let contexts = Dictionary(
                    uniqueKeysWithValues: Set(
                        fixture.intents.map(\.strategyId)
                    ).map {
                        (
                            $0,
                            localPaperContext(
                                market: fixture.market,
                                now: fixture.asOf,
                                capitalBudget: 1_000_000,
                                parameterVersion: 1
                            )
                        )
                    }
                )
                let result = try services.executionGateway.process(
                    intents: fixture.intents,
                    contexts: contexts,
                    referencePrice: fixture.referencePrice,
                    referencePriceSource:
                        fixture.referencePriceSource,
                    paperConfiguration: PaperBrokerConfiguration(
                        fillRatio: fixture.paperFillRatio,
                        slippageBasisPoints: 2,
                        feePerUnit: 0.005,
                        minimumFee: 0.25,
                        rejectOrders: false,
                        expireOrders: false
                    ),
                    liveConfiguration:
                        try rejectingLiveConfiguration(),
                    brokerPositions: [
                        fixture.symbol:
                            fixture.startingBrokerQuantity
                    ]
                )
                executionState = result.state
            }
        } catch {
            latestStrategyAlert =
                "Local Paper fixture initialization failed safely: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
    }

    private func processOfficialLocalPaperIntents(
        strategy: StrategyItemModel,
        records: [StrategyIntentRecord]
    ) throws {
        guard !records.isEmpty else { return }
        let fixture = try services.executionFixtures
            .loadPaperGatewayFixture()
        let capitalBudget = max(strategy.capitalBudget, 100_000)
        let existing = Dictionary(
            uniqueKeysWithValues: executionState.ledgerPositions
                .filter { $0.strategyId == strategy.strategyId }
                .map { ($0.symbol, $0.virtualQuantity) }
        )
        let intents = records.compactMap { record -> TradeIntent? in
            let desired =
                capitalBudget * record.targetWeight /
                fixture.referencePrice
            let requested = desired - (existing[record.symbol] ?? 0)
            guard abs(requested) > 0.0001 else { return nil }
            return TradeIntent(
                schemaVersion: 1,
                intentId: record.intentId,
                strategyId: strategy.strategyId,
                strategyVersion: strategy.manifest.version,
                cycleId: record.cycleId,
                settlementCycle:
                    "\(defaultMarket)-\(Self.dayString(record.timestamp))",
                symbol: record.symbol,
                requestedQuantity:
                    (requested * 10_000).rounded() / 10_000,
                priority: record.priority,
                allowPartial: record.allowPartial,
                minimumEffectiveFill: 0.0001,
                timeToLiveSeconds: 60,
                reasonCode: record.reasonCode,
                parameterVersion: strategy.parameterVersion,
                createdAt: record.timestamp
            )
        }
        guard !intents.isEmpty else { return }
        let brokerPositions = Dictionary(
            grouping: executionState.ledgerPositions,
            by: \.symbol
        ).mapValues { $0.map(\.virtualQuantity).reduce(0, +) }
        let now = Date()
        let result = try services.executionGateway.process(
            intents: intents,
            contexts: [
                strategy.strategyId: localPaperContext(
                    market: defaultMarket,
                    now: now,
                    capitalBudget: capitalBudget,
                    parameterVersion: strategy.parameterVersion,
                    transitionActive: strategy.blocksNewRisk,
                    transitionPolicy:
                        strategy.liveToPaperTransition
                )
            ],
            referencePrice: fixture.referencePrice,
            referencePriceSource: fixture.referencePriceSource,
            paperConfiguration: PaperBrokerConfiguration(
                fillRatio: 1,
                slippageBasisPoints: 2,
                feePerUnit: 0.005,
                minimumFee: 0.25,
                rejectOrders: false,
                expireOrders: false
            ),
            liveConfiguration: try rejectingLiveConfiguration(),
            brokerPositions: brokerPositions
        )
        executionState = result.state
    }

    private func localPaperContext(
        market: String,
        now: Date,
        capitalBudget: Double,
        parameterVersion: Int,
        transitionActive: Bool = false,
        transitionPolicy: LiveToPaperTransition = .stopOpeningRisk
    ) -> ExecutionGatewayContext {
        ExecutionGatewayContext(
            mode: .paperOnly,
            globalLiveLock: false,
            authorization: nil,
            dataFresh: true,
            marketAllowed: true,
            strategyHealth: .healthy,
            capitalBudget: capitalBudget,
            maximumPositionExposure: capitalBudget,
            cliReady: false,
            liveAdapterEnabled: false,
            fixtureMode: true,
            parameterVersion: parameterVersion,
            market: market,
            now: now,
            dailyLoss: 0,
            drawdown: 0,
            outsideRegularHours: false,
            transitionActive: transitionActive,
            transitionPolicy: transitionPolicy
        )
    }

    private func runControlledLocalPaperExit(
        strategy: StrategyItemModel
    ) throws {
        let positions = executionState.ledgerPositions.filter {
            $0.strategyId == strategy.strategyId &&
                $0.virtualQuantity != 0
        }
        guard !positions.isEmpty else {
            latestStrategyAlert =
                "Local Paper controlled exit completed with no virtual position to close."
            return
        }
        let fixture = try services.executionFixtures
            .loadPaperGatewayFixture()
        let now = Date()
        let cycleId =
            "local-paper-controlled-exit-\(Int(now.timeIntervalSince1970 * 1000))"
        let intents = positions.enumerated().map { index, position in
            TradeIntent(
                schemaVersion: 1,
                intentId: "\(cycleId)-\(index + 1)",
                strategyId: strategy.strategyId,
                strategyVersion: strategy.manifest.version,
                cycleId: cycleId,
                settlementCycle:
                    "\(defaultMarket)-\(Self.dayString(now))",
                symbol: position.symbol,
                requestedQuantity: -position.virtualQuantity,
                priority: Int.max - index,
                allowPartial: false,
                minimumEffectiveFill:
                    abs(position.virtualQuantity),
                timeToLiveSeconds: 60,
                reasonCode:
                    "live_to_local_paper_controlled_exit",
                parameterVersion: strategy.parameterVersion,
                createdAt: now
            )
        }
        let brokerPositions = Dictionary(
            grouping: executionState.ledgerPositions,
            by: \.symbol
        ).mapValues { $0.map(\.virtualQuantity).reduce(0, +) }
        let exposure = positions.map {
            abs($0.virtualQuantity) * fixture.referencePrice
        }.reduce(0, +)
        let result = try services.executionGateway.process(
            intents: intents,
            contexts: [
                strategy.strategyId: localPaperContext(
                    market: defaultMarket,
                    now: now,
                    capitalBudget: max(exposure, 1),
                    parameterVersion: strategy.parameterVersion,
                    transitionActive: true,
                    transitionPolicy: .controlledExit
                )
            ],
            referencePrice: fixture.referencePrice,
            referencePriceSource: fixture.referencePriceSource,
            paperConfiguration: PaperBrokerConfiguration(
                fillRatio: 1,
                slippageBasisPoints: 2,
                feePerUnit: 0.005,
                minimumFee: 0.25,
                rejectOrders: false,
                expireOrders: false
            ),
            liveConfiguration: try rejectingLiveConfiguration(),
            brokerPositions: brokerPositions
        )
        executionState = result.state
        latestStrategyAlert =
            "Local Paper controlled exit generated policy intents, simulated fills, and reconciled the virtual ledger. No real order was sent."
    }

    private func rejectingLiveConfiguration() throws
        -> LiveAdapterConfiguration {
        LiveAdapterConfiguration(
            enabled: false,
            fixtureMode: true,
            executableURL: nil,
            timeout: 5,
            capability: try services.executionFixtures
                .loadExecutionCapability()
        )
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func initializeResearch() {
        do {
            let marketSnapshot = try services.fixtureDataService
                .loadFixtureSnapshot()
            let dataset = try services.researchFixtures.buildDataset(
                from: marketSnapshot
            )
            researchDataset = dataset
            var definitions = try services.factorResearchStore
                .loadFactorDefinitions()
            if definitions.isEmpty {
                definitions = try services.researchFixtures
                    .loadFactorDefinitions()
                try services.factorResearchStore.saveFactorDefinitions(
                    definitions
                )
            }
            let trials = try services.factorResearchStore.loadFactorTrials(
                limit: 200
            )
            researchFactors = services.factorSearch.initialSummaries(
                definitions: definitions,
                trials: trials
            )
            recentFactorTrials = Array(trials.reversed())

            let fixture = try services.researchFixtures
                .loadRegimeAllocationFixture()
            let regime = services.regimeEngine.evaluate(
                fixture.regimeInput,
                asOf: dataset.createdAt
            )
            regimeSnapshot = regime
            let allocation = services.capitalAllocator.allocate(
                totalCapital: fixture.totalCapital,
                baseRiskFraction: fixture.baseRiskFraction,
                regime: regime,
                strategies: fixture.strategies
            )
            capitalAllocation = allocation
            applyCapitalAllocations(allocation.allocations)
        } catch {
            factorSearchStatus =
                "Research initialization failed: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
    }

    private func applyCapitalAllocations(
        _ allocations: [StrategyCapitalAllocation]
    ) {
        let indexed = Dictionary(
            uniqueKeysWithValues: allocations.map {
                ($0.strategyId, $0)
            }
        )
        for strategy in strategies {
            guard let allocation = indexed[strategy.strategyId] else {
                continue
            }
            strategy.capitalBudget = allocation.capitalBudget
            strategy.capitalAllocationExplanation =
                allocation.explanationText
        }
    }

    private func initializeStrategies() {
        do {
            let official = try services.strategyRegistry.loadOfficial()
            let states = Dictionary(
                uniqueKeysWithValues: (
                    try? services.strategyStore.loadStrategyStates()
                )?.map { ($0.strategyId, $0) } ?? []
            )
            let officialState = states[official.manifest.strategyId] ??
                defaultStrategyState(
                    manifest: official.manifest,
                    parameters: official.parameters
                )
            try services.strategyStore.saveStrategyManifest(
                official.manifest
            )
            try services.strategyStore.saveStrategyState(officialState)
            if (try services.strategyStore.loadLiveAuthorizations()).isEmpty {
                let fixture = try services.strategyRegistry
                    .loadAuthorizationFixture("valid-live-authorization")
                try services.strategyStore.saveLiveAuthorization(fixture)
            }
            let officialItem = StrategyItemModel(
                manifest: official.manifest,
                parameterSchema: official.parameters,
                state: officialState
            )
            officialItem.parameterChanges = (
                try? services.strategyStore.loadParameterChanges(
                    strategyId: officialItem.strategyId,
                    limit: 50
                )
            ) ?? []
            strategies = [officialItem]

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let manifests = (
                try? services.strategyStore.loadStrategyManifests()
            ) ?? []
            for manifest in manifests
                where manifest.source == .thirdParty {
                let schemaURL = URL(fileURLWithPath: manifest.parameterSchema)
                guard let parameters = try? decoder.decode(
                    StrategyParameterSchema.self,
                    from: Data(contentsOf: schemaURL)
                ),
                services.strategyRegistry.validate(
                    manifest: manifest,
                    parameters: parameters,
                    existingStrategyIds: Set(strategies.map(\.strategyId)),
                    manifestDirectory: schemaURL.deletingLastPathComponent()
                ) == nil else {
                    continue
                }
                let state = states[manifest.strategyId] ??
                    defaultStrategyState(
                        manifest: manifest,
                        parameters: parameters
                    )
                let item = StrategyItemModel(
                    manifest: manifest,
                    parameterSchema: parameters,
                    state: state
                )
                item.parameterChanges = (
                    try? services.strategyStore.loadParameterChanges(
                        strategyId: item.strategyId,
                        limit: 50
                    )
                ) ?? []
                strategies.append(item)
            }
            selectedStrategyID = strategies.first?.strategyId ?? ""
        } catch {
            strategyStatusMessage =
                "Strategy registry initialization failed: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
    }

    private func defaultStrategyState(
        manifest: StrategyManifest,
        parameters: StrategyParameterSchema
    ) -> StrategyPersistentState {
        StrategyPersistentState(
            strategyId: manifest.strategyId,
            mode: .paperOnly,
            runtimeState: .stopped,
            health: .degraded,
            lastHeartbeat: nil,
            parameterVersion: 1,
            parameterValues: Dictionary(
                uniqueKeysWithValues: parameters.parameters.map {
                    ($0.key, $0.defaultValue)
                }
            ),
            blocksNewRisk: false,
            liveToPaperTransition: .stopOpeningRisk
        )
    }

    private func saveStrategy(_ strategy: StrategyItemModel) {
        try? services.strategyStore.saveStrategyState(
            strategy.persistentState()
        )
        objectWillChange.send()
    }

    private func applyPendingParameterChanges(
        _ strategy: StrategyItemModel
    ) {
        let pending = strategy.parameterChanges.filter {
            $0.result == .pendingCycle ||
                $0.result == .pendingSafeBoundary
        }
        for change in pending.sorted(by: {
            $0.requestedAt < $1.requestedAt
        }) {
            let applied = services.parameterGovernance.applyBoundary(
                change,
                effectiveAt: Date()
            )
            try? services.strategyStore.appendParameterChange(applied)
            guard let parameter = strategy.parameters.first(where: {
                $0.key == applied.parameterKey
            }) else {
                continue
            }
            parameter.value = applied.newValue
            parameter.draftValue = applied.newValue
            parameter.status = applied.result.rawValue
            parameter.previewText =
                "Applied at the next safe cycle boundary."
            strategy.parameterVersion = max(
                strategy.parameterVersion,
                applied.parameterVersion
            )
            strategy.parameterChanges.removeAll { $0.id == change.id }
            strategy.parameterChanges.insert(applied, at: 0)
        }
        strategy.blocksNewRisk = strategy.parameterChanges.contains {
            $0.riskTier == .high &&
                ($0.result == .pendingConfirmation ||
                 $0.result == .pendingSafeBoundary)
        }
    }

    private func sendRuntimeControl(
        type: String,
        resultingState: StrategyRuntimeState
    ) {
        guard let strategy = selectedStrategy,
              let runtime = externalRuntimes[strategy.strategyId] else {
            strategyStatusMessage =
                "No third-party strategy process is running."
            return
        }
        do {
            try runtime.send(
                coreMessage(
                    strategy: strategy,
                    cycleId: "runtime-\(type)",
                    type: type,
                    payload: ["reason": "local_runtime_control"]
                )
            )
            strategy.runtimeState = resultingState
            strategyStatusMessage =
                "Strategy runtime received \(type)."
        } catch {
            strategy.runtimeState = .rejected
            strategyStatusMessage =
                "Runtime control failed: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
        saveStrategy(strategy)
    }

    private func coreMessage(
        strategy: StrategyItemModel,
        cycleId: String,
        type: String,
        payload: [String: String]
    ) -> StrategyMessageEnvelope {
        StrategyMessageEnvelope(
            schemaVersion: 1,
            eventId: UUID().uuidString,
            correlationId: UUID().uuidString,
            strategyId: strategy.strategyId,
            strategyVersion: strategy.manifest.version,
            cycleId: cycleId,
            timestamp: Date(),
            messageType: type,
            payload: payload
        )
    }

    private func handleExternalMessage(
        _ message: StrategyMessageEnvelope,
        strategy: StrategyItemModel
    ) {
        switch message.messageType {
        case "ready":
            strategy.runtimeState = .ready
        case "heartbeat":
            strategy.lastHeartbeat = message.timestamp
            strategy.health = .healthy
        case "health":
            strategy.health = HealthState(
                rawValue: message.payload["state"] ?? ""
            ) ?? .degraded
        case "log":
            appendLog(
                level: parseLogLevel(message.payload["level"]),
                module: message.payload["module"] ?? "ThirdPartyStrategy",
                message: message.payload["message"] ??
                    "Strategy log event.",
                strategyID: strategy.strategyId,
                correlationID: message.correlationId,
                cycleID: message.cycleId,
                context: ["message_type": message.messageType]
            )
        case "signal":
            if let score = Double(message.payload["score"] ?? "") {
                strategy.signals.insert(
                    StrategySignal(
                        symbol: message.payload["symbol"] ?? "",
                        score: score,
                        reason: message.payload["reason"] ?? "",
                        timestamp: message.timestamp
                    ),
                    at: 0
                )
            }
        case "target_position":
            if let weight = Double(
                message.payload["target_weight"] ?? ""
            ) {
                strategy.targets.insert(
                    StrategyTarget(
                        symbol: message.payload["symbol"] ?? "",
                        targetWeight: weight,
                        reason: message.payload["reason"] ?? "",
                        timestamp: message.timestamp
                    ),
                    at: 0
                )
            }
        case "trade_intent":
            let intent = StrategyIntentRecord(
                intentId: message.payload["intent_id"] ??
                    message.eventId,
                symbol: message.payload["symbol"] ?? "",
                targetWeight: Double(
                    message.payload["target_weight"] ?? ""
                ) ?? 0,
                priority: Int(message.payload["priority"] ?? "") ?? 0,
                allowPartial: Bool(
                    message.payload["allow_partial"] ?? ""
                ) ?? false,
                reasonCode: message.payload["reason_code"] ?? "",
                cycleId: message.cycleId,
                timestamp: message.timestamp,
                mode: strategy.mode
            )
            _ = services.strategyIntentRouter.route(
                mode: strategy.mode,
                intent: intent,
                liveAdapter: services.liveBrokerAdapter
            )
            strategy.intents.insert(intent, at: 0)
        case "cycle_complete":
            strategy.runtimeState = .running
            strategy.cycles.insert(
                StrategyCycleSummary(
                    cycleId: message.cycleId,
                    completedAt: message.timestamp,
                    signalCount: strategy.signals.count,
                    targetCount: strategy.targets.count,
                    intentCount: strategy.intents.count,
                    result: message.payload["result"] ?? "Completed"
                ),
                at: 0
            )
        case "error":
            strategy.runtimeState = .unhealthy
            strategy.health = .unhealthy
            strategy.blocksNewRisk = true
            latestStrategyAlert = SensitiveDataRedactor.redact(
                message.payload["message"] ?? "Strategy runtime error."
            )
        default:
            break
        }
        saveStrategy(strategy)
    }

    private func appendModeAudit(
        strategy: StrategyItemModel,
        result: ModeSelectionResult
    ) {
        appendAudit(
            action: "StrategyModeSelection",
            context: [
                "strategy_id": strategy.strategyId,
                "accepted": result.accepted ? "true" : "false",
                "mode": result.mode.rawValue,
                "live_lock": globalLiveLock ? "true" : "false",
                "live_submission_available": "false",
                "transition": strategy.liveToPaperTransition.rawValue
            ],
            category: result.accepted
                ? .strategyLifecycle
                : .riskRejection
        )
    }

    private func parseLogLevel(_ raw: String?) -> ApplicationLogLevel {
        guard let raw else { return .info }
        return ApplicationLogLevel(rawValue: raw.capitalized) ?? .info
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
            logRetentionDays: Int(logRetentionDays.rounded()),
            globalLiveLock: globalLiveLock
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
        strategyID: String? = nil,
        correlationID: String? = nil,
        cycleID: String? = nil,
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
            correlationID: correlationID,
            strategyID: strategyID,
            cycleID: cycleID,
            context: safeContext
        )
        try? services.logStore.appendLog(entry)
        applicationLogs.append(entry)
        if applicationLogs.count > 100 {
            applicationLogs.removeFirst(applicationLogs.count - 100)
        }
    }

    private func appendExistingLog(_ entry: ApplicationLogEntry) {
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

    private func appendAudit(
        action: String,
        context: [String: String],
        category: AuditEventCategory = .factorLifecycle
    ) {
        let correlationID = UUID().uuidString
        let event = AuditEvent(
            id: UUID().uuidString,
            occurredAt: Date(),
            category: category,
            action: action,
            result: .completed,
            actor: "local-user",
            correlationID: correlationID,
            context: context
        )
        try? services.auditStore.appendAuditEvent(event)
    }
}
