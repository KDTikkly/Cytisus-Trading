import Foundation

enum ComputeDeviceType: String, Codable, CaseIterable {
    case cpu = "CPU"
    case appleMetal = "AppleMetal"
    case nvidiaCUDA = "NvidiaCUDA"
    case amdROCm = "AmdROCm"
    case intelOpenVINO = "IntelOpenVINO"
    case npu = "NPU"
}

enum ComputeHealth: String, Codable {
    case ready = "Ready"
    case unavailable = "Unavailable"
    case degraded = "Degraded"
}

enum ComputeJobType: String, Codable, CaseIterable {
    case factorCalculation = "FactorCalculation"
    case backtest = "Backtest"
    case walkForwardBacktest = "WalkForwardBacktest"
    case parameterSearch = "ParameterSearch"
    case portfolioOptimization = "PortfolioOptimization"
    case monteCarlo = "MonteCarlo"
    case trainModel = "TrainModel"
    case exportONNX = "ExportONNX"
    case testONNX = "TestONNX"
    case benchmarkInference = "BenchmarkInference"
    case validateProject = "ValidateProject"
    case simulateExecutionAlgorithm = "SimulateExecutionAlgorithm"
}

enum ComputeJobStatus: String, Codable {
    case queued = "Queued"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

enum ComputeSchedulingMode: String, Codable, CaseIterable {
    case auto = "Auto"
    case cpuOnly = "CPUOnly"
    case preferGPU = "PreferGPU"
    case preferNPUForInference = "PreferNPUForInference"
    case specificDevice = "SpecificDevice"
    case maximumPerformance = "MaximumPerformance"
    case balanced = "Balanced"
    case batterySaver = "BatterySaver"
}

enum ONNXModelStatus: String, Codable {
    case draft = "Draft"
    case imported = "Imported"
    case validated = "Validated"
    case backtested = "Backtested"
    case shadow = "Shadow"
    case active = "Active"
    case incompatible = "Incompatible"
    case retired = "Retired"
}

enum AgentOrderPermissionMode: String, Codable, CaseIterable {
    case suggestOnly = "SuggestOnly"
    case confirmEveryOrder = "ConfirmEveryOrder"
    case boundedAutonomy = "BoundedAutonomy"
}

enum AgentOrderDecision: String, Codable {
    case suggested = "Suggested"
    case pendingConfirmation = "PendingConfirmation"
    case authorized = "Authorized"
    case rejected = "Rejected"
    case expired = "Expired"
    case revoked = "Revoked"
}

struct ComputeDevice: Codable, Identifiable {
    let deviceId: String
    let type: ComputeDeviceType
    let vendor: String
    let model: String
    let driverOrRuntimeVersion: String
    let memoryBytes: Int64?
    let supportedPrecisions: [String]
    let supportedBackends: [String]
    let trainingSupported: Bool
    let inferenceSupported: Bool
    let health: ComputeHealth
    let failureReason: String

    var id: String { deviceId }
    var name: String { "\(vendor) \(model)".trimmingCharacters(in: .whitespaces) }
    var runtime: String { driverOrRuntimeVersion }
    var reason: String { failureReason }
}

struct ComputePolicy: Codable {
    let preferredDeviceId: String
    let allowCPUFallback: Bool
    let maxConcurrentJobs: Int
    let maxThreads: Int
    let maxMemoryBytes: Int64
    let schedulingMode: ComputeSchedulingMode = .auto
}

struct ComputeResourceLimits: Codable {
    let timeoutSeconds: Int
    let maxThreads: Int
    let maxMemoryBytes: Int64
    let maxGPUMemoryBytes: Int64
    let maxEpochs: Int
    let maxTrials: Int
    let maxOutputBytes: Int64
}

struct AgentCostPolicy: Codable {
    let callLimit: Int
    let inputTokenLimit: Int
    let outputTokenLimit: Int
    let dailySpendingLimit: Double
    let monthlySpendingLimit: Double
    let confirmationThreshold: Double
}

struct ComputeJob: Codable, Identifiable {
    let jobId: String
    let type: ComputeJobType
    let status: ComputeJobStatus
    let projectId: String
    let deviceId: String
    let seed: Int
    let createdAt: Date
    let completedAt: Date?
    let artifactReferences: [String: String]
    let message: String

    var id: String { jobId }
}

struct AlgorithmProjectFile: Codable, Identifiable {
    let relativePath: String
    let sha256: String
    let sizeBytes: Int64

    var id: String { relativePath }
}

struct AlgorithmProjectVersion: Codable, Identifiable {
    let version: Int
    let createdAt: Date
    let source: String
    let files: [AlgorithmProjectFile]

    var id: Int { version }
}

struct AlgorithmProject: Codable, Identifiable {
    let projectId: String
    let name: String
    let projectType: String
    let currentVersion: Int
    let versions: [AlgorithmProjectVersion]

    var id: String { projectId }
}

struct AgentProjectPatch: Codable {
    let patchId: String
    let projectId: String
    let relativePath: String
    let newContent: String
    let rationale: String
    let estimatedTokenCost: Int
}

struct TrainingCheckpoint: Codable, Identifiable {
    let checkpointId: String
    let jobId: String
    let epoch: Int
    let artifactPath: String
    let sha256: String

    var id: String { checkpointId }
}

struct ONNXModelRecord: Codable, Identifiable {
    let modelId: String
    let name: String
    let version: String
    let status: ONNXModelStatus
    let artifactPath: String
    let sha256: String
    let inputNames: [String]
    let outputNames: [String]
    let compatibleProviders: [String]
    let importedAt: Date
    let datasetVersion: String = ""
    let featureMetadata: [String: String] = [:]
    let normalizationMetadata: [String: String] = [:]
    let preferredProvider: String = "CPUExecutionProvider"
    let fallbackProviders: [String] = []
    let actualProviderUsed: String = ""
    let strategyBindings: [String] = []
    let dependencyIds: [String] = []

    var id: String { modelId }
}

struct ExecutionModuleProposal: Codable, Identifiable {
    let proposalId: String
    let moduleId: String
    let intentId: String
    let symbol: String
    let side: String
    let quantity: Double
    let limitPrice: Double
    let requiresExecutionGateway: Bool
    let reason: String

    var id: String { proposalId }
}

struct ExecutionModuleRecord: Codable, Identifiable {
    let moduleId: String
    let name: String
    let version: String
    let status: String
    let requiresExecutionGateway: Bool

    var id: String { moduleId }
}

struct LongbridgeAccountFixture: Codable, Identifiable {
    let accountId: String
    let displayName: String
    let channel: String
    let market: String
    let isSynthetic: Bool

    var id: String { accountId }
}

struct StrategyAccountMapping: Codable, Identifiable {
    let strategyId: String
    let accountId: String
    let market: String
    let source: String

    var id: String { "\(strategyId):\(accountId):\(market)" }
}

struct AgentOrderAuthorization: Codable, Identifiable {
    let authorizationId: String
    let mode: AgentOrderPermissionMode
    let allowedStrategies: [String]
    let allowedSymbols: [String]
    let maxNotionalPerOrder: Double
    let maxDailyNotional: Double
    let maxOrdersPerDay: Int
    let expiresAt: Date
    let revoked: Bool
    let allowedAccounts: [String] = []
    let allowedMarkets: [String] = []
    let allowedOrderTypes: [String] = []
    let maximumPosition: Double = .greatestFiniteMagnitude
    let maximumDailyLoss: Double = .greatestFiniteMagnitude
    let minimumConfidence: Double = 0
    let validFrom: Date? = nil
    let outsideRegularHoursPermission: Bool = false

    var id: String { authorizationId }
    var allowedSymbolsOrUniverse: [String] { allowedSymbols }
    var maximumOrderValue: Double { maxNotionalPerOrder }
    var maximumDailyValue: Double { maxDailyNotional }
}

struct AgentOrderIntent: Codable, Identifiable {
    let intentId: String
    let authorizationId: String
    let strategyId: String
    let symbol: String
    let side: String
    let quantity: Double
    let referencePrice: Double
    let createdAt: Date
    let agentSessionId: String = ""
    let modelId: String = ""
    let accountId: String = ""
    let market: String = "US"
    let orderType: String = "Market"
    let limitPrice: Double? = nil
    let timeInForce: String = "Day"
    let outsideRegularHours: Bool = false
    let reason: String = ""
    let confidence: Double = 1
    let expiresAt: Date? = nil

    var id: String { intentId }
    var quantityOrNotional: Double { quantity }
}

struct AgentOrderEvaluation: Codable {
    let decision: AgentOrderDecision
    let reason: String
    let notional: Double
}

struct LocalStudioState: Codable {
    let schemaVersion: Int
    let projects: [AlgorithmProject]
    let jobs: [ComputeJob]
    let checkpoints: [TrainingCheckpoint]
    let models: [ONNXModelRecord]
    let executionModules: [ExecutionModuleRecord]
    let accounts: [LongbridgeAccountFixture]
    let accountMappings: [StrategyAccountMapping]
    let agentAuthorizations: [AgentOrderAuthorization]

    static let empty = LocalStudioState(
        schemaVersion: 1,
        projects: [],
        jobs: [],
        checkpoints: [],
        models: [],
        executionModules: [],
        accounts: [],
        accountMappings: [],
        agentAuthorizations: []
    )
}
