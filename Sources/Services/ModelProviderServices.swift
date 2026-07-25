import Foundation

enum ProviderEndpointSafety {
    case secure
    case localHTTP
    case remoteHTTPConfirmationRequired
    case invalid
}

struct ProviderRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?
}

struct ProviderClientTestResult {
    let category: ProviderTestResultCategory
    let message: String
    let latencyMilliseconds: Int?

    var isReady: Bool { category == .ready }
}

struct ModelGenerationOutcome {
    let text: String
    let selection: ModelProviderSelection
}

protocol ModelProviderClient {
    func listModels(
        provider: ModelProviderProfile,
        apiKey: String
    ) async throws -> [ProviderModelRecord]
    func testConnection(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String
    ) async -> ProviderClientTestResult
    func generateText(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> String
    func generateStructuredResponse(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> [String: Any]
    func requestToolDecision(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> ModelToolDecision
}

enum ProviderEndpointValidator {
    static func validate(_ value: String) -> ProviderEndpointSafety {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              ["https", "http"].contains(scheme) else {
            return .invalid
        }
        if scheme == "https" {
            return .secure
        }
        return ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
            ? .localHTTP
            : .remoteHTTPConfirmationRequired
    }
}

enum ModelProviderRequestFactory {
    static func listModels(
        provider: ModelProviderProfile,
        apiKey: String
    ) throws -> ProviderRequest {
        switch provider.protocolType {
        case .openAICompatible:
            return ProviderRequest(
                method: "GET",
                url: try endpoint(provider.baseURL, "models"),
                headers: ["Authorization": "Bearer \(apiKey)"],
                body: nil
            )
        case .geminiCompatible:
            return ProviderRequest(
                method: "GET",
                url: try endpoint(provider.baseURL, "models"),
                headers: ["x-goog-api-key": apiKey],
                body: nil
            )
        case .anthropicCompatible:
            throw ModelProviderServiceError.unsupportedCapability(
                "Anthropic-compatible model discovery is optional and unavailable."
            )
        }
    }

    static func generateText(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) throws -> ProviderRequest {
        switch provider.protocolType {
        case .openAICompatible:
            return try jsonRequest(
                url: endpoint(provider.baseURL, "chat/completions"),
                headers: ["Authorization": "Bearer \(apiKey)"],
                object: [
                    "model": model.modelId,
                    "temperature": 0,
                    "messages": [
                        ["role": "system", "content": systemInstruction],
                        ["role": "user", "content": userText]
                    ]
                ]
            )
        case .anthropicCompatible:
            return try jsonRequest(
                url: endpoint(provider.baseURL, "messages"),
                headers: [
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01"
                ],
                object: [
                    "model": model.modelId,
                    "max_tokens": 64,
                    "temperature": 0,
                    "system": systemInstruction,
                    "messages": [
                        ["role": "user", "content": userText]
                    ]
                ]
            )
        case .geminiCompatible:
            let modelId = model.modelId.hasPrefix("models/")
                ? String(model.modelId.dropFirst("models/".count))
                : model.modelId
            guard let encoded = modelId.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) else {
                throw ModelProviderServiceError.invalidBaseURL
            }
            return try jsonRequest(
                url: endpoint(
                    provider.baseURL,
                    "models/\(encoded):generateContent"
                ),
                headers: ["x-goog-api-key": apiKey],
                object: [
                    "systemInstruction": [
                        "parts": [["text": systemInstruction]]
                    ],
                    "contents": [[
                        "role": "user",
                        "parts": [["text": userText]]
                    ]],
                    "generationConfig": [
                        "temperature": 0,
                        "maxOutputTokens": 64
                    ]
                ]
            )
        }
    }

    private static func endpoint(
        _ baseURL: String,
        _ relative: String
    ) throws -> URL {
        guard let url = URL(
            string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/"
                + relative.trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
        ) else {
            throw ModelProviderServiceError.invalidBaseURL
        }
        return url
    }

    private static func jsonRequest(
        url: URL,
        headers: [String: String],
        object: Any
    ) throws -> ProviderRequest {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ModelProviderServiceError.responseParseFailure
        }
        return ProviderRequest(
            method: "POST",
            url: url,
            headers: headers,
            body: try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        )
    }
}

enum ModelProviderServiceError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidBaseURL
    case insecureEndpointRejected
    case unsupportedCapability(String)
    case responseParseFailure
    case providerFailure(Int, String)
    case tradingToolRejected

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .invalidBaseURL: return "The Base URL is invalid."
        case .insecureEndpointRejected:
            return "Remote HTTP requires explicit confirmation."
        case .unsupportedCapability(let message): return message
        case .responseParseFailure: return "The provider response was invalid."
        case .providerFailure(let code, let message):
            return "Provider returned \(code): \(message)"
        case .tradingToolRejected:
            return "Trading and account-mutation model tools are rejected."
        }
    }
}

final class HTTPModelProviderClient: ModelProviderClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func listModels(
        provider: ModelProviderProfile,
        apiKey: String
    ) async throws -> [ProviderModelRecord] {
        let request = try ModelProviderRequestFactory.listModels(
            provider: provider,
            apiKey: apiKey
        )
        let data = try await send(
            request,
            timeoutSeconds: provider.requestTimeoutSeconds
        )
        guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw ModelProviderServiceError.responseParseFailure
        }
        let values: [(String, String)]
        switch provider.protocolType {
        case .openAICompatible:
            values = (root["data"] as? [[String: Any]] ?? []).compactMap {
                item in
                guard let id = item["id"] as? String else { return nil }
                return (id, id)
            }
        case .geminiCompatible:
            values = (root["models"] as? [[String: Any]] ?? []).compactMap {
                item in
                guard let id = item["name"] as? String else { return nil }
                return (id, item["displayName"] as? String ?? id)
            }
        case .anthropicCompatible:
            values = []
        }
        let now = Date()
        return values.map { modelId, displayName in
            ProviderModelRecord(
                modelRecordId: UUID().uuidString,
                providerId: provider.providerId,
                modelId: modelId,
                displayName: displayName,
                enabled: false,
                source: .discovered,
                status: .disabled,
                supportsText: .supported,
                supportsToolCalling: .unknown,
                supportsStructuredOutput: .unknown,
                contextWindow: nil,
                createdAt: now,
                updatedAt: now,
                lastVerifiedAt: now
            )
        }
    }

    func testConnection(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String
    ) async -> ProviderClientTestResult {
        let started = Date()
        do {
            _ = try await generateText(
                provider: provider,
                model: model,
                apiKey: apiKey,
                systemInstruction: "Return the single word READY.",
                userText: "Connectivity check."
            )
            return ProviderClientTestResult(
                category: .ready,
                message: "Provider and model responded.",
                latencyMilliseconds: Int(
                    Date().timeIntervalSince(started) * 1_000
                )
            )
        } catch {
            return ProviderClientTestResult(
                category: Self.mapFailure(error),
                message: SensitiveDataRedactor.redact(
                    error.localizedDescription
                ),
                latencyMilliseconds: Int(
                    Date().timeIntervalSince(started) * 1_000
                )
            )
        }
    }

    func generateText(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> String {
        let request = try ModelProviderRequestFactory.generateText(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemInstruction: systemInstruction,
            userText: userText
        )
        let data = try await send(
            request,
            timeoutSeconds: provider.requestTimeoutSeconds
        )
        guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw ModelProviderServiceError.responseParseFailure
        }
        let output: String?
        switch provider.protocolType {
        case .openAICompatible:
            output = ((root["choices"] as? [[String: Any]])?.first?["message"]
                as? [String: Any])?["content"] as? String
        case .anthropicCompatible:
            output = (root["content"] as? [[String: Any]])?.first?["text"]
                as? String
        case .geminiCompatible:
            let candidate = (root["candidates"] as? [[String: Any]])?.first
            let content = candidate?["content"] as? [String: Any]
            output = (content?["parts"] as? [[String: Any]])?.first?["text"]
                as? String
        }
        guard let output else {
            throw ModelProviderServiceError.responseParseFailure
        }
        return output
    }

    func generateStructuredResponse(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> [String: Any] {
        let value = try await generateText(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemInstruction: systemInstruction,
            userText: userText
        )
        guard let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw ModelProviderServiceError.responseParseFailure
        }
        return object
    }

    func requestToolDecision(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> ModelToolDecision {
        guard model.supportsToolCalling == .supported else {
            throw ModelProviderServiceError.unsupportedCapability(
                "Tool calling is not explicitly supported by this model."
            )
        }
        let object = try await generateStructuredResponse(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemInstruction: systemInstruction,
            userText: userText
        )
        guard let tool = object["tool"] as? String else {
            throw ModelProviderServiceError.responseParseFailure
        }
        return ModelToolDecision(
            tool: tool,
            arguments: object["arguments"] as? [String: String] ?? [:]
        )
    }

    private func send(
        _ providerRequest: ProviderRequest,
        timeoutSeconds: Int
    ) async throws -> Data {
        var request = URLRequest(url: providerRequest.url)
        request.httpMethod = providerRequest.method
        request.timeoutInterval = TimeInterval(
            min(max(timeoutSeconds, 2), 120)
        )
        for (key, value) in providerRequest.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = providerRequest.body {
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderServiceError.responseParseFailure
        }
        guard (200..<300).contains(http.statusCode) else {
            let bounded = String(
                String(data: data.prefix(4_096), encoding: .utf8) ?? ""
            )
            throw ModelProviderServiceError.providerFailure(
                http.statusCode,
                SensitiveDataRedactor.redact(bounded)
            )
        }
        return data
    }

    private static func mapFailure(
        _ error: Error
    ) -> ProviderTestResultCategory {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .connectionTimeout
            case .cannotFindHost, .dnsLookupFailed: return .dnsFailure
            case .secureConnectionFailed,
                 .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot:
                return .tlsFailure
            default: return .providerUnavailable
            }
        }
        if let serviceError = error as? ModelProviderServiceError {
            switch serviceError {
            case .providerFailure(let code, _):
                switch code {
                case 401: return .unauthorized
                case 403: return .forbidden
                case 404: return .modelNotFound
                case 429: return .rateLimited
                case 500...599: return .providerUnavailable
                default: return .unknown
                }
            case .responseParseFailure:
                return .responseParseFailure
            case .unsupportedCapability:
                return .unsupportedCapability
            default:
                return .unknown
            }
        }
        return .unknown
    }
}

final class ModelProviderManager {
    private let store: ModelProviderStore
    private let secrets: ModelSecretStore
    private let client: ModelProviderClient

    init(
        store: ModelProviderStore,
        secrets: ModelSecretStore,
        client: ModelProviderClient
    ) {
        self.store = store
        self.secrets = secrets
        self.client = client
    }

    func loadProviders() -> [ModelProviderProfile] {
        (try? store.loadModelProviders()) ?? []
    }

    func loadModels() -> [ProviderModelRecord] {
        (try? store.loadProviderModels()) ?? []
    }

    func loadAssignments() -> [ModelRoleAssignment] {
        (try? store.loadModelRoleAssignments()) ?? []
    }

    func addProvider(
        displayName: String,
        protocolType: ModelProviderProtocol,
        baseURL: String,
        timeoutSeconds: Int,
        apiKey: String,
        confirmRemoteHTTP: Bool
    ) throws -> ModelProviderProfile {
        var providers = try store.loadModelProviders()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !providers.contains(where: {
                $0.displayName.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Provider name is required and must be unique."
            )
        }
        try validateEndpoint(baseURL, confirmRemoteHTTP: confirmRemoteHTTP)
        let now = Date()
        let providerId = UUID().uuidString
        let reference = "model-provider:\(providerId)"
        try secrets.save(secret: apiKey, reference: reference)
        let provider = ModelProviderProfile(
            providerId: providerId,
            displayName: name,
            protocolType: protocolType,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: false,
            requestTimeoutSeconds: min(max(timeoutSeconds, 2), 120),
            createdAt: now,
            updatedAt: now,
            lastTestedAt: nil,
            lastTestStatus: .notVerified,
            lastTestMessage: "Saved. Test the provider before enabling it.",
            secretReference: reference
        )
        providers.append(provider)
        try store.saveModelProviders(providers)
        return provider
    }

    func replaceAPIKey(providerId: String, apiKey: String) throws {
        var provider = try requiredProvider(providerId)
        try secrets.replace(
            secret: apiKey,
            reference: provider.secretReference
        )
        provider.enabled = false
        provider.updatedAt = Date()
        provider.lastTestStatus = .notVerified
        provider.lastTestMessage = "API key replaced. Test before enabling."
        try saveProvider(provider)
    }

    func updateProvider(
        providerId: String,
        displayName: String,
        protocolType: ModelProviderProtocol,
        baseURL: String,
        timeoutSeconds: Int,
        confirmRemoteHTTP: Bool
    ) throws {
        var provider = try requiredProvider(providerId)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !loadProviders().contains(where: {
                $0.providerId != providerId &&
                    $0.displayName.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Provider name is required and must be unique."
            )
        }
        try validateEndpoint(baseURL, confirmRemoteHTTP: confirmRemoteHTTP)
        provider.displayName = name
        provider.protocolType = protocolType
        provider.baseURL = baseURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        provider.requestTimeoutSeconds = min(max(timeoutSeconds, 2), 120)
        provider.enabled = false
        provider.updatedAt = Date()
        provider.lastTestStatus = .notVerified
        provider.lastTestMessage =
            "Configuration changed. Test before enabling."
        try saveProvider(provider)
    }

    func deleteProvider(_ providerId: String) throws {
        let provider = try requiredProvider(providerId)
        try secrets.delete(reference: provider.secretReference)
        let removedIds = Set(try store.loadProviderModels()
            .filter { $0.providerId == providerId }
            .map(\.modelRecordId))
        try store.saveModelProviders(
            try store.loadModelProviders().filter {
                $0.providerId != providerId
            }
        )
        try store.saveProviderModels(
            try store.loadProviderModels().filter {
                $0.providerId != providerId
            }
        )
        try store.saveModelRoleAssignments(
            try store.loadModelRoleAssignments().filter {
                !removedIds.contains($0.modelRecordId)
            }
        )
    }

    func addManualModel(
        providerId: String,
        modelId: String,
        displayName: String? = nil
    ) throws -> ProviderModelRecord {
        _ = try requiredProvider(providerId)
        var models = try store.loadProviderModels()
        let identifier = modelId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !identifier.isEmpty,
              !models.contains(where: {
                $0.providerId == providerId && $0.modelId == identifier
              }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Model ID is required and must be unique for this provider."
            )
        }
        let now = Date()
        let model = ProviderModelRecord(
            modelRecordId: UUID().uuidString,
            providerId: providerId,
            modelId: identifier,
            displayName: displayName?.isEmpty == false
                ? displayName!
                : identifier,
            enabled: false,
            source: .manual,
            status: .unverified,
            supportsText: .supported,
            supportsToolCalling: .unknown,
            supportsStructuredOutput: .unknown,
            contextWindow: nil,
            createdAt: now,
            updatedAt: now,
            lastVerifiedAt: nil
        )
        models.append(model)
        try store.saveProviderModels(models)
        return model
    }

    func discoverModels(providerId: String) async throws
        -> [ProviderModelRecord] {
        let provider = try requiredProvider(providerId)
        let key = try secrets.retrieve(reference: provider.secretReference)
        let discovered = try await client.listModels(
            provider: provider,
            apiKey: key
        )
        var models = try store.loadProviderModels()
        for candidate in discovered where !models.contains(where: {
            $0.providerId == providerId && $0.modelId == candidate.modelId
        }) {
            models.append(candidate)
        }
        try store.saveProviderModels(models)
        return discovered
    }

    func setProviderEnabled(
        providerId: String,
        enabled: Bool
    ) throws {
        var provider = try requiredProvider(providerId)
        guard !enabled || provider.lastTestStatus == .ready else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Test the provider successfully before enabling it."
            )
        }
        provider.enabled = enabled
        provider.updatedAt = Date()
        provider.lastTestStatus = enabled ? provider.lastTestStatus : .disabled
        try saveProvider(provider)
    }

    func setModelEnabled(
        modelRecordId: String,
        enabled: Bool
    ) throws {
        var models = try store.loadProviderModels()
        guard let index = models.firstIndex(where: {
            $0.modelRecordId == modelRecordId
        }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Model not found."
            )
        }
        models[index].enabled = enabled
        models[index].status = enabled ? .available : .disabled
        models[index].updatedAt = Date()
        try store.saveProviderModels(models)
        if !enabled {
            try store.saveModelRoleAssignments(
                try store.loadModelRoleAssignments().filter {
                    $0.modelRecordId != modelRecordId
                }
            )
        }
    }

    func updateModelDisplayName(
        modelRecordId: String,
        displayName: String
    ) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Model display name is required."
            )
        }
        var models = try store.loadProviderModels()
        guard let index = models.firstIndex(where: {
            $0.modelRecordId == modelRecordId
        }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Model not found."
            )
        }
        models[index].displayName = name
        models[index].updatedAt = Date()
        try store.saveProviderModels(models)
    }

    func removeModel(_ modelRecordId: String) throws {
        try store.saveProviderModels(
            try store.loadProviderModels().filter {
                $0.modelRecordId != modelRecordId
            }
        )
        try store.saveModelRoleAssignments(
            try store.loadModelRoleAssignments().filter {
                $0.modelRecordId != modelRecordId
            }
        )
    }

    func setPrimary(_ modelRecordId: String) throws {
        try requireSelectable(modelRecordId)
        var assignments = try store.loadModelRoleAssignments().filter {
            $0.role != .primary && $0.modelRecordId != modelRecordId
        }
        assignments.append(ModelRoleAssignment(
            assignmentId: UUID().uuidString,
            modelRecordId: modelRecordId,
            role: .primary,
            position: 0,
            updatedAt: Date()
        ))
        try store.saveModelRoleAssignments(assignments)
    }

    func addFallback(_ modelRecordId: String) throws {
        try requireSelectable(modelRecordId)
        var assignments = try store.loadModelRoleAssignments()
        guard !assignments.contains(where: {
            $0.modelRecordId == modelRecordId
        }) else { return }
        let position = (assignments.filter { $0.role == .fallback }
            .map(\.position).max() ?? 0) + 1
        assignments.append(ModelRoleAssignment(
            assignmentId: UUID().uuidString,
            modelRecordId: modelRecordId,
            role: .fallback,
            position: position,
            updatedAt: Date()
        ))
        try store.saveModelRoleAssignments(assignments)
    }

    func moveFallback(_ modelRecordId: String, delta: Int) throws {
        let primary = try store.loadModelRoleAssignments().filter {
            $0.role == .primary
        }
        var fallbacks = try store.loadModelRoleAssignments()
            .filter { $0.role == .fallback }
            .sorted { $0.position < $1.position }
        guard let index = fallbacks.firstIndex(where: {
            $0.modelRecordId == modelRecordId
        }) else { return }
        let destination = min(max(index + delta, 0), fallbacks.count - 1)
        guard destination != index else { return }
        fallbacks.swapAt(index, destination)
        let now = Date()
        let reordered = fallbacks.enumerated().map { offset, item in
            ModelRoleAssignment(
                assignmentId: item.assignmentId,
                modelRecordId: item.modelRecordId,
                role: .fallback,
                position: offset + 1,
                updatedAt: now
            )
        }
        try store.saveModelRoleAssignments(primary + reordered)
    }

    func removeRole(_ modelRecordId: String) throws {
        try store.saveModelRoleAssignments(
            try store.loadModelRoleAssignments().filter {
                $0.modelRecordId != modelRecordId
            }
        )
    }

    func selectionChain() -> [ModelProviderSelection] {
        guard let providers = try? store.loadModelProviders(),
              let models = try? store.loadProviderModels(),
              let assignments = try? store.loadModelRoleAssignments() else {
            return []
        }
        let providerMap = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.providerId, $0) }
        )
        let modelMap = Dictionary(
            uniqueKeysWithValues: models.map { ($0.modelRecordId, $0) }
        )
        return assignments.sorted {
            ($0.role == .primary ? 0 : 1, $0.position) <
                ($1.role == .primary ? 0 : 1, $1.position)
        }.compactMap { assignment in
            guard let model = modelMap[assignment.modelRecordId],
                  let provider = providerMap[model.providerId],
                  provider.enabled,
                  provider.lastTestStatus == .ready,
                  model.enabled,
                  model.status == .available else {
                return nil
            }
            return ModelProviderSelection(provider: provider, model: model)
        }
    }

    func generateTextWithFallback(
        systemInstruction: String,
        userText: String
    ) async throws -> ModelGenerationOutcome {
        var lastFailure: Error?
        for selection in selectionChain() {
            do {
                let key = try secrets.retrieve(
                    reference: selection.provider.secretReference
                )
                let text = try await client.generateText(
                    provider: selection.provider,
                    model: selection.model,
                    apiKey: key,
                    systemInstruction: systemInstruction,
                    userText: userText
                )
                return ModelGenerationOutcome(
                    text: text,
                    selection: selection
                )
            } catch {
                guard Self.fallbackEligible(error) else { throw error }
                lastFailure = error
            }
        }
        throw lastFailure ?? ModelProviderServiceError.invalidConfiguration(
            "No Ready primary model is configured."
        )
    }

    func requestToolDecisionWithFallback(
        systemInstruction: String,
        userText: String
    ) async throws -> (ModelToolDecision, ModelProviderSelection) {
        var lastFailure: Error?
        for selection in selectionChain() {
            do {
                let key = try secrets.retrieve(
                    reference: selection.provider.secretReference
                )
                let decision = try await client.requestToolDecision(
                    provider: selection.provider,
                    model: selection.model,
                    apiKey: key,
                    systemInstruction: systemInstruction,
                    userText: userText
                )
                return (decision, selection)
            } catch {
                guard Self.fallbackEligible(error) else { throw error }
                lastFailure = error
            }
        }
        throw lastFailure ?? ModelProviderServiceError.invalidConfiguration(
            "No Ready tool-capable model is configured."
        )
    }

    func testConnection(
        providerId: String,
        modelRecordId: String
    ) async -> ProviderClientTestResult {
        let started = Date()
        do {
            var provider = try requiredProvider(providerId)
            guard let model = try store.loadProviderModels().first(where: {
                $0.modelRecordId == modelRecordId &&
                    $0.providerId == providerId
            }) else {
                throw ModelProviderServiceError.invalidConfiguration(
                    "Model not found."
                )
            }
            let key = try secrets.retrieve(
                reference: provider.secretReference
            )
            let result = await client.testConnection(
                provider: provider,
                model: model,
                apiKey: key
            )
            let completed = Date()
            provider.updatedAt = completed
            provider.lastTestedAt = completed
            provider.lastTestStatus = Self.mapStatus(result.category)
            provider.lastTestMessage = SensitiveDataRedactor.redact(
                result.message
            )
            try saveProvider(provider)
            try store.appendProviderTestEvent(ProviderTestEvent(
                eventId: UUID().uuidString,
                providerId: providerId,
                modelRecordId: modelRecordId,
                startedAt: started,
                completedAt: completed,
                resultCategory: result.category,
                sanitizedMessage: SensitiveDataRedactor.redact(
                    result.message
                ),
                latencyMilliseconds: result.latencyMilliseconds
            ))
            return result
        } catch {
            return ProviderClientTestResult(
                category: .secretStoreFailure,
                message: SensitiveDataRedactor.redact(
                    error.localizedDescription
                ),
                latencyMilliseconds: nil
            )
        }
    }

    private func validateEndpoint(
        _ baseURL: String,
        confirmRemoteHTTP: Bool
    ) throws {
        switch ProviderEndpointValidator.validate(baseURL) {
        case .secure, .localHTTP: return
        case .remoteHTTPConfirmationRequired:
            guard confirmRemoteHTTP else {
                throw ModelProviderServiceError.insecureEndpointRejected
            }
        case .invalid:
            throw ModelProviderServiceError.invalidBaseURL
        }
    }

    private func requiredProvider(
        _ providerId: String
    ) throws -> ModelProviderProfile {
        guard let provider = try store.loadModelProviders().first(where: {
            $0.providerId == providerId
        }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Provider not found."
            )
        }
        return provider
    }

    private func saveProvider(
        _ provider: ModelProviderProfile
    ) throws {
        var providers = try store.loadModelProviders()
        guard let index = providers.firstIndex(where: {
            $0.providerId == provider.providerId
        }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Provider not found."
            )
        }
        providers[index] = provider
        try store.saveModelProviders(providers)
    }

    private func requireSelectable(_ modelRecordId: String) throws {
        guard let model = try store.loadProviderModels().first(where: {
            $0.modelRecordId == modelRecordId
        }) else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Model not found."
            )
        }
        let provider = try requiredProvider(model.providerId)
        guard provider.enabled,
              provider.lastTestStatus == .ready,
              model.enabled,
              model.status == .available else {
            throw ModelProviderServiceError.invalidConfiguration(
                "Only enabled models from Ready providers are selectable."
            )
        }
    }

    private static func mapStatus(
        _ result: ProviderTestResultCategory
    ) -> ProviderConnectionStatus {
        switch result {
        case .ready: return .ready
        case .unauthorized: return .unauthorized
        case .rateLimited: return .rateLimited
        case .providerUnavailable: return .unavailable
        default: return .degraded
        }
    }

    private static func fallbackEligible(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .networkConnectionLost,
                .notConnectedToInternet
            ].contains(urlError.code)
        }
        if let serviceError = error as? ModelProviderServiceError,
           case let .providerFailure(code, _) = serviceError {
            return code == 408 || code == 429 || code >= 500
        }
        return false
    }
}

protocol ReadOnlyLongbridgeToolGateway {
    func execute(
        tool: ReadOnlyModelTool,
        arguments: [String: String]
    ) async throws -> ModelToolResult
}

final class ModelLongbridgeCoordinator {
    private let gateway: ReadOnlyLongbridgeToolGateway

    init(gateway: ReadOnlyLongbridgeToolGateway) {
        self.gateway = gateway
    }

    func executeDecision(
        _ decision: ModelToolDecision
    ) async throws -> ModelToolResult {
        guard let tool = ReadOnlyModelTool(rawValue: decision.tool) else {
            throw ModelProviderServiceError.tradingToolRejected
        }
        return try await gateway.execute(
            tool: tool,
            arguments: decision.arguments
        )
    }
}

final class FixtureReadOnlyLongbridgeToolGateway:
    ReadOnlyLongbridgeToolGateway {
    private let fixtures: LongbridgeDataServicing

    init(fixtures: LongbridgeDataServicing) {
        self.fixtures = fixtures
    }

    func execute(
        tool: ReadOnlyModelTool,
        arguments: [String: String]
    ) async throws -> ModelToolResult {
        let snapshot = try fixtures.loadFixtureSnapshot()
        switch tool {
        case .quote:
            guard let symbol = arguments["symbol"], !symbol.isEmpty else {
                throw ModelProviderServiceError.invalidConfiguration(
                    "Quote requires a symbol."
                )
            }
            guard symbol.caseInsensitiveCompare(
                snapshot.currentSnapshot.symbol
            ) == .orderedSame else {
                throw ModelProviderServiceError.invalidConfiguration(
                    "The fixture has no quote for the requested symbol."
                )
            }
            return ModelToolResult(
                tool: tool.rawValue,
                result: [
                    "symbol": snapshot.currentSnapshot.symbol,
                    "last_price": String(snapshot.currentSnapshot.last),
                    "source": snapshot.currentSnapshot.sourceVersion
                ]
            )
        case .marketStatus:
            return ModelToolResult(
                tool: tool.rawValue,
                result: [
                    "market": snapshot.marketStatus.market,
                    "status": snapshot.marketStatus.session,
                    "source": snapshot.marketStatus.sourceVersion
                ]
            )
        case .symbolLookup:
            guard let symbol = arguments["symbol"], !symbol.isEmpty else {
                throw ModelProviderServiceError.invalidConfiguration(
                    "SymbolLookup requires a symbol."
                )
            }
            let security = snapshot.securityList.securities.first {
                $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame
            }
            return ModelToolResult(
                tool: tool.rawValue,
                result: [
                    "symbol": symbol,
                    "found": security == nil ? "false" : "true",
                    "name": security?.name ?? ""
                ]
            )
        }
    }
}

final class FixtureModelProviderClient: ModelProviderClient {
    private let models: [ProviderModelRecord]
    private let text: String
    private let decision: ModelToolDecision

    init(
        models: [ProviderModelRecord],
        text: String,
        decision: ModelToolDecision
    ) {
        self.models = models
        self.text = text
        self.decision = decision
    }

    func listModels(
        provider: ModelProviderProfile,
        apiKey: String
    ) async throws -> [ProviderModelRecord] {
        models
    }

    func testConnection(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String
    ) async -> ProviderClientTestResult {
        ProviderClientTestResult(
            category: .ready,
            message: "Fixture provider is ready.",
            latencyMilliseconds: 1
        )
    }

    func generateText(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> String {
        text
    }

    func generateStructuredResponse(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> [String: Any] {
        ["tool": decision.tool, "arguments": decision.arguments]
    }

    func requestToolDecision(
        provider: ModelProviderProfile,
        model: ProviderModelRecord,
        apiKey: String,
        systemInstruction: String,
        userText: String
    ) async throws -> ModelToolDecision {
        decision
    }
}
