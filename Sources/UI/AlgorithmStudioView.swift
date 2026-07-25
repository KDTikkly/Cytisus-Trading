import SwiftUI

struct AlgorithmStudioView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "Local Quant Runtime",
                    title: "Algorithm Studio",
                    subtitle: "Versioned projects, truthful compute discovery, deterministic research jobs, and gated Agent proposals."
                )

                HStack(alignment: .top, spacing: 16) {
                    GlassCard {
                        studioSection(
                            title: "Projects and Agent",
                            value: "\(model.localStudioState.projects.count) project",
                            detail: "\(model.agentSafetyStatus) \(model.agentCostLimitStatus)"
                        )
                    }
                    GlassCard {
                        studioSection(
                            title: "Quant Worker",
                            value: "Local process",
                            detail: model.quantWorkerStatus
                        )
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Controlled Runtime")
                            .font(.headline)
                        TextField(
                            "Approved Python executable path",
                            text: $model.pythonExecutablePath
                        )
                        .textFieldStyle(.roundedBorder)
                        TextField(
                            "Worker root directory",
                            text: $model.quantWorkerRootDirectory
                        )
                        .textFieldStyle(.roundedBorder)
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
                        Text(model.quantWorkerStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Compute Backends")
                                .font(.headline)
                            ForEach(model.computeDevices) { device in
                                HStack {
                                    Text(device.name)
                                    Spacer()
                                    Text(device.health.rawValue)
                                        .foregroundStyle(
                                            device.health == .ready
                                                ? Color.green : Color.secondary
                                        )
                                }
                                Text(device.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    GlassCard {
                        studioSection(
                            title: "Backtests, Training, and ONNX",
                            value: "\(model.localStudioState.jobs.count) job",
                            detail: "Jobs are bounded, cancellable, checkpoint-aware, and use CPU fallback when no accelerator is validated."
                        )
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    GlassCard {
                        studioSection(
                            title: "Execution Lab",
                            value: "Proposal only",
                            detail: model.executionModuleStatus
                        )
                    }
                    GlassCard {
                        studioSection(
                            title: "Longbridge Accounts",
                            value: "\(model.localStudioState.accounts.count) fixture",
                            detail: model.longbridgeAccountStatus
                        )
                    }
                }

                GlassCard {
                    studioSection(
                        title: "Agent Order Authorization",
                        value: "SuggestOnly / ConfirmEveryOrder / BoundedAutonomy",
                        detail: "Authorizations are explicit, limited, expiring, revocable, and still subject to the existing risk and execution gateways. There is no manual order ticket."
                    )
                }
            }
            .padding(34)
        }
    }

    private func studioSection(
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.cyan)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
