import Foundation

enum FactorTaskType: String, Codable, CaseIterable {
    case alpha = "Alpha"
    case risk = "Risk"
    case regime = "Regime"
    case liquidity = "Liquidity"
    case execution = "Execution"
}

enum FactorTrialResult: String, Codable {
    case candidate = "Candidate"
    case rejected = "Rejected"
    case quarantined = "Quarantined"
}

enum FactorMissingValuePolicy: String, Codable {
    case propagate = "Propagate"
    case ignoreWindowMissing = "IgnoreWindowMissing"
    case crossSectionMedian = "CrossSectionMedian"
}

enum FactorHorizons {
    static let daily = ["1d", "3d", "5d", "10d", "20d", "60d", "120d", "252d"]
    static let reservedIntraday = Set(["1m", "5m", "30m"])

    static func days(_ horizon: String) throws -> Int {
        guard daily.contains(horizon),
              let value = Int(horizon.dropLast()) else {
            throw FactorDSLError.invalidDefinition(
                "Only standard daily horizons are evaluated."
            )
        }
        return value
    }
}

struct FactorDefinition: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let factorId: String
    let factorType: FactorTaskType
    let target: String
    let horizon: String
    let universe: String
    let requiredData: [String]
    let updateFrequency: String
    let version: Int
    let state: FactorState
    let expression: String
    let strategyStates: [String: FactorState]

    var id: String { factorId }
}

struct FactorEvidence: Codable, Equatable {
    let coverage: Double
    let missingRate: Double
    let taskMetric: Double
    let taskMetricName: String
    let stability: Double
    let turnover: Double
    let costProxy: Double
    let capacityProxy: Double
    let existingFactorCorrelation: Double
    let neighboringHorizonStability: Double
    let marginalContribution: Double
    let oosWindows: Int
    let multipleTestingPenalty: Double
    let regimeEvidence: String
}

struct FactorTrial: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let trialId: String
    let factorFamily: String
    let expression: String
    let parameters: [String: String]
    let datasetVersion: String
    let universeVersion: String
    let searchAlgorithm: String
    let generation: Int
    let oosWindows: Int
    let metrics: [String: Double]
    let result: FactorTrialResult
    let rejectionReason: String?
    let createdAt: Date

    var id: String { trialId }
}

struct FactorResearchSummary: Identifiable, Equatable {
    let definition: FactorDefinition
    let globalState: FactorState
    let strategyState: FactorState
    let trialCount: Int
    let evidence: FactorEvidence
    let stateReason: String

    var id: String { definition.factorId }
    var name: String {
        definition.factorId.replacingOccurrences(of: "-", with: " ")
    }
    var oosEvidence: String {
        "\(evidence.oosWindows) windows | \(evidence.taskMetricName) " +
            String(format: "%.3f", evidence.taskMetric)
    }
}

struct ResearchObservation: Equatable {
    let symbol: String
    let industry: String
    let eventTime: Date
    let availableTime: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let returns: Double
    let marketReturn: Double
    let sectorReturn: Double
    let capitalFlow: Double

    func field(_ name: String) throws -> Double {
        switch name {
        case "open": return open
        case "high": return high
        case "low": return low
        case "close": return close
        case "volume": return volume
        case "returns": return returns
        case "market_return": return marketReturn
        case "sector_return": return sectorReturn
        case "capital_flow": return capitalFlow
        default:
            throw FactorDSLError.invalidDefinition(
                "Unknown research field: \(name)"
            )
        }
    }
}

struct NormalizedResearchDataset: Equatable {
    let datasetVersion: String
    let universeVersion: String
    let createdAt: Date
    let observations: [ResearchObservation]
}

struct FactorSearchConfiguration: Equatable {
    let beamWidth: Int
    let topK: Int
    let maximumGenerations: Int
    let maximumCandidates: Int
    let maximumDepth: Int
    let maximumOperators: Int

    static let tiny = FactorSearchConfiguration(
        beamWidth: 4,
        topK: 3,
        maximumGenerations: 2,
        maximumCandidates: 24,
        maximumDepth: 8,
        maximumOperators: 16
    )
}

struct FactorSearchResult {
    let status: String
    let evaluatedCount: Int
    let candidateCount: Int
    let rejectedCount: Int
    let quarantinedCount: Int
    let trials: [FactorTrial]
    let summaries: [FactorResearchSummary]
}

struct FactorLifecycleEvidence {
    let dataContamination: Bool
    let lookAheadBias: Bool
    let trainTestLeakage: Bool
    let unreproducibleResult: Bool
    let definitionError: Bool
    let trialRecordPresent: Bool
    let shortTermScore: Double
    let longTermScore: Double
    let regimeSpecificFailure: Bool
    let repeatedOosFailures: Int
    let changePointProbability: Double
    let counterfactualImprovement: Double
    let renewedEvidence: Bool
}

struct FactorLifecycleDecision {
    let state: FactorState
    let global: Bool
    let blocksRiskExpansion: Bool
    let riskMultiplier: Double
    let reason: String
}

struct RegimeInput: Codable, Equatable {
    let trendStrength: Double
    let rangeScore: Double
    let realizedVolatility: Double
    let crossAssetRisk: Double
    let strategyReportedFit: [String: Double]
}

struct RegimeSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let asOf: Date
    let probabilities: [String: Double]
    let uncertainty: Double
    let riskMultiplier: Double
    let explanation: [String: Double]

    var trend: Double { probabilities["Trend"] ?? 0 }
    var range: Double { probabilities["Range"] ?? 0 }
    var highVolatility: Double {
        probabilities["HighVolatility"] ?? 0
    }
    var crisis: Double { probabilities["Crisis"] ?? 0 }
}

struct StrategyAllocationInput: Codable, Equatable {
    let strategyId: String
    let health: HealthState
    let isNew: Bool
    let longTermOos: Double
    let recentLive: Double
    let recentPaper: Double
    let signalStrength: Double
    let regimeFit: Double
    let confidenceCalibration: Double
    let dataQuality: Double
    let modelUncertainty: Double
    let volatility: Double
    let averageCorrelation: Double
    let drawdown: Double
    let capacity: Double
    let liquidity: Double
    let currentWeight: Double
}

struct RegimeAllocationFixture: Codable, Equatable {
    let schemaVersion: Int
    let regimeInput: RegimeInput
    let totalCapital: Double
    let baseRiskFraction: Double
    let strategies: [StrategyAllocationInput]
}

struct StrategyCapitalAllocation: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let strategyId: String
    let finalWeight: Double
    let capitalBudget: Double
    let explanation: [String: Double]

    var id: String { strategyId }
    var explanationText: String {
        let base = explanation["base_weight"] ?? 0
        let alpha = explanation["alpha_tilt"] ?? 0
        let correlation = explanation["correlation_penalty"] ?? 0
        let drawdown = explanation["drawdown_penalty"] ?? 0
        let capacity = explanation["capacity_penalty"] ?? 0
        let liquidity = explanation["liquidity_penalty"] ?? 0
        return String(
            format: "Base %.1f%% | Alpha %+.3f | Correlation %.3f | Drawdown %.3f | Capacity %.3f | Liquidity %.3f",
            base * 100,
            alpha,
            correlation,
            drawdown,
            capacity,
            liquidity
        )
    }
}

struct CapitalAllocationResult: Equatable {
    let totalRiskBudget: Double
    let regime: RegimeSnapshot
    let allocations: [StrategyCapitalAllocation]
}
