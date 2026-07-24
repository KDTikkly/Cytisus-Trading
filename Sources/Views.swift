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
                    Text("Offline Factor Lab")
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
                Label("Local Demo Mode", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text("No network | No accounts | No real orders")
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
                        eyebrow: "Research Workspace",
                        title: "Strategy status at a glance",
                        subtitle: "Sanitized sample data demonstrates the factor governance workflow."
                    )
                    Spacer()
                    Button("Run Sample Review") { model.runReview() }
                        .buttonStyle(PrimaryGlassButton())
                }

                HStack(spacing: 16) {
                    MetricCard(title: "Run Mode", value: "Offline", detail: "No account connections", symbol: "wifi.slash", tint: .cyan)
                    MetricCard(title: "Active Factors", value: "\(model.activeFactors)", detail: "Independent risk gates", symbol: "point.3.filled.connected.trianglepath.dotted", tint: .green)
                    MetricCard(title: "Weighted Coverage", value: model.weightedCoverage.formatted(.percent.precision(.fractionLength(0))), detail: "Minimum gate: 80%", symbol: "chart.dots.scatter", tint: .purple)
                    MetricCard(title: "Shadow Queue", value: "\(model.shadowFactors)", detail: "Awaiting OOS evidence", symbol: "eye.circle", tint: .orange)
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                PageHeader(
                    eyebrow: "Factor Governance",
                    title: "Factor Lifecycle",
                    subtitle: "Use frozen out-of-sample evidence to control admission, downgrade, and retirement."
                )
                Spacer()
                if let date = model.lastReview {
                    Text("Last review \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Reset") { model.resetDemo() }
                    .buttonStyle(.borderless)
                Button("Generate Review Proposal") { model.runReview() }
                    .buttonStyle(PrimaryGlassButton())
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Factor").frame(maxWidth: .infinity, alignment: .leading)
                        Text("State").frame(width: 120, alignment: .leading)
                        Text("IC").frame(width: 62, alignment: .trailing)
                        Text("IR").frame(width: 62, alignment: .trailing)
                        Text("Coverage").frame(width: 70, alignment: .trailing)
                        Text("Weight").frame(width: 70, alignment: .trailing)
                        Text("OOS").frame(width: 58, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    Divider().overlay(.white.opacity(0.07))

                    ForEach(Array(model.factors.enumerated()), id: \.element.id) { index, factor in
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Text(factor.name).font(.subheadline.weight(.semibold))
                                        Text(factor.category)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.cyan)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(.cyan.opacity(0.10), in: Capsule())
                                    }
                                    Text(factor.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                StatusPill(state: factor.state).frame(width: 120, alignment: .leading)
                                Text(factor.ic.formatted(.number.precision(.fractionLength(3)))).frame(width: 62, alignment: .trailing)
                                Text(factor.ir.formatted(.number.precision(.fractionLength(2)))).frame(width: 62, alignment: .trailing)
                                Text(factor.coverage.formatted(.percent.precision(.fractionLength(0)))).frame(width: 70, alignment: .trailing)
                                Text(factor.weight.formatted(.percent.precision(.fractionLength(0)))).frame(width: 70, alignment: .trailing)
                                Text("\(factor.evidenceWindows)").frame(width: 58, alignment: .trailing)
                            }
                            .font(.system(.subheadline, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            if index < model.factors.count - 1 {
                                Divider().overlay(.white.opacity(0.055)).padding(.leading, 18)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(.cyan)
                Text("Run the proposal twice to promote the shadow factor and retire the weak factor. Changes remain in local memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(34)
    }
}

struct LabView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Policy Lab",
                    title: "Strategy Lab",
                    subtitle: "Adjust demo thresholds and observe how governance rules constrain factors."
                )

                HStack(alignment: .top, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Governance Parameters").font(.headline)
                            ParameterSlider(
                                title: "Per-Trade Risk Budget",
                                detail: "Interface demonstration only",
                                value: $model.riskBudget,
                                range: 0.25...0.75,
                                display: { String(format: "%.2f%%", $0) }
                            )
                            ParameterSlider(
                                title: "Minimum Data Coverage",
                                detail: "No new risk below the gate",
                                value: $model.coverageGate,
                                range: 0.70...0.95,
                                display: { $0.formatted(.percent.precision(.fractionLength(0))) }
                            )
                            ParameterSlider(
                                title: "Single-Factor Weight Cap",
                                detail: "New factors still start at no more than 5%",
                                value: $model.maxFactorWeight,
                                range: 0.10...0.35,
                                display: { $0.formatted(.percent.precision(.fractionLength(0))) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Non-Negotiable Boundaries").font(.headline)
                            BoundaryRow(text: "At least 252 time-series observations")
                            BoundaryRow(text: "At least 6 frozen OOS windows")
                            BoundaryRow(text: "OOS degradation must remain controlled")
                            BoundaryRow(text: "Positive incremental contribution after costs")
                            BoundaryRow(text: "Missing values cannot be treated as neutral zero")
                            BoundaryRow(text: "Risk gates remain separate from alpha weights")
                            Divider().overlay(.white.opacity(0.08))
                            Label("This app does not execute trades", systemImage: "hand.raised.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(width: 350)
                }

                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Current Parameter Proposal").font(.headline)
                            Text("Coverage >= \(model.coverageGate.formatted(.percent.precision(.fractionLength(0)))) | Weight cap \(model.maxFactorWeight.formatted(.percent.precision(.fractionLength(0)))) | Risk budget \(String(format: "%.2f%%", model.riskBudget))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28)).foregroundStyle(.green)
                    }
                }
            }
            .padding(34)
        }
    }
}

struct ParameterSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(display(value))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            Slider(value: $value, in: range)
                .tint(.cyan)
        }
    }
}

struct BoundaryRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.88))
            .symbolRenderingMode(.hierarchical)
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
                    PrivacyCard(symbol: "network.slash", title: "No Network Requests", detail: "No market-data, broker, or analytics service connections")
                    PrivacyCard(symbol: "person.crop.circle.badge.xmark", title: "No Identity Data", detail: "No account numbers, user names, or device identifiers")
                    PrivacyCard(symbol: "key.slash", title: "No Secrets", detail: "No tokens, certificates, or environment variables")
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Release Boundary").font(.headline)
                        PrivacyLine(label: "Includes", value: "Native UI, demo factors, an offline state machine, and rule descriptions")
                        PrivacyLine(label: "Excludes", value: "Production code, positions, orders, P&L, account bindings, and access tokens")
                        PrivacyLine(label: "Storage", value: "No persistence by default; restart restores the built-in demo state")
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
