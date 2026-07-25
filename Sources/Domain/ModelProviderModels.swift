import Foundation

enum ModelProviderProtocol: String, Codable, CaseIterable, Identifiable {
    case openAICompatible = "OpenAICompatible"
    case anthropicCompatible = "AnthropicCompatible"
    case geminiCompatible = "GeminiCompatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropicCompatible: return "Anthropic Compatible"
        case .geminiCompatible: return "Gemini Compatible"
        }
    }
}

enum ProviderConnectionStatus: String, Codable {
    case notConfigured = "NotConfigured"
    case notVerified = "NotVerified"
    case ready = "Ready"
    case degraded = "Degraded"
    case rateLimited = "RateLimited"
    case unauthorized = "Unauthorized"
    case unavailable = "Unavailable"
    case disabled = "Disabled"
}

enum ProviderTestResultCategory: String, Codable, CaseIterable {
    case ready = "Ready"
    case invalidConfiguration = "InvalidConfiguration"
    case invalidBaseURL = "InvalidBaseURL"
    case insecureEndpointRejected = "InsecureEndpointRejected"
    case secretStoreFailure = "SecretStoreFailure"
    case dnsFailure = "DNSFailure"
    case connectionTimeout = "ConnectionTimeout"
    case tlsFailure = "TLSFailure"
    case unauthorized = "Unauthorized"
    case forbidden = "Forbidden"
    case rateLimited = "RateLimited"
    case providerUnavailable = "ProviderUnavailable"
    case modelNotFound = "ModelNotFound"
    case unsupportedCapability = "UnsupportedCapability"
    case responseParseFailure = "ResponseParseFailure"
    case cancelled = "Cancelled"
    case unknown = "Unknown"
}

enum ModelRecordSource: String, Codable {
    case discovered = "Discovered"
    case manual = "Manual"
}

enum ModelCapabilityState: String, Codable {
    case supported = "Supported"
    case unsupported = "Unsupported"
    case unknown = "Unknown"
}

enum ProviderModelStatus: String, Codable {
    case available = "Available"
    case unverified = "Unverified"
    case unavailable = "Unavailable"
    case disabled = "Disabled"
}

enum ModelRole: String, Codable {
    case primary = "Primary"
    case fallback = "Fallback"
}

struct ModelProviderProfile: Codable, Identifiable, Equatable {
    let providerId: String
    var displayName: String
    var protocolType: ModelProviderProtocol
    var baseURL: String
    var enabled: Bool
    var requestTimeoutSeconds: Int
    let createdAt: Date
    var updatedAt: Date
    var lastTestedAt: Date?
    var lastTestStatus: ProviderConnectionStatus
    var lastTestMessage: String
    let secretReference: String

    var id: String { providerId }

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case displayName = "display_name"
        case protocolType = "protocol_type"
        case baseURL = "base_url"
        case enabled
        case requestTimeoutSeconds = "request_timeout_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastTestedAt = "last_tested_at"
        case lastTestStatus = "last_test_status"
        case lastTestMessage = "last_test_message"
        case secretReference = "secret_reference"
    }
}

struct ProviderModelRecord: Codable, Identifiable, Equatable {
    let modelRecordId: String
    let providerId: String
    var modelId: String
    var displayName: String
    var enabled: Bool
    let source: ModelRecordSource
    var status: ProviderModelStatus
    var supportsText: ModelCapabilityState
    var supportsToolCalling: ModelCapabilityState
    var supportsStructuredOutput: ModelCapabilityState
    var contextWindow: Int?
    let createdAt: Date
    var updatedAt: Date
    var lastVerifiedAt: Date?

    var id: String { modelRecordId }

    enum CodingKeys: String, CodingKey {
        case modelRecordId = "model_record_id"
        case providerId = "provider_id"
        case modelId = "model_id"
        case displayName = "display_name"
        case enabled
        case source
        case status
        case supportsText = "supports_text"
        case supportsToolCalling = "supports_tool_calling"
        case supportsStructuredOutput = "supports_structured_output"
        case contextWindow = "context_window_optional"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastVerifiedAt = "last_verified_at"
    }
}

struct ModelRoleAssignment: Codable, Identifiable, Equatable {
    let assignmentId: String
    let modelRecordId: String
    let role: ModelRole
    let position: Int
    let updatedAt: Date

    var id: String { assignmentId }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case modelRecordId = "model_record_id"
        case role
        case position
        case updatedAt = "updated_at"
    }
}

struct ProviderTestEvent: Codable, Identifiable, Equatable {
    let eventId: String
    let providerId: String
    let modelRecordId: String?
    let startedAt: Date
    let completedAt: Date
    let resultCategory: ProviderTestResultCategory
    let sanitizedMessage: String
    let latencyMilliseconds: Int?

    var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case providerId = "provider_id"
        case modelRecordId = "model_record_id_optional"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case resultCategory = "result_category"
        case sanitizedMessage = "sanitized_message"
        case latencyMilliseconds = "latency_ms_optional"
    }
}

struct ModelProviderSelection: Equatable {
    let provider: ModelProviderProfile
    let model: ProviderModelRecord
}

enum ReadOnlyModelTool: String, Codable {
    case quote = "Quote"
    case marketStatus = "MarketStatus"
    case symbolLookup = "SymbolLookup"
}

struct ModelToolDecision: Codable, Equatable {
    let tool: String
    let arguments: [String: String]
}

struct ModelToolResult: Codable, Equatable {
    let tool: String
    let result: [String: String]
}
