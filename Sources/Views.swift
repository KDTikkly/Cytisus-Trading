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
                    Text("离线因子实验室")
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
                Label("本地演示模式", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text("无网络 · 无账户 · 无真实订单")
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
                        title: "策略状态一目了然",
                        subtitle: "所有数据均为脱敏样例，仅用于展示因子治理流程。"
                    )
                    Spacer()
                    Button("运行样本评审") { model.runReview() }
                        .buttonStyle(PrimaryGlassButton())
                }

                HStack(spacing: 16) {
                    MetricCard(title: "运行模式", value: "离线", detail: "不连接任何账户", symbol: "wifi.slash", tint: .cyan)
                    MetricCard(title: "活跃因子", value: "\(model.activeFactors)", detail: "风险门控独立", symbol: "point.3.filled.connected.trianglepath.dotted", tint: .green)
                    MetricCard(title: "加权覆盖率", value: model.weightedCoverage.formatted(.percent.precision(.fractionLength(0))), detail: "最低门槛 80%", symbol: "chart.dots.scatter", tint: .purple)
                    MetricCard(title: "影子队列", value: "\(model.shadowFactors)", detail: "等待样本外证据", symbol: "eye.circle", tint: .orange)
                }

                HStack(spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("样本策略轨迹")
                                        .font(.headline)
                                    Text("归一化研究曲线 · 非实际收益")
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
                                Label("无真实持仓", systemImage: "lock.fill")
                                Spacer()
                                Text("演示区间：12 个样本窗口")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("治理摘要").font(.headline)
                            SummaryRow(symbol: "checkmark.seal.fill", tint: .green, title: "准入", detail: "连续两次通过 OOS 门槛")
                            SummaryRow(symbol: "arrow.down.right.circle.fill", tint: .orange, title: "降级", detail: "连续两次失败进入观察")
                            SummaryRow(symbol: "archivebox.circle.fill", tint: .secondary, title: "淘汰", detail: "三次失败并冷却 126 天")
                            SummaryRow(symbol: "exclamationmark.shield.fill", tint: .red, title: "隔离", detail: "前视或来源污染立即停止")
                            Divider().overlay(.white.opacity(0.08))
                            Text("收益目标永远不参与因子晋升。")
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
                    title: "因子生命周期",
                    subtitle: "以冻结样本外证据控制准入、降级与淘汰。"
                )
                Spacer()
                if let date = model.lastReview {
                    Text("最近评审 \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("重置") { model.resetDemo() }
                    .buttonStyle(.borderless)
                Button("生成评审提案") { model.runReview() }
                    .buttonStyle(PrimaryGlassButton())
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("因子").frame(maxWidth: .infinity, alignment: .leading)
                        Text("状态").frame(width: 105, alignment: .leading)
                        Text("IC").frame(width: 62, alignment: .trailing)
                        Text("IR").frame(width: 62, alignment: .trailing)
                        Text("覆盖").frame(width: 70, alignment: .trailing)
                        Text("权重").frame(width: 70, alignment: .trailing)
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
                                StatusPill(state: factor.state).frame(width: 105, alignment: .leading)
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
                Text("点击两次“生成评审提案”可看到影子因子晋升和弱因子淘汰。所有变化只存在于本地内存。")
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
                    title: "策略实验室",
                    subtitle: "调整演示门槛，观察治理规则如何约束因子。"
                )

                HStack(alignment: .top, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("治理参数").font(.headline)
                            ParameterSlider(
                                title: "单笔风险预算",
                                detail: "仅用于界面演示",
                                value: $model.riskBudget,
                                range: 0.25...0.75,
                                display: { String(format: "%.2f%%", $0) }
                            )
                            ParameterSlider(
                                title: "最低数据覆盖率",
                                detail: "低于门槛不新增风险",
                                value: $model.coverageGate,
                                range: 0.70...0.95,
                                display: { $0.formatted(.percent.precision(.fractionLength(0))) }
                            )
                            ParameterSlider(
                                title: "单因子权重上限",
                                detail: "新因子初始仍不超过 5%",
                                value: $model.maxFactorWeight,
                                range: 0.10...0.35,
                                display: { $0.formatted(.percent.precision(.fractionLength(0))) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("不可绕过的边界").font(.headline)
                            BoundaryRow(text: "至少 252 个时间序列观察")
                            BoundaryRow(text: "至少 6 个冻结 OOS 窗口")
                            BoundaryRow(text: "样本外退化率必须受控")
                            BoundaryRow(text: "成本后增量贡献为正")
                            BoundaryRow(text: "缺失值不能按中性 0 处理")
                            BoundaryRow(text: "风险门控与 Alpha 权重分离")
                            Divider().overlay(.white.opacity(0.08))
                            Label("本应用不提供交易执行", systemImage: "hand.raised.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(width: 350)
                }

                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("当前参数提案").font(.headline)
                            Text("覆盖率 ≥ \(model.coverageGate.formatted(.percent.precision(.fractionLength(0)))) · 权重上限 \(model.maxFactorWeight.formatted(.percent.precision(.fractionLength(0)))) · 风险预算 \(String(format: "%.2f%%", model.riskBudget))")
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
                    title: "已脱敏，自包含",
                    subtitle: "发行包不含任何生产账户或个人数据。"
                )

                HStack(spacing: 16) {
                    PrivacyCard(symbol: "network.slash", title: "无网络请求", detail: "没有行情、券商或分析服务连接")
                    PrivacyCard(symbol: "person.crop.circle.badge.xmark", title: "无身份信息", detail: "不含账户号、用户名或设备标识")
                    PrivacyCard(symbol: "key.slash", title: "无密钥", detail: "不含令牌、证书或环境变量")
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("发行边界").font(.headline)
                        PrivacyLine(label: "包含", value: "原生界面、演示因子、离线状态机、规则说明")
                        PrivacyLine(label: "不包含", value: "真实代码、真实持仓、订单、盈亏、账户绑定、访问令牌")
                        PrivacyLine(label: "数据保存", value: "默认不落盘；重启后恢复内置演示状态")
                        PrivacyLine(label: "交易能力", value: "没有下单、撤单、账户配置或资金操作接口")
                        Divider().overlay(.white.opacity(0.08))
                        Label("适合演示、评审和界面原型，不构成投资建议。", systemImage: "checkmark.shield.fill")
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
