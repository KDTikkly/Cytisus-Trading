import Foundation
import SwiftUI

struct ProviderModelRow: Identifiable {
    let model: ProviderModelRecord
    let role: String
    let fallbackPosition: Int

    var id: String { model.modelRecordId }
}

@MainActor
final class ModelProvidersViewModel: ObservableObject {
    @Published private(set) var providers: [ModelProviderProfile] = []
    @Published private(set) var models: [ProviderModelRow] = []
    @Published var selectedProviderID = "" {
        didSet { loadSelectedProvider() }
    }
    @Published var selectedModelID = "" {
        didSet {
            modelDisplayName = selectedModel?.model.displayName ?? ""
        }
    }
    @Published var providerName = ""
    @Published var protocolType: ModelProviderProtocol = .openAICompatible
    @Published var baseURL = "https://api.openai.com/v1"
    @Published var apiKey = ""
    @Published var requestTimeoutSeconds = 15.0
    @Published var confirmRemoteHTTP = false
    @Published var manualModelID = ""
    @Published var modelDisplayName = ""
    @Published private(set) var statusMessage =
        "Add a provider or select an existing profile."
    @Published private(set) var isBusy = false

    private let manager: ModelProviderManager
    private var editingExisting = false

    init(manager: ModelProviderManager) {
        self.manager = manager
        reload()
    }

    var selectedProvider: ModelProviderProfile? {
        providers.first { $0.providerId == selectedProviderID }
    }

    var selectedModel: ProviderModelRow? {
        models.first { $0.id == selectedModelID }
    }

    var savedKeyState: String {
        selectedProvider == nil
            ? "No saved key"
            : "API key saved in macOS Keychain"
    }

    var selectedProviderModelCount: Int {
        manager.loadModels().filter {
            $0.providerId == selectedProviderID
        }.count
    }

    var selectedProviderRoleBadge: String {
        let modelIds = Set(manager.loadModels()
            .filter { $0.providerId == selectedProviderID }
            .map(\.modelRecordId))
        let roles = Set(manager.loadAssignments()
            .filter { modelIds.contains($0.modelRecordId) }
            .map { $0.role.rawValue })
        return roles.isEmpty ? "None" : roles.sorted().joined(separator: ", ")
    }

    var selectionSummary: String {
        let chain = manager.selectionChain()
        guard !chain.isEmpty else {
            return "No Ready primary model is selected."
        }
        return chain.map {
            "\($0.provider.displayName)/\($0.model.displayName)"
        }.joined(separator: " -> ")
    }

    func beginAdd() {
        editingExisting = false
        selectedProviderID = ""
        providerName = ""
        protocolType = .openAICompatible
        baseURL = "https://api.openai.com/v1"
        apiKey = ""
        requestTimeoutSeconds = 15
        confirmRemoteHTTP = false
        models = []
        statusMessage = "Enter provider metadata and an API key."
    }

    func beginEdit() {
        guard selectedProvider != nil else {
            statusMessage = "Select a provider to edit."
            return
        }
        editingExisting = true
        loadSelectedProvider()
        statusMessage =
            "Editing disables the provider until it is tested again."
    }

    func saveProvider() {
        do {
            if editingExisting, let provider = selectedProvider {
                try manager.updateProvider(
                    providerId: provider.providerId,
                    displayName: providerName,
                    protocolType: protocolType,
                    baseURL: baseURL,
                    timeoutSeconds: Int(requestTimeoutSeconds),
                    confirmRemoteHTTP: confirmRemoteHTTP
                )
                statusMessage = "Provider metadata updated."
            } else {
                guard !apiKey.isEmpty else {
                    throw ModelProviderServiceError.invalidConfiguration(
                        "An API key is required for a new provider."
                    )
                }
                let provider = try manager.addProvider(
                    displayName: providerName,
                    protocolType: protocolType,
                    baseURL: baseURL,
                    timeoutSeconds: Int(requestTimeoutSeconds),
                    apiKey: apiKey,
                    confirmRemoteHTTP: confirmRemoteHTTP
                )
                selectedProviderID = provider.providerId
                editingExisting = true
                statusMessage = "Provider saved as Not Verified."
            }
            apiKey = ""
            reload(providerId: selectedProviderID)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    func replaceAPIKey() {
        guard let provider = selectedProvider, !apiKey.isEmpty else {
            statusMessage =
                "Select a provider and enter a replacement key."
            return
        }
        do {
            try manager.replaceAPIKey(
                providerId: provider.providerId,
                apiKey: apiKey
            )
            apiKey = ""
            statusMessage = "API key replaced. Test before enabling."
            reload(providerId: provider.providerId)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    func deleteProvider() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider to delete."
            return
        }
        do {
            try manager.deleteProvider(provider.providerId)
            statusMessage =
                "Provider, models, roles, and secure key deleted."
            reload()
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    func toggleProvider() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider."
            return
        }
        do {
            try manager.setProviderEnabled(
                providerId: provider.providerId,
                enabled: !provider.enabled
            )
            statusMessage = provider.enabled
                ? "Provider disabled."
                : "Provider enabled."
            reload(providerId: provider.providerId)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    func testConnection() async {
        guard let provider = selectedProvider,
              let model = selectedModel else {
            statusMessage = "Select a provider and model to test."
            return
        }
        isBusy = true
        let result = await manager.testConnection(
            providerId: provider.providerId,
            modelRecordId: model.id
        )
        statusMessage =
            "\(result.category.rawValue): \(SensitiveDataRedactor.redact(result.message))"
        reload(providerId: provider.providerId, modelId: model.id)
        isBusy = false
    }

    func discoverModels() async {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider."
            return
        }
        isBusy = true
        do {
            let discovered = try await manager.discoverModels(
                providerId: provider.providerId
            )
            statusMessage =
                "Discovered \(discovered.count) models. They remain disabled."
            reload(providerId: provider.providerId)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
        isBusy = false
    }

    func proposeProjectPatch(
        projectName: String,
        request: String
    ) async throws -> String {
        let outcome = try await manager.generateTextWithFallback(
            systemInstruction:
                "Propose a review-only quantitative strategy ProjectPatch. Do not place orders, change credentials, or apply changes.",
            userText:
                "Project: \(projectName)\nRequested adjustment: \(request)\nReturn a concise patch proposal and validation plan."
        )
        return outcome.text
    }

    func addManualModel() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider."
            return
        }
        do {
            let model = try manager.addManualModel(
                providerId: provider.providerId,
                modelId: manualModelID
            )
            manualModelID = ""
            statusMessage = "Manual model added as disabled and unverified."
            reload(providerId: provider.providerId, modelId: model.modelRecordId)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    func toggleModel() {
        guard let row = selectedModel else {
            statusMessage = "Select a model."
            return
        }
        runModelAction {
            try manager.setModelEnabled(
                modelRecordId: row.id,
                enabled: !row.model.enabled
            )
        }
    }

    func updateModelDisplayName() {
        guard let row = selectedModel else { return }
        runModelAction {
            try manager.updateModelDisplayName(
                modelRecordId: row.id,
                displayName: modelDisplayName
            )
        }
    }

    func removeModel() {
        guard let row = selectedModel else { return }
        let providerId = selectedProviderID
        do {
            try manager.removeModel(row.id)
            statusMessage = "Model and its role assignment removed."
            reload(providerId: providerId)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    func setPrimary() {
        guard let row = selectedModel else { return }
        runModelAction { try manager.setPrimary(row.id) }
    }

    func addFallback() {
        guard let row = selectedModel else { return }
        runModelAction { try manager.addFallback(row.id) }
    }

    func removeRole() {
        guard let row = selectedModel else { return }
        runModelAction { try manager.removeRole(row.id) }
    }

    func moveFallback(_ delta: Int) {
        guard let row = selectedModel else { return }
        runModelAction {
            try manager.moveFallback(row.id, delta: delta)
        }
    }

    private func runModelAction(_ action: () throws -> Void) {
        let providerId = selectedProviderID
        let modelId = selectedModelID
        do {
            try action()
            statusMessage = "Model configuration updated."
            reload(providerId: providerId, modelId: modelId)
        } catch {
            statusMessage = SensitiveDataRedactor.redact(
                error.localizedDescription
            )
        }
    }

    private func reload(
        providerId: String? = nil,
        modelId: String? = nil
    ) {
        let desiredProvider = providerId ?? selectedProviderID
        providers = manager.loadProviders()
        selectedProviderID = providers.contains(where: {
            $0.providerId == desiredProvider
        }) ? desiredProvider : (providers.first?.providerId ?? "")
        reloadModels(modelId: modelId)
        objectWillChange.send()
    }

    private func reloadModels(modelId: String? = nil) {
        let desiredModel = modelId ?? selectedModelID
        let assignments = manager.loadAssignments()
        models = manager.loadModels()
            .filter { $0.providerId == selectedProviderID }
            .map { model in
                let assignment = assignments.first {
                    $0.modelRecordId == model.modelRecordId
                }
                return ProviderModelRow(
                    model: model,
                    role: assignment?.role.rawValue ?? "None",
                    fallbackPosition: assignment?.position ?? 0
                )
            }
        selectedModelID = models.contains(where: { $0.id == desiredModel })
            ? desiredModel
            : (models.first?.id ?? "")
    }

    private func loadSelectedProvider() {
        guard let provider = selectedProvider else {
            reloadModels()
            return
        }
        editingExisting = true
        providerName = provider.displayName
        protocolType = provider.protocolType
        baseURL = provider.baseURL
        requestTimeoutSeconds = Double(provider.requestTimeoutSeconds)
        confirmRemoteHTTP = false
        apiKey = ""
        reloadModels()
    }
}
