import AppKit
import SwiftUI

private enum StrategyWorkspaceTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case factors = "Factors"
    case signals = "Signals"
    case portfolio = "Portfolio"
    case risk = "Risk"
    case execution = "Execution"
    case code = "Code"
    case parameters = "Parameters"
    case backtests = "Backtests"
    case versions = "Versions"

    var id: String { rawValue }
}

private struct QuantStrategyProject: Identifiable {
    let id: String
    let name: String
    let strategyType: String
    let version: Int
    let lifecycle: String
    let universe: String
    let timeframe: String
    let rebalance: String
    let lastBacktest: String
    let validation: String
    let modified: String
    let factors: String
    let signals: String
    let portfolio: String
    let risk: String
    let execution: String
    let code: String
    let parameters: String
    let versions: String
    let eligibility: String

    var agentPatchAllowed: Bool {
        lifecycle != "Active" && lifecycle != "Live"
    }

    static let samples = [
        QuantStrategyProject(
            id: "cross-sectional-multifactor",
            name: "Cross-Sectional Multi-Factor",
            strategyType: "Cross-sectional ranking",
            version: 18,
            lifecycle: "Candidate",
            universe: "Daily dynamic US liquid equities",
            timeframe: "Daily bars",
            rebalance: "Every 5 trading days",
            lastBacktest: "2026-07-24 18:10",
            validation: "OOS and regime checks passed",
            modified: "2026-07-24 18:26",
            factors: "Value, quality, momentum, liquidity, and volatility controls.",
            signals: "Winsorized z-scores combined by governed factor weights.",
            portfolio: "Risk-budgeted long-short targets with turnover and capacity limits.",
            risk: "Gross exposure, concentration, drawdown, liquidity, and regime gates.",
            execution: "Participation-limited VWAP child proposals through the Execution Gateway.",
            code: "Structured strategy modules: universe, factors, signals, portfolio, risk, and execution selection.",
            parameters: "Signal threshold 0.15; rebalance 5 days; gross exposure 0.60.",
            versions: "Baseline v17 versus Candidate v18. Candidate improves cost-adjusted OOS stability.",
            eligibility: "Candidate; eligible for Paper after approval."
        ),
        QuantStrategyProject(
            id: "momentum-regime",
            name: "Momentum Regime Strategy",
            strategyType: "Regime-aware trend",
            version: 7,
            lifecycle: "Shadow",
            universe: "Daily dynamic US ETFs",
            timeframe: "Daily bars",
            rebalance: "Daily",
            lastBacktest: "2026-07-23 21:42",
            validation: "Walk-forward complete; Shadow observation active",
            modified: "2026-07-24 09:15",
            factors: "Time-series momentum, realized volatility, and regime probability.",
            signals: "Regime-weighted trend score with uncertainty reduction.",
            portfolio: "Volatility-targeted allocation with instrument and sector caps.",
            risk: "Crisis de-risking, drawdown probation, and liquidity gates.",
            execution: "Arrival-price schedule selected; all orders remain gateway governed.",
            code: "Versioned local modules with deterministic parameter manifests.",
            parameters: "Lookback 126 days; target volatility 10%; crisis multiplier 0.25.",
            versions: "Baseline v6 versus Shadow v7. No direct mutation while Shadow is observed.",
            eligibility: "Shadow; Live eligibility requires observation completion and authorization."
        )
    ]
}

struct AlgorithmStudioView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var projects = QuantStrategyProject.samples
    @State private var selectedProjectID = QuantStrategyProject.samples[0].id
    @State private var selectedTab: StrategyWorkspaceTab = .overview
    @State private var agentRequest = ""
    @State private var proposedPatch =
        "No ProjectPatch has been proposed."
    @State private var validationPlan =
        "Backtest, walk-forward, regime, turnover, cost, and risk checks are required."
    @State private var costEstimate = "No model request has been made."
    @State private var comparison =
        "Select Compare Versions to review baseline versus candidate."
    @State private var isAgentBusy = false

    private var selectedProject: QuantStrategyProject {
        projects.first { $0.id == selectedProjectID } ?? projects[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Quantitative Strategy Development",
                    title: "Algorithm Studio",
                    subtitle: "Build, validate, compare, and govern quantitative strategy projects."
                )

                HStack {
                    Button("New Strategy") { createProject() }
                    Button("Open Project") { openProject() }
                    Button("Compare Versions") {
                        comparison = selectedProject.versions
                        selectedTab = .versions
                    }
                }

                GlassCard(padding: 16) {
                    Text(
                        "Project  >  Universe  >  Factors  >  Signals  >  Portfolio and Risk  >  Execution Logic  >  Backtest  >  Walk-forward Validation  >  Optimization or Training  >  Candidate  >  Paper  >  Shadow  >  Live Eligibility"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .fixedSize(horizontal: false, vertical: true)
                }

                strategyProjects

                HStack(alignment: .top, spacing: 16) {
                    strategyWorkspace
                        .frame(maxWidth: .infinity)
                    agentAssistant
                        .frame(width: 330)
                }

                HStack(alignment: .top, spacing: 16) {
                    GlassCard {
                        studioMetric(
                            title: "Latest Backtest",
                            value: selectedProject.lastBacktest,
                            detail: backtestSummary
                        )
                    }
                    GlassCard {
                        studioMetric(
                            title: "Walk-forward Validation",
                            value: selectedProject.validation,
                            detail: selectedProject.eligibility
                        )
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Jobs: Backtest / Optimization / Training")
                            .font(.headline)
                        quantJob(
                            name: "Walk-forward Backtest",
                            backend: preferredBackend,
                            progress: 0.62,
                            status: "Running"
                        )
                        quantJob(
                            name: "Parameter Optimization",
                            backend: "Generic CPU",
                            progress: 1,
                            status: "Complete"
                        )
                    }
                }
            }
            .padding(34)
        }
    }

    private var strategyProjects: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("Strategy Projects").font(.headline)
                ForEach(projects) { project in
                    Button {
                        selectedProjectID = project.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).fontWeight(.semibold)
                                Text(project.strategyType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("v\(project.version)")
                                .foregroundStyle(.cyan)
                            Text(project.lifecycle)
                                .foregroundStyle(.orange)
                                .frame(width: 80, alignment: .leading)
                            Text(project.modified)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(
                            selectedProjectID == project.id
                                ? Color.cyan.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var strategyWorkspace: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current Strategy").font(.headline)
                Text(
                    "\(selectedProject.name) v\(selectedProject.version) \(selectedProject.lifecycle)"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(StrategyWorkspaceTab.allCases) { tab in
                            Button(tab.rawValue) { selectedTab = tab }
                                .buttonStyle(.bordered)
                                .tint(selectedTab == tab ? .cyan : .gray)
                        }
                    }
                }

                Divider().overlay(.white.opacity(0.08))
                Text(selectedTab.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail(for: selectedTab))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 150, alignment: .topLeading)
            }
        }
    }

    private var agentAssistant: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Agent Assistant").font(.headline)
                Text("Operates only on the selected quantitative project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $agentRequest)
                    .font(.body)
                    .frame(minHeight: 76)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(.black.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button(isAgentBusy ? "Proposing..." : "Propose ProjectPatch") {
                    Task { await proposePatch() }
                }
                .disabled(
                    isAgentBusy ||
                    agentRequest.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    !selectedProject.agentPatchAllowed
                )
                Group {
                    Text("Proposed Patch").foregroundStyle(.cyan)
                    Text(proposedPatch)
                    Text("Validation Plan").foregroundStyle(.cyan)
                    Text(validationPlan)
                    Text("Cost Estimate").foregroundStyle(.cyan)
                    Text(costEstimate)
                }
                .font(.caption)
                Text("Active and Live versions cannot be modified directly.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var preferredBackend: String {
        model.computeDevices.first {
            $0.health == .ready && $0.type != .cpu
        }?.name ?? "Generic CPU"
    }

    private var backtestSummary: String {
        "Sharpe 1.42 | Max drawdown 8.1% | Estimated cost 17 bps"
    }

    private func detail(for tab: StrategyWorkspaceTab) -> String {
        switch tab {
        case .overview:
            return "Type: \(selectedProject.strategyType)\nUniverse: \(selectedProject.universe)\nTimeframe: \(selectedProject.timeframe)\nRebalance: \(selectedProject.rebalance)\nValidation: \(selectedProject.validation)"
        case .factors: return selectedProject.factors
        case .signals: return selectedProject.signals
        case .portfolio: return selectedProject.portfolio
        case .risk: return selectedProject.risk
        case .execution: return selectedProject.execution
        case .code: return selectedProject.code
        case .parameters: return selectedProject.parameters
        case .backtests:
            return "\(backtestSummary)\nLast backtest: \(selectedProject.lastBacktest)"
        case .versions:
            return "\(selectedProject.versions)\n\(comparison)"
        }
    }

    private func studioMetric(
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.cyan)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quantJob(
        name: String,
        backend: String,
        progress: Double,
        status: String
    ) -> some View {
        HStack {
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
            Text("Backend: \(backend)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 210, alignment: .leading)
            ProgressView(value: progress)
                .frame(width: 130)
            Text(status)
                .font(.caption)
                .foregroundStyle(.cyan)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func createProject() {
        let version = projects.count + 1
        let project = QuantStrategyProject(
            id: "untitled-\(version)",
            name: "Untitled Quant Strategy",
            strategyType: "Structured quantitative strategy",
            version: 1,
            lifecycle: "Candidate",
            universe: "Define a dynamic universe",
            timeframe: "Daily bars",
            rebalance: "Define a rebalance frequency",
            lastBacktest: "Not run",
            validation: "Validation required",
            modified: Date.now.formatted(date: .abbreviated, time: .shortened),
            factors: "Define governed factors.",
            signals: "Define signal combination logic.",
            portfolio: "Define portfolio construction.",
            risk: "Define risk gates.",
            execution: "Select an execution algorithm.",
            code: "No project code has been added.",
            parameters: "No structured parameters have been added.",
            versions: "Initial candidate version.",
            eligibility: "Not eligible until validation passes."
        )
        projects.append(project)
        selectedProjectID = project.id
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Quantitative Strategy Project"
        panel.allowedFileTypes = ["json", "yaml", "yml"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = QuantStrategyProject(
            id: "opened-\(url.lastPathComponent)",
            name: url.deletingPathExtension().lastPathComponent,
            strategyType: "Imported structured project",
            version: 1,
            lifecycle: "Candidate",
            universe: "Review imported universe",
            timeframe: "Review imported timeframe",
            rebalance: "Review imported rebalance",
            lastBacktest: "Not run in this session",
            validation: "Imported project requires validation",
            modified: Date.now.formatted(date: .abbreviated, time: .shortened),
            factors: "Review imported factor definitions.",
            signals: "Review imported signal logic.",
            portfolio: "Review imported portfolio construction.",
            risk: "Review imported risk gates.",
            execution: "Review imported execution selection.",
            code: url.path,
            parameters: "Review imported structured parameters.",
            versions: "Imported as a new Candidate reference.",
            eligibility: "Not eligible until local validation passes."
        )
        projects.append(project)
        selectedProjectID = project.id
    }

    private func proposePatch() async {
        guard selectedProject.agentPatchAllowed else {
            proposedPatch =
                "Direct changes are blocked for Active and Live strategies."
            return
        }
        isAgentBusy = true
        defer { isAgentBusy = false }
        do {
            proposedPatch = try await model.modelProviders.proposeProjectPatch(
                projectName: selectedProject.name,
                request: agentRequest
            )
            validationPlan =
                "Run backtest, walk-forward, regime, turnover, cost, and risk gates before creating a Candidate."
            costEstimate = model.agentCostLimitStatus
        } catch {
            proposedPatch =
                "Proposal failed: \(SensitiveDataRedactor.redact(error.localizedDescription))"
        }
    }
}

struct ComputeView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Local Quantitative Compute",
                    title: "Compute",
                    subtitle: "Manage local CPU, GPU, and NPU scheduling. Hardware appears in Algorithm Studio only as job metadata."
                )

                HStack(alignment: .top, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Compute Backends").font(.headline)
                            ForEach(model.computeDevices) { device in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name)
                                        Text(device.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(device.health.rawValue)
                                        .foregroundStyle(
                                            device.health == .ready
                                                ? Color.cyan : Color.secondary
                                        )
                                }
                            }
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Scheduling").font(.headline)
                            Picker(
                                "Scheduling policy",
                                selection: $model.computeSchedulingMode
                            ) {
                                ForEach(
                                    ComputeSchedulingMode.allCases,
                                    id: \.self
                                ) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            Text(
                                "Backtests, optimization, and training use a validated local backend with CPU fallback."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active Compute Jobs").font(.headline)
                        Text(
                            "\(model.localStudioState.jobs.count) persisted job record"
                        )
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                        Text(
                            "Backtest, optimization, and training jobs expose backend and progress as operational metadata."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(34)
        }
    }
}
