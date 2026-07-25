import AppKit
import SwiftUI

struct ProductLogoView: View {
    var body: some View {
        ZStack {
            Color(red: 0.004, green: 0.012, blue: 0.055)
            if let url = Bundle.main.url(forResource: "ProductLogo", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "moon.stars.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(.purple)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 0.7)
        )
        .shadow(color: .purple.opacity(0.35), radius: 10, y: 4)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ZStack {
            LiquidBackdrop()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 246)
                Divider().overlay(.white.opacity(0.08))
                Group {
                    switch model.selection {
                    case .overview: OverviewView()
                    case .factors: FactorsView()
                    case .lab: LabView()
                    case .data: DataUniverseView()
                    case .settings: SettingsView()
                    case .logs: LogsView()
                    case .privacy: PrivacyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ProductLogoView()
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cytisus-Trading")
                        .font(.headline.weight(.semibold))
                    Text("v1.1 Strategy Runtime")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 7) {
                ForEach(StudioSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { model.selection = section }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.symbol)
                                .frame(width: 21)
                            Text(section.rawValue)
                            Spacer()
                        }
                        .font(.subheadline.weight(model.selection == section ? .semibold : .regular))
                        .foregroundStyle(model.selection == section ? .white : .secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(
                            model.selection == section ? Color.white.opacity(0.105) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay {
                            if model.selection == section {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(.white.opacity(0.16), lineWidth: 0.7)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                Label("Data Mode", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text(model.fixtureModeStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 18)
        .padding(.top, 46)
        .padding(.bottom, 20)
        .background(.black.opacity(0.11))
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.cyan)
            Text(title)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PageHeader(
                        eyebrow: "Automated Operations",
                        title: "Dashboard",
                        subtitle: "Strategy runtime health, bounded modes, and deterministic Paper activity. Live broker submission is unavailable."
                    )
                    Spacer()
                    Button("Run Paper Cycle") {
                        model.runSelectedPaperCycle()
                    }
                        .buttonStyle(PrimaryGlassButton())
                }

                HStack(spacing: 16) {
                    MetricCard(title: "Paper Strategies", value: "\(model.paperStrategyCount)", detail: "Safe default", symbol: "doc.text.magnifyingglass", tint: .cyan)
                    MetricCard(title: "Live Selected", value: "\(model.liveStrategyCount)", detail: "Submission disabled", symbol: "lock.shield", tint: .orange)
                    MetricCard(title: "Healthy Runtimes", value: "\(model.healthyStrategyCount)", detail: "Heartbeat observed", symbol: "waveform.path.ecg", tint: .green)
                    MetricCard(title: "Global Live Lock", value: model.globalLiveLock ? "ON" : "OFF", detail: "OFF by default", symbol: "lock.fill", tint: .purple)
                }

                HStack(spacing: 16) {
                    MetricCard(title: "Trend", value: model.regimeTrendDisplay, detail: "Ensemble probability", symbol: "arrow.up.right", tint: .green)
                    MetricCard(title: "Range", value: model.regimeRangeDisplay, detail: "Ensemble probability", symbol: "arrow.left.and.right", tint: .cyan)
                    MetricCard(title: "High Volatility", value: model.regimeHighVolatilityDisplay, detail: "Ensemble probability", symbol: "waveform.path", tint: .orange)
                    MetricCard(title: "Crisis", value: model.regimeCrisisDisplay, detail: "Ensemble probability", symbol: "exclamationmark.triangle", tint: .red)
                }

                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Dynamic Capital Allocator").font(.headline)
                            Text(model.allocatorSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Uncertainty \(model.regimeUncertaintyDisplay)")
                            Text("Risk multiplier \(model.regimeRiskDisplay)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sample Strategy Path")
                                        .font(.headline)
                                    Text("Normalized research curve | Not actual returns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+6.8%")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            MiniPerformanceChart().frame(height: 170)
                            HStack {
                                Label("No real positions", systemImage: "lock.fill")
                                Spacer()
                                Text("Demo period: 12 sample windows")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Governance Summary").font(.headline)
                            SummaryRow(symbol: "checkmark.seal.fill", tint: .green, title: "Admission", detail: "Pass the OOS gate twice in sequence")
                            SummaryRow(symbol: "arrow.down.right.circle.fill", tint: .orange, title: "Downgrade", detail: "Two failures trigger probation")
                            SummaryRow(symbol: "archivebox.circle.fill", tint: .secondary, title: "Retirement", detail: "Three failures and a 126-day cooldown")
                            SummaryRow(symbol: "exclamationmark.shield.fill", tint: .red, title: "Quarantine", detail: "Stop immediately on look-ahead or source contamination")
                            Divider().overlay(.white.opacity(0.08))
                            Text("Return targets never influence factor promotion.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.cyan)
                        }
                    }
                    .frame(width: 330)
                }

                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Latest Strategy Cycle").font(.headline)
                            Text(model.latestCycleDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.latestStrategyAlert)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(34)
        }
    }
}

struct SummaryRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FactorsView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    PageHeader(
                        eyebrow: "Factor Governance",
                        title: "Research and Lifecycle",
                        subtitle: "Typed deterministic factors, retained trials, task evidence, neighboring-horizon stability, and governed lifecycle state."
                    )
                    Spacer()
                    Button("Run Tiny Fixture Search") {
                        model.runTinyFactorSearch()
                    }
                    .buttonStyle(PrimaryGlassButton())
                }

                Text(model.factorSearchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Factor").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Task").frame(width: 76, alignment: .leading)
                            Text("Horizon").frame(width: 64)
                            Text("Global").frame(width: 92, alignment: .leading)
                            Text("Strategy").frame(width: 92, alignment: .leading)
                            Text("Trials").frame(width: 48, alignment: .trailing)
                            Text("OOS evidence").frame(width: 170, alignment: .trailing)
                            Text("Marginal").frame(width: 72, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        Divider().overlay(.white.opacity(0.07))

                        ForEach(Array(model.researchFactors.enumerated()), id: \.element.id) { index, factor in
                            VStack(spacing: 0) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(factor.name.capitalized)
                                            .font(.subheadline.weight(.semibold))
                                        Text(factor.stateReason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(factor.definition.factorType.rawValue)
                                        .frame(width: 76, alignment: .leading)
                                    Text(factor.definition.horizon).frame(width: 64)
                                    StatusPill(state: factor.globalState)
                                        .frame(width: 92, alignment: .leading)
                                    StatusPill(state: factor.strategyState)
                                        .frame(width: 92, alignment: .leading)
                                    Text("\(factor.trialCount)")
                                        .frame(width: 48, alignment: .trailing)
                                    Text(factor.oosEvidence)
                                        .frame(width: 170, alignment: .trailing)
                                    Text(
                                        factor.evidence.marginalContribution.formatted(
                                            .number.precision(.fractionLength(3))
                                        )
                                    )
                                    .frame(width: 72, alignment: .trailing)
                                }
                                .font(.caption)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                if index < model.researchFactors.count - 1 {
                                    Divider().overlay(.white.opacity(0.055))
                                }
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Retained Trial Registry").font(.headline)
                        if model.recentFactorTrials.isEmpty {
                            Text("No research trials have run. Definitions remain fixture-backed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.recentFactorTrials.prefix(12)) { trial in
                            HStack {
                                Text(trial.factorFamily)
                                    .frame(width: 180, alignment: .leading)
                                Text(trial.result.rawValue)
                                    .foregroundStyle(
                                        trial.result == .candidate
                                            ? .green
                                            : trial.result == .quarantined
                                                ? .red
                                                : .orange
                                    )
                                    .frame(width: 90, alignment: .leading)
                                Text(trial.expression)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(trial.rejectionReason ?? "Passed current candidate gates")
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 280, alignment: .leading)
                            }
                            .font(.caption)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.cyan)
                    Text("Every attempted candidate is retained. Quarantine is global; regime-specific weakness contracts affected strategy risk without globally retiring the factor.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(34)
        }
    }
}

struct LabView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Local Strategy Runtime",
                    title: "Strategies",
                    subtitle: "Register governed strategy processes, edit schema-defined parameters, and inspect Paper outcomes. No manual execution controls are provided."
                )

                HStack(alignment: .top, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Strategy Registry").font(.headline)
                            Picker(
                                "Strategy",
                                selection: $model.selectedStrategyID
                            ) {
                                ForEach(model.strategies) { strategy in
                                    Text(strategy.name)
                                        .tag(strategy.strategyId)
                                }
                            }
                            .labelsHidden()
                            TextField(
                                "Local third-party manifest path",
                                text: $model.strategyManifestPath
                            )
                            .textFieldStyle(.roundedBorder)
                            Button("Validate and Register") {
                                model.registerThirdPartyStrategy()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(width: 330)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Mode Governance").font(.headline)
                            HStack {
                                Button("Use Paper Only") {
                                    model.requestPaperMode()
                                }
                                .buttonStyle(PrimaryGlassButton())
                                Button("Request Live") {
                                    model.requestLiveMode()
                                }
                                .buttonStyle(.bordered)
                            }
                            Picker(
                                "Live-to-Paper transition",
                                selection: $model.selectedTransition
                            ) {
                                ForEach(LiveToPaperTransition.allCases) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            Text(model.globalLiveLockStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.liveAuthorizationSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider().overlay(.white.opacity(0.08))
                            Text(model.strategyStatusMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(model.latestStrategyAlert)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let strategy = model.selectedStrategy {
                    StrategyDetailView(strategy: strategy)
                }
            }
            .padding(34)
        }
    }
}

struct StrategyDetailView: View {
    @EnvironmentObject private var model: StudioModel
    @ObservedObject var strategy: StrategyItemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(strategy.name).font(.headline)
                            Text(
                                "\(strategy.sourceLabel) | \(strategy.manifest.version) | \(strategy.runtimeState.rawValue) | \(strategy.health.rawValue)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(strategy.lastHeartbeatDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Capital budget \(strategy.capitalBudgetDisplay)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)
                            Text(strategy.capitalAllocationExplanation)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        HStack {
                            Button("Start") { model.startSelectedStrategy() }
                            Button("Pause") { model.pauseSelectedStrategy() }
                            Button("Resume") { model.resumeSelectedStrategy() }
                            Button("Stop") { model.stopSelectedStrategy() }
                            Button("Run Paper Cycle") {
                                model.runSelectedPaperCycle()
                            }
                            .buttonStyle(PrimaryGlassButton())
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schema-Generated Parameters").font(.headline)
                    ForEach(strategy.parameters) { parameter in
                        StrategyParameterEditor(parameter: parameter)
                        if parameter.id != strategy.parameters.last?.id {
                            Divider().overlay(.white.opacity(0.06))
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                StrategyObservationCard(
                    title: "Signals",
                    values: strategy.signals.map {
                        "\($0.symbol) | \($0.score.formatted(.number.precision(.fractionLength(3))))"
                    }
                )
                StrategyObservationCard(
                    title: "Targets",
                    values: strategy.targets.map {
                        "\($0.symbol) | \($0.targetWeight.formatted(.percent.precision(.fractionLength(1))))"
                    }
                )
                StrategyObservationCard(
                    title: "Intent History",
                    values: strategy.intents.map {
                        "\($0.symbol) | \($0.reasonCode) | \($0.mode.rawValue)"
                    }
                )
            }
        }
    }
}

struct StrategyParameterEditor: View {
    @EnvironmentObject private var model: StudioModel
    @ObservedObject var parameter: StrategyParameterModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(parameter.label).font(.subheadline.weight(.semibold))
                Text(parameter.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(parameter.rangeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 260, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("Risk: \(parameter.riskTierLabel)")
                Text("Apply: \(parameter.activationLabel)")
                Text("Status: \(parameter.status)")
            }
            .font(.caption)
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                TextField("Value", text: $parameter.draftValue)
                    .textFieldStyle(.roundedBorder)
                Toggle(
                    "Confirm high-risk change",
                    isOn: $parameter.confirmationChecked
                )
                .font(.caption)
                Text(parameter.previewText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply Change") {
                model.applyParameterChange(parameter)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct StrategyObservationCard: View {
    let title: String
    let values: [String]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                if values.isEmpty {
                    Text("No observations yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(values.prefix(6).enumerated()), id: \.offset) {
                        Text($0.element)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DataUniverseView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    PageHeader(
                        eyebrow: "Read-only Market Operations",
                        title: "Data and Universe",
                        subtitle: "Capability-aware CLI inspection, point-in-time market data, local cache state, and daily universe decisions."
                    )
                    Spacer()
                    Button("Check Data") { model.refreshLongbridge() }
                        .buttonStyle(PrimaryGlassButton())
                }

                HStack(spacing: 14) {
                    MetricCard(
                        title: "CLI State",
                        value: model.cliStatusState.rawValue,
                        detail: model.cliVersion,
                        symbol: "terminal",
                        tint: model.cliStatusState == .ready ? .green : .orange
                    )
                    MetricCard(
                        title: "Last Check",
                        value: model.lastCheckDisplay,
                        detail: model.cliStatusMessage,
                        symbol: "clock",
                        tint: .cyan
                    )
                    MetricCard(
                        title: "Data Freshness",
                        value: model.dataFreshnessDisplay,
                        detail: "Market: \(model.marketSession)",
                        symbol: "waveform.path.ecg",
                        tint: .purple
                    )
                    MetricCard(
                        title: "Local Cache",
                        value: model.cacheSizeDisplay,
                        detail: "Stable JSON cache keys",
                        symbol: "externaldrive",
                        tint: .blue
                    )
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Available Data Permissions")
                            .font(.headline)
                        Text(model.dataPermissionsSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("CLI path: \(model.cliPathDisplay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Raw authentication output is never written to logs.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Symbol").frame(width: 100, alignment: .leading)
                            Text("Decision").frame(width: 100, alignment: .leading)
                            Text("Reason").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Industry").frame(width: 150, alignment: .leading)
                            Text("Last").frame(width: 72, alignment: .trailing)
                            Text("History").frame(width: 62, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)

                        Divider().overlay(.white.opacity(0.07))

                        ForEach(Array(model.universeEntries.enumerated()), id: \.element.id) { index, entry in
                            VStack(spacing: 0) {
                                HStack {
                                    Text(entry.symbol)
                                        .frame(width: 100, alignment: .leading)
                                    Text(entry.dispositionLabel)
                                        .foregroundStyle(
                                            entry.disposition == .included
                                                ? .green
                                                : entry.disposition == .reduceOnly
                                                    ? .orange
                                                    : .secondary
                                        )
                                        .frame(width: 100, alignment: .leading)
                                    Text(entry.reason)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.industry)
                                        .frame(width: 150, alignment: .leading)
                                    Text(
                                        entry.liquidityMetrics.lastPrice,
                                        format: .number.precision(.fractionLength(2))
                                    )
                                    .frame(width: 72, alignment: .trailing)
                                    Text("\(entry.dataCoverage.historyCoverageDays)")
                                        .frame(width: 62, alignment: .trailing)
                                }
                                .font(.system(.caption, design: .rounded))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                if index < model.universeEntries.count - 1 {
                                    Divider()
                                        .overlay(.white.opacity(0.055))
                                        .padding(.leading, 18)
                                }
                            }
                        }
                    }
                }
            }
            .padding(34)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "Local Data Configuration",
                    title: "Settings",
                    subtitle: "Only non-sensitive CLI and cache preferences are stored. Authorization stays inside the user-installed CLI."
                )

                HStack(alignment: .top, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Longbridge CLI").font(.headline)
                            Toggle(
                                "Use deterministic fixture mode",
                                isOn: $model.fixtureMode
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Executable path")
                                    .font(.caption.weight(.semibold))
                                TextField(
                                    "Leave blank to use the system PATH",
                                    text: $model.cliExecutablePath
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Default market")
                                    .font(.caption.weight(.semibold))
                                TextField("US", text: $model.defaultMarket)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Label(
                                "No broker token, secret, or authorization code is requested or stored.",
                                systemImage: "checkmark.shield.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Cache and Retention").font(.headline)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cache directory")
                                    .font(.caption.weight(.semibold))
                                TextField(
                                    "Local cache directory",
                                    text: $model.cacheDirectory
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                            SettingSlider(
                                title: "Process timeout",
                                display: model.processTimeoutDisplay,
                                value: $model.processTimeoutSeconds,
                                range: 2...120
                            )
                            SettingSlider(
                                title: "Data retention",
                                display: model.dataRetentionDisplay,
                                value: $model.dataRetentionDays,
                                range: 7...365
                            )
                            SettingSlider(
                                title: "Log retention",
                                display: model.logRetentionDisplay,
                                value: $model.logRetentionDays,
                                range: 7...180
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Global Live Lock").font(.headline)
                        Toggle(
                            "Enable bounded Live mode selection",
                            isOn: $model.globalLiveLock
                        )
                        Text(model.globalLiveLockStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            "Live broker submission remains disabled in this implementation pass."
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                GlassCard {
                    Text(model.fixtureModeStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(34)
        }
    }
}

struct SettingSlider: View {
    let title: String
    let display: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(display)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            Slider(value: $value, in: range, step: 1)
                .tint(.cyan)
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                eyebrow: "Structured Operations",
                title: "Logs",
                subtitle: "CLI logs contain bounded outcomes and read-only categories, never raw authentication output."
            )

            HStack {
                TextField(
                    "Search message, module, strategy, correlation, or cycle",
                    text: $model.logSearchText
                )
                .textFieldStyle(.roundedBorder)
                Picker(
                    "Severity",
                    selection: $model.selectedLogSeverity
                ) {
                    Text("All").tag(nil as ApplicationLogLevel?)
                    ForEach(
                        [
                            ApplicationLogLevel.debug,
                            .info,
                            .warning,
                            .error,
                            .critical
                        ],
                        id: \.rawValue
                    ) { severity in
                        Text(severity.rawValue)
                            .tag(Optional(severity))
                    }
                }
                .frame(width: 180)
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Time").frame(width: 150, alignment: .leading)
                        Text("Severity").frame(width: 80, alignment: .leading)
                        Text("Module").frame(width: 110, alignment: .leading)
                        Text("Strategy").frame(width: 150, alignment: .leading)
                        Text("Correlation").frame(width: 140, alignment: .leading)
                        Text("Cycle").frame(width: 120, alignment: .leading)
                        Text("Message").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)

                    Divider().overlay(.white.opacity(0.07))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.filteredApplicationLogs) { entry in
                                HStack(alignment: .top) {
                                    Text(
                                        entry.timestamp.formatted(
                                            date: .omitted,
                                            time: .standard
                                        )
                                    )
                                    .frame(width: 150, alignment: .leading)
                                    Text(entry.severity.rawValue)
                                        .frame(width: 80, alignment: .leading)
                                    Text(entry.module)
                                        .frame(width: 110, alignment: .leading)
                                    Text(entry.strategyID ?? "")
                                        .frame(width: 150, alignment: .leading)
                                    Text(entry.correlationID ?? "")
                                        .frame(width: 140, alignment: .leading)
                                    Text(entry.cycleID ?? "")
                                        .frame(width: 120, alignment: .leading)
                                    Text(entry.message)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                Divider().overlay(.white.opacity(0.05))
                            }
                        }
                    }
                }
            }
        }
        .padding(34)
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Privacy by Design",
                    title: "Sanitized and self-contained",
                    subtitle: "The release contains no production account or personal data."
                )

                HStack(spacing: 16) {
                    PrivacyCard(symbol: "network.slash", title: "Fixture Mode Offline", detail: "Local CLI mode delegates read-only data access to the user-installed CLI")
                    PrivacyCard(symbol: "person.crop.circle.badge.xmark", title: "No Identity Data", detail: "No account numbers, user names, or device identifiers")
                    PrivacyCard(symbol: "key.slash", title: "No Secrets", detail: "No tokens, certificates, or environment variables")
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Release Boundary").font(.headline)
                        PrivacyLine(label: "Includes", value: "Native UI, fixture data, a read-only CLI adapter, local cache, and daily universe decisions")
                        PrivacyLine(label: "Excludes", value: "Broker credentials, order submission, real orders, P&L, and account bindings")
                        PrivacyLine(label: "Storage", value: "Non-sensitive settings, market cache, universe, logs, and audit data stay local")
                        PrivacyLine(label: "Trading", value: "No order, cancellation, account configuration, or fund-management interfaces")
                        Divider().overlay(.white.opacity(0.08))
                        Label("Suitable for demos, reviews, and UI prototyping. Not investment advice.", systemImage: "checkmark.shield.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(34)
        }
    }
}

struct PrivacyCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        GlassCard(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.cyan)
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PrivacyLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
                .frame(width: 58, alignment: .leading)
            Text(value).font(.subheadline).foregroundStyle(.white.opacity(0.86))
        }
    }
}
