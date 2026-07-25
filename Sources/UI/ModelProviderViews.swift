import SwiftUI

struct ModelProvidersSettingsView: View {
    @ObservedObject var viewModel: ModelProvidersViewModel
    @State private var confirmDelete = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Providers").font(.headline)
                        Text(
                            "Model API authorization is separate from Longbridge OAuth."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Provider") { viewModel.beginAdd() }
                    Button("Edit") { viewModel.beginEdit() }
                    Button("Delete", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(viewModel.selectedProvider == nil)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Providers")
                            .font(.caption.weight(.semibold))
                        Picker(
                            "Provider",
                            selection: $viewModel.selectedProviderID
                        ) {
                            Text("New provider").tag("")
                            ForEach(viewModel.providers) { provider in
                                Text(
                                    "\(provider.displayName) | \(provider.protocolType.displayName) | \(provider.lastTestStatus.rawValue)"
                                )
                                .tag(provider.providerId)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        HStack {
                            Button(
                                viewModel.selectedProvider?.enabled == true
                                    ? "Disable"
                                    : "Enable"
                            ) {
                                viewModel.toggleProvider()
                            }
                            Button("Test Connection") {
                                Task { await viewModel.testConnection() }
                            }
                            .disabled(
                                viewModel.selectedProvider == nil ||
                                viewModel.selectedModel == nil ||
                                viewModel.isBusy
                            )
                            Button("Fetch Models") {
                                Task { await viewModel.discoverModels() }
                            }
                            .disabled(
                                viewModel.selectedProvider == nil ||
                                viewModel.isBusy
                            )
                        }
                        Text(viewModel.savedKeyState)
                            .font(.caption)
                            .foregroundStyle(.green)
                        if let provider = viewModel.selectedProvider {
                            Text(
                                "Models \(viewModel.selectedProviderModelCount) | Roles \(viewModel.selectedProviderRoleBadge) | Last tested \(provider.lastTestedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Provider Editor")
                            .font(.caption.weight(.semibold))
                        TextField(
                            "Provider name",
                            text: $viewModel.providerName
                        )
                        .textFieldStyle(.roundedBorder)
                        Picker(
                            "Protocol",
                            selection: $viewModel.protocolType
                        ) {
                            ForEach(ModelProviderProtocol.allCases) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        TextField("Base URL", text: $viewModel.baseURL)
                            .textFieldStyle(.roundedBorder)
                        SecureField(
                            viewModel.selectedProvider == nil
                                ? "API key"
                                : "New API key for replacement",
                            text: $viewModel.apiKey
                        )
                        .textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Timeout")
                                .font(.caption.weight(.semibold))
                            Slider(
                                value: $viewModel.requestTimeoutSeconds,
                                in: 2...120,
                                step: 1
                            )
                            Text(
                                "\(Int(viewModel.requestTimeoutSeconds)) s"
                            )
                            .font(.system(.caption, design: .monospaced))
                        }
                        Toggle(
                            "I confirm this non-local HTTP endpoint",
                            isOn: $viewModel.confirmRemoteHTTP
                        )
                        .font(.caption)
                        HStack {
                            Button("Save Provider") {
                                viewModel.saveProvider()
                            }
                            Button("Replace API Key") {
                                viewModel.replaceAPIKey()
                            }
                            .disabled(viewModel.selectedProvider == nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().overlay(.white.opacity(0.08))

                HStack {
                    TextField(
                        "Manual model ID",
                        text: $viewModel.manualModelID
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Add Model Manually") {
                        viewModel.addManualModel()
                    }
                    .disabled(viewModel.selectedProvider == nil)
                }

                HStack {
                    TextField(
                        "Selected model display name",
                        text: $viewModel.modelDisplayName
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Update Display Name") {
                        viewModel.updateModelDisplayName()
                    }
                    Button("Remove Model", role: .destructive) {
                        viewModel.removeModel()
                    }
                }
                .disabled(viewModel.selectedModel == nil)

                VStack(spacing: 0) {
                    HStack {
                        Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Source").frame(width: 85, alignment: .leading)
                        Text("Status").frame(width: 90, alignment: .leading)
                        Text("Tool use").frame(width: 90, alignment: .leading)
                        Text("Role").frame(width: 85, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 7)

                    ForEach(viewModel.models) { row in
                        Button {
                            viewModel.selectedModelID = row.id
                        } label: {
                            HStack {
                                Text(row.model.displayName)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                Text(row.model.source.rawValue)
                                    .frame(width: 85, alignment: .leading)
                                Text(row.model.status.rawValue)
                                    .frame(width: 90, alignment: .leading)
                                Text(row.model.supportsToolCalling.rawValue)
                                    .frame(width: 90, alignment: .leading)
                                Text(
                                    row.role == ModelRole.fallback.rawValue
                                        ? "\(row.role) \(row.fallbackPosition)"
                                        : row.role
                                )
                                .frame(width: 85, alignment: .leading)
                            }
                            .font(.caption)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(
                                row.id == viewModel.selectedModelID
                                    ? Color.cyan.opacity(0.12)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(.white.opacity(0.05))
                    }
                }

                HStack {
                    Button(
                        viewModel.selectedModel?.model.enabled == true
                            ? "Disable Model"
                            : "Enable Model"
                    ) {
                        viewModel.toggleModel()
                    }
                    Button("Set Primary") { viewModel.setPrimary() }
                    Button("Add Fallback") { viewModel.addFallback() }
                    Button("Remove Role") { viewModel.removeRole() }
                    Button("Move Up") { viewModel.moveFallback(-1) }
                    Button("Move Down") { viewModel.moveFallback(1) }
                }
                .disabled(viewModel.selectedModel == nil)

                Text(viewModel.selectionSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "API keys are masked and never stored in the application database, logs, CLI arguments, or Longbridge environment."
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
        }
        .alert("Delete provider?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteProvider()
            }
        } message: {
            Text(
                "This removes provider metadata, models, role assignments, and the Keychain item."
            )
        }
    }
}
