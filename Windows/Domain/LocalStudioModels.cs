namespace CytisusTrading.Windows;

public enum ComputeDeviceType
{
    Cpu,
    AppleMetal,
    NvidiaCuda,
    AmdRocm,
    IntelOpenVino,
    Npu
}

public enum ComputeHealth
{
    Ready,
    Unavailable,
    Degraded
}

public enum ComputeJobType
{
    FactorCalculation,
    Backtest,
    WalkForwardBacktest,
    ParameterSearch,
    PortfolioOptimization,
    MonteCarlo,
    TrainModel,
    ExportOnnx,
    TestOnnx,
    BenchmarkInference,
    ValidateProject,
    SimulateExecutionAlgorithm
}

public enum ComputeJobStatus
{
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled
}

public enum ComputeSchedulingMode
{
    Auto,
    CpuOnly,
    PreferGpu,
    PreferNpuForInference,
    SpecificDevice,
    MaximumPerformance,
    Balanced,
    BatterySaver
}

public enum OnnxModelStatus
{
    Draft,
    Imported,
    Validated,
    Backtested,
    Shadow,
    Active,
    Incompatible,
    Retired
}

public enum AgentOrderPermissionMode
{
    SuggestOnly,
    ConfirmEveryOrder,
    BoundedAutonomy
}

public enum AgentOrderDecision
{
    Suggested,
    PendingConfirmation,
    Authorized,
    Rejected,
    Expired,
    Revoked
}

public sealed record ComputeDevice(
    string DeviceId,
    ComputeDeviceType Type,
    string Vendor,
    string Model,
    string DriverOrRuntimeVersion,
    long? MemoryBytes,
    IReadOnlyList<string> SupportedPrecisions,
    IReadOnlyList<string> SupportedBackends,
    bool TrainingSupported,
    bool InferenceSupported,
    ComputeHealth Health,
    string FailureReason)
{
    public string Name => $"{Vendor} {Model}".Trim();
    public string Runtime => DriverOrRuntimeVersion;
    public string Reason => FailureReason;
}

public sealed record ComputePolicy(
    string PreferredDeviceId,
    bool AllowCpuFallback,
    int MaxConcurrentJobs,
    int MaxThreads,
    long MaxMemoryBytes,
    ComputeSchedulingMode SchedulingMode = ComputeSchedulingMode.Auto);

public sealed record ComputeResourceLimits(
    int TimeoutSeconds,
    int MaxThreads,
    long MaxMemoryBytes,
    long MaxGpuMemoryBytes,
    int MaxEpochs,
    int MaxTrials,
    long MaxOutputBytes);

public sealed record AgentCostPolicy(
    int CallLimit,
    int InputTokenLimit,
    int OutputTokenLimit,
    decimal DailySpendingLimit,
    decimal MonthlySpendingLimit,
    decimal ConfirmationThreshold);

public sealed record ComputeJob(
    string JobId,
    ComputeJobType Type,
    ComputeJobStatus Status,
    string ProjectId,
    string DeviceId,
    int Seed,
    DateTimeOffset CreatedAt,
    DateTimeOffset? CompletedAt,
    IReadOnlyDictionary<string, string> ArtifactReferences,
    string Message);

public sealed record AlgorithmProjectFile(
    string RelativePath,
    string Sha256,
    long SizeBytes);

public sealed record AlgorithmProjectVersion(
    int Version,
    DateTimeOffset CreatedAt,
    string Source,
    IReadOnlyList<AlgorithmProjectFile> Files);

public sealed record AlgorithmProject(
    string ProjectId,
    string Name,
    string ProjectType,
    int CurrentVersion,
    IReadOnlyList<AlgorithmProjectVersion> Versions);

public sealed record AgentProjectPatch(
    string PatchId,
    string ProjectId,
    string RelativePath,
    string NewContent,
    string Rationale,
    int EstimatedTokenCost);

public sealed record TrainingCheckpoint(
    string CheckpointId,
    string JobId,
    int Epoch,
    string ArtifactPath,
    string Sha256);

public sealed record OnnxModelRecord(
    string ModelId,
    string Name,
    string Version,
    OnnxModelStatus Status,
    string ArtifactPath,
    string Sha256,
    IReadOnlyList<string> InputNames,
    IReadOnlyList<string> OutputNames,
    IReadOnlyList<string> CompatibleProviders,
    DateTimeOffset ImportedAt,
    string DatasetVersion = "",
    IReadOnlyDictionary<string, string>? FeatureMetadata = null,
    IReadOnlyDictionary<string, string>? NormalizationMetadata = null,
    string PreferredProvider = "CPUExecutionProvider",
    IReadOnlyList<string>? FallbackProviders = null,
    string ActualProviderUsed = "",
    IReadOnlyList<string>? StrategyBindings = null,
    IReadOnlyList<string>? DependencyIds = null);

public sealed record ExecutionModuleProposal(
    string ProposalId,
    string ModuleId,
    string IntentId,
    string Symbol,
    string Side,
    decimal Quantity,
    decimal LimitPrice,
    bool RequiresExecutionGateway,
    string Reason);

public sealed record ExecutionModuleRecord(
    string ModuleId,
    string Name,
    string Version,
    string Status,
    bool RequiresExecutionGateway);

public sealed record LongbridgeAccountFixture(
    string AccountId,
    string DisplayName,
    string Channel,
    string Market,
    bool IsSynthetic);

public sealed record StrategyAccountMapping(
    string StrategyId,
    string AccountId,
    string Market,
    string Source);

public sealed record AgentOrderAuthorization(
    string AuthorizationId,
    AgentOrderPermissionMode Mode,
    IReadOnlyList<string> AllowedStrategies,
    IReadOnlyList<string> AllowedSymbols,
    decimal MaxNotionalPerOrder,
    decimal MaxDailyNotional,
    int MaxOrdersPerDay,
    DateTimeOffset ExpiresAt,
    bool Revoked,
    IReadOnlyList<string>? AllowedAccounts = null,
    IReadOnlyList<string>? AllowedMarkets = null,
    IReadOnlyList<string>? AllowedOrderTypes = null,
    decimal MaximumPosition = decimal.MaxValue,
    decimal MaximumDailyLoss = decimal.MaxValue,
    double MinimumConfidence = 0,
    DateTimeOffset? ValidFrom = null,
    bool OutsideRegularHoursPermission = false)
{
    public IReadOnlyList<string> AllowedSymbolsOrUniverse => AllowedSymbols;
    public decimal MaximumOrderValue => MaxNotionalPerOrder;
    public decimal MaximumDailyValue => MaxDailyNotional;
}

public sealed record AgentOrderIntent(
    string IntentId,
    string AuthorizationId,
    string StrategyId,
    string Symbol,
    string Side,
    decimal Quantity,
    decimal ReferencePrice,
    DateTimeOffset CreatedAt,
    string AgentSessionId = "",
    string ModelId = "",
    string AccountId = "",
    string Market = "US",
    string OrderType = "Market",
    decimal? LimitPrice = null,
    string TimeInForce = "Day",
    bool OutsideRegularHours = false,
    string Reason = "",
    double Confidence = 1,
    DateTimeOffset? ExpiresAt = null)
{
    public decimal QuantityOrNotional => Quantity;
}

public sealed record AgentOrderEvaluation(
    AgentOrderDecision Decision,
    string Reason,
    decimal Notional);

public sealed record LocalStudioState(
    int SchemaVersion,
    IReadOnlyList<AlgorithmProject> Projects,
    IReadOnlyList<ComputeJob> Jobs,
    IReadOnlyList<TrainingCheckpoint> Checkpoints,
    IReadOnlyList<OnnxModelRecord> Models,
    IReadOnlyList<ExecutionModuleRecord> ExecutionModules,
    IReadOnlyList<LongbridgeAccountFixture> Accounts,
    IReadOnlyList<StrategyAccountMapping> AccountMappings,
    IReadOnlyList<AgentOrderAuthorization> AgentAuthorizations)
{
    public static LocalStudioState Empty { get; } = new(
        1,
        Array.Empty<AlgorithmProject>(),
        Array.Empty<ComputeJob>(),
        Array.Empty<TrainingCheckpoint>(),
        Array.Empty<OnnxModelRecord>(),
        Array.Empty<ExecutionModuleRecord>(),
        Array.Empty<LongbridgeAccountFixture>(),
        Array.Empty<StrategyAccountMapping>(),
        Array.Empty<AgentOrderAuthorization>());
}
