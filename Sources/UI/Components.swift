import SwiftUI

extension FactorState {
    var tint: Color {
        switch self {
        case .candidate: return .cyan
        case .shadow: return .indigo
        case .active: return .green
        case .reduced: return .yellow
        case .probation: return .orange
        case .retired: return .secondary
        case .quarantined: return .red
        }
    }
}

struct LiquidBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimated = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.045, blue: 0.105),
                        Color(red: 0.075, green: 0.055, blue: 0.16),
                        Color(red: 0.025, green: 0.085, blue: 0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.cyan.opacity(0.27))
                    .frame(width: proxy.size.width * 0.48)
                    .blur(radius: 100)
                    .offset(
                        x: isAnimated ? proxy.size.width * 0.26 : -proxy.size.width * 0.18,
                        y: isAnimated ? -proxy.size.height * 0.20 : proxy.size.height * 0.12
                    )

                Circle()
                    .fill(Color.indigo.opacity(0.36))
                    .frame(width: proxy.size.width * 0.55)
                    .blur(radius: 125)
                    .offset(
                        x: isAnimated ? -proxy.size.width * 0.28 : proxy.size.width * 0.24,
                        y: isAnimated ? proxy.size.height * 0.19 : -proxy.size.height * 0.16
                    )

                Ellipse()
                    .fill(Color.purple.opacity(0.22))
                    .frame(width: proxy.size.width * 0.64, height: proxy.size.height * 0.36)
                    .blur(radius: 115)
                    .rotationEffect(.degrees(isAnimated ? 18 : -12))
                    .offset(y: proxy.size.height * 0.28)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 14).repeatForever(autoreverses: true),
                value: isAnimated
            )
            .onAppear { isAnimated = true }
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 20

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .white.opacity(0.08), .cyan.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
    }
}

struct StatusPill: View {
    let state: FactorState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 7, height: 7)
                .shadow(color: state.tint.opacity(0.8), radius: 5)
            Text(state.rawValue)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(state.tint.opacity(0.17), in: Capsule())
        .overlay(Capsule().stroke(state.tint.opacity(0.32), lineWidth: 0.7))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.14), in: Circle())
                    Spacer()
                    Circle().fill(tint).frame(width: 6, height: 6)
                        .shadow(color: tint, radius: 6)
                }
                Text(value)
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PrimaryGlassButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.cyan.opacity(configuration.isPressed ? 0.40 : 0.58), Color.indigo.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(0.32), lineWidth: 0.8))
            .shadow(color: .cyan.opacity(0.18), radius: 14, y: 7)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct MiniPerformanceChart: View {
    private let values: [Double] = [0.18, 0.22, 0.20, 0.29, 0.34, 0.31, 0.40, 0.45, 0.43, 0.53, 0.59, 0.63, 0.68]

    var body: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step, y: proxy.size.height * (1 - value))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: first.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                }
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.34), .indigo.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(
                    LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .cyan.opacity(0.55), radius: 7)
            }
        }
    }
}

