import Foundation

enum OrderSide: String, Codable {
    case buy = "Buy"
    case sell = "Sell"
}

enum RiskDecisionOutcome: String, Codable {
    case accepted = "Accepted"
    case rejected = "Rejected"
}

enum BrokerOrderState: String, Codable {
    case accepted = "Accepted"
    case rejected = "Rejected"
    case fullyFilled = "FullyFilled"
    case partiallyFilled = "PartiallyFilled"
    case expired = "Expired"
    case ambiguous = "Ambiguous"
}

enum ReconciliationStatus: String, Codable {
    case reconciled = "Reconciled"
    case mismatch = "Mismatch"
}

enum LiveSubmissionState: String, Codable {
    case disabled = "Disabled"
    case commandConstructed = "CommandConstructed"
    case rejected = "Rejected"
    case submitted = "Submitted"
    case ambiguous = "Ambiguous"
}

struct TradeIntent: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let intentId: String
    let strategyId: String
    let strategyVersion: String
    let cycleId: String
    let settlementCycle: String
    let symbol: String
    let requestedQuantity: Double
    let priority: Int
    let allowPartial: Bool
    let minimumEffectiveFill: Double
    let timeToLiveSeconds: Int
    let reasonCode: String
    let parameterVersion: Int
    let createdAt: Date

    var id: String { intentId }
    var side: OrderSide { requestedQuantity >= 0 ? .buy : .sell }
    var absoluteQuantity: Double { abs(requestedQuantity) }
}

struct RiskDecision: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let decisionId: String
    let intentId: String
    let strategyId: String
    let symbol: String
    let outcome: RiskDecisionOutcome
    let reason: String
    let correlationId: String
    let createdAt: Date

    var id: String { decisionId }
}

struct InternalTransfer: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let transferId: String
    let symbol: String
    let settlementCycle: String
    let buyerStrategyId: String
    let sellerStrategyId: String
    let quantity: Double
    let referencePrice: Double
    let referencePriceSource: String
    let buyerIntentId: String
    let sellerIntentId: String
    let correlationId: String
    let createdAt: Date

    var id: String { transferId }
    var display: String {
        "\(symbol) | \(sellerStrategyId) -> \(buyerStrategyId) | " +
            String(format: "%.4f @ %.2f", quantity, referencePrice)
    }
}

struct BrokerOrder: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let orderId: String
    let correlationId: String
    let symbol: String
    let side: OrderSide
    let quantity: Double
    let referencePrice: Double
    let mode: StrategyMode
    let state: BrokerOrderState
    let createdAt: Date
    let expiresAt: Date
    let submissionAttempts: Int
    let statusMessage: String

    var id: String { orderId }
    var modeLabel: String {
        mode == .paperOnly ? "Local Paper" : "Live"
    }
}

struct BrokerFill: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let fillId: String
    let orderId: String
    let correlationId: String
    let symbol: String
    let side: OrderSide
    let quantity: Double
    let price: Double
    let slippageEstimate: Double
    let feeEstimate: Double
    let filledAt: Date

    var id: String { fillId }
}

struct VirtualAllocation: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let allocationId: String
    let fillId: String
    let intentId: String
    let strategyId: String
    let symbol: String
    let side: OrderSide
    let quantity: Double
    let price: Double
    let fee: Double
    let correlationId: String
    let createdAt: Date

    var id: String { allocationId }
}

struct AllocationShortfall: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let shortfallId: String
    let intentId: String
    let strategyId: String
    let symbol: String
    let requestedQuantity: Double
    let allocatedQuantity: Double
    let unfilledQuantity: Double
    let reason: String
    let correlationId: String
    let createdAt: Date

    var id: String { shortfallId }
}

struct VirtualLedgerPosition: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let strategyId: String
    let symbol: String
    let targetPosition: Double
    let virtualQuantity: Double
    let costBasis: Double
    let realizedPnl: Double
    let unrealizedPnl: Double
    let capitalUsage: Double
    let riskContribution: Double
    let intentIds: [String]
    let allocationIds: [String]
    let internalTransferIds: [String]
    let updatedAt: Date

    var id: String { "\(strategyId)|\(symbol)" }
}

struct ReconciliationEvent: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let reconciliationId: String
    let symbol: String
    let virtualQuantity: Double
    let brokerQuantity: Double
    let difference: Double
    let status: ReconciliationStatus
    let blocksNewRisk: Bool
    let diagnostic: String
    let correlationId: String
    let createdAt: Date

    var id: String { reconciliationId }
}

struct CriticalRiskEvent: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let riskEventId: String
    let symbol: String
    let severity: String
    let message: String
    let persistent: Bool
    let correlationId: String
    let createdAt: Date

    var id: String { riskEventId }
}

struct ExecutionStateSnapshot: Codable, Equatable {
    let schemaVersion: Int
    var intents: [TradeIntent]
    var riskDecisions: [RiskDecision]
    var internalTransfers: [InternalTransfer]
    var brokerOrders: [BrokerOrder]
    var brokerFills: [BrokerFill]
    var virtualAllocations: [VirtualAllocation]
    var allocationShortfalls: [AllocationShortfall]
    var ledgerPositions: [VirtualLedgerPosition]
    var reconciliations: [ReconciliationEvent]
    var riskEvents: [CriticalRiskEvent]
    var blockedSymbols: Set<String>

    static let empty = ExecutionStateSnapshot(
        schemaVersion: 1,
        intents: [],
        riskDecisions: [],
        internalTransfers: [],
        brokerOrders: [],
        brokerFills: [],
        virtualAllocations: [],
        allocationShortfalls: [],
        ledgerPositions: [],
        reconciliations: [],
        riskEvents: [],
        blockedSymbols: []
    )
}

struct ExecutionGatewayContext {
    let mode: StrategyMode
    let globalLiveLock: Bool
    let authorization: LiveAuthorization?
    let dataFresh: Bool
    let marketAllowed: Bool
    let strategyHealth: HealthState
    let capitalBudget: Double
    let maximumPositionExposure: Double
    let cliReady: Bool
    let liveAdapterEnabled: Bool
    let fixtureMode: Bool
    let parameterVersion: Int
    let market: String
    let now: Date
    let dailyLoss: Double
    let drawdown: Double
    let outsideRegularHours: Bool
    let transitionActive: Bool
    let transitionPolicy: LiveToPaperTransition
}

struct GatewayBatchResult {
    let state: ExecutionStateSnapshot
    let decisions: [RiskDecision]
    let transfers: [InternalTransfer]
    let orders: [BrokerOrder]
    let fills: [BrokerFill]
    let allocations: [VirtualAllocation]
    let shortfalls: [AllocationShortfall]
    let reconciliations: [ReconciliationEvent]
}

struct PaperBrokerConfiguration {
    let fillRatio: Double
    let slippageBasisPoints: Double
    let feePerUnit: Double
    let minimumFee: Double
    let rejectOrders: Bool
    let expireOrders: Bool
}

struct BrokerSubmissionResult {
    let order: BrokerOrder
    let fill: BrokerFill?
}

struct LongbridgeExecutionCapability: Codable, Equatable {
    let schemaVersion: Int
    let sourceVersion: String
    let syntheticFixture: Bool
    let supportsMachineReadableOutput: Bool
    let supportsOrderSubmission: Bool
    let argumentTemplate: [String]
    let message: String
}

struct LiveAdapterConfiguration {
    let enabled: Bool
    let fixtureMode: Bool
    let executableURL: URL?
    let timeout: TimeInterval
    let capability: LongbridgeExecutionCapability
}

struct LiveSubmissionResult {
    let state: LiveSubmissionState
    let order: BrokerOrder
    let arguments: [String]
    let retryPermitted: Bool
    let message: String
}

struct FixtureLedgerSeed: Codable, Equatable {
    let strategyId: String
    let virtualQuantity: Double
    let costBasis: Double
}

struct PaperGatewayFixture: Codable, Equatable {
    let schemaVersion: Int
    let asOf: Date
    let market: String
    let symbol: String
    let referencePrice: Double
    let referencePriceSource: String
    let startingBrokerQuantity: Double
    let paperFillRatio: Double
    let startingLedger: [FixtureLedgerSeed]
    let intents: [TradeIntent]
}

struct ReconciliationFailureFixture: Codable, Equatable {
    let schemaVersion: Int
    let asOf: Date
    let symbol: String
    let virtualQuantity: Double
    let brokerQuantity: Double
    let expectedStatus: ReconciliationStatus
    let expectedBlocksNewRisk: Bool
}
