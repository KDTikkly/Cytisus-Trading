namespace CytisusTrading.Windows;

public enum ModelProviderProtocol
{
    OpenAICompatible,
    AnthropicCompatible,
    GeminiCompatible
}

public enum ProviderConnectionStatus
{
    NotConfigured,
    NotVerified,
    Ready,
    Degraded,
    RateLimited,
    Unauthorized,
    Unavailable,
    Disabled
}

public enum ProviderTestResultCategory
{
    Ready,
    InvalidConfiguration,
    InvalidBaseURL,
    InsecureEndpointRejected,
    SecretStoreFailure,
    DNSFailure,
    ConnectionTimeout,
    TLSFailure,
    Unauthorized,
    Forbidden,
    RateLimited,
    ProviderUnavailable,
    ModelNotFound,
    UnsupportedCapability,
    ResponseParseFailure,
    Cancelled,
    Unknown
}

public enum ModelRecordSource
{
    Discovered,
    Manual
}

public enum ModelCapabilityState
{
    Supported,
    Unsupported,
    Unknown
}

public enum ProviderModelStatus
{
    Available,
    Unverified,
    Unavailable,
    Disabled
}

public enum ModelRole
{
    Primary,
    Fallback
}

public sealed record ModelProviderProfile(
    string ProviderId,
    string DisplayName,
    ModelProviderProtocol ProtocolType,
    string BaseUrl,
    bool Enabled,
    int RequestTimeoutSeconds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    DateTimeOffset? LastTestedAt,
    ProviderConnectionStatus LastTestStatus,
    string LastTestMessage,
    string SecretReference);

public sealed record ProviderModelRecord(
    string ModelRecordId,
    string ProviderId,
    string ModelId,
    string DisplayName,
    bool Enabled,
    ModelRecordSource Source,
    ProviderModelStatus Status,
    ModelCapabilityState SupportsText,
    ModelCapabilityState SupportsToolCalling,
    ModelCapabilityState SupportsStructuredOutput,
    int? ContextWindowOptional,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    DateTimeOffset? LastVerifiedAt);

public sealed record ModelRoleAssignment(
    string AssignmentId,
    string ModelRecordId,
    ModelRole Role,
    int Position,
    DateTimeOffset UpdatedAt);

public sealed record ProviderTestEvent(
    string EventId,
    string ProviderId,
    string? ModelRecordIdOptional,
    DateTimeOffset StartedAt,
    DateTimeOffset CompletedAt,
    ProviderTestResultCategory ResultCategory,
    string SanitizedMessage,
    int? LatencyMsOptional);

public sealed record ModelProviderSelection(
    ModelProviderProfile Provider,
    ProviderModelRecord Model);

public enum ReadOnlyModelTool
{
    Quote,
    MarketStatus,
    SymbolLookup
}

public sealed record ModelToolDecision(
    string Tool,
    IReadOnlyDictionary<string, string> Arguments);

public sealed record ModelToolResult(
    string Tool,
    IReadOnlyDictionary<string, string> Result);
