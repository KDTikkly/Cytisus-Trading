import Foundation

struct NettingResult {
    let transfers: [InternalTransfer]
    let residualIntents: [TradeIntent]
}

struct FillAllocationResult {
    let allocations: [VirtualAllocation]
    let shortfalls: [AllocationShortfall]
}

final class InternalNettingService {
    func net(
        _ intents: [TradeIntent],
        referencePrice: Double,
        referencePriceSource: String,
        correlationId: String,
        now: Date
    ) -> NettingResult {
        var transfers: [InternalTransfer] = []
        var residuals: [TradeIntent] = []
        let groups = Dictionary(grouping: intents) {
            "\($0.symbol)|\($0.settlementCycle)"
        }
        for key in groups.keys.sorted() {
            guard let group = groups[key] else { continue }
            let buys = group.filter {
                $0.requestedQuantity > 0
            }.sorted(by: priorityOrder)
            let sells = group.filter {
                $0.requestedQuantity < 0
            }.sorted(by: priorityOrder)
            var remaining = Dictionary(
                uniqueKeysWithValues: group.map {
                    ($0.intentId, $0.absoluteQuantity)
                }
            )
            var buyIndex = 0
            var sellIndex = 0
            while buyIndex < buys.count && sellIndex < sells.count {
                let buy = buys[buyIndex]
                let sell = sells[sellIndex]
                let quantity = min(
                    remaining[buy.intentId] ?? 0,
                    remaining[sell.intentId] ?? 0
                )
                if quantity > 0 {
                    transfers.append(
                        InternalTransfer(
                            schemaVersion: 1,
                            transferId: Self.stableId(
                                "transfer",
                                "\(buy.intentId)|\(sell.intentId)|\(quantity)"
                            ),
                            symbol: buy.symbol,
                            settlementCycle: buy.settlementCycle,
                            buyerStrategyId: buy.strategyId,
                            sellerStrategyId: sell.strategyId,
                            quantity: quantity,
                            referencePrice: referencePrice,
                            referencePriceSource: referencePriceSource,
                            buyerIntentId: buy.intentId,
                            sellerIntentId: sell.intentId,
                            correlationId: correlationId,
                            createdAt: now
                        )
                    )
                    remaining[buy.intentId] =
                        (remaining[buy.intentId] ?? 0) - quantity
                    remaining[sell.intentId] =
                        (remaining[sell.intentId] ?? 0) - quantity
                }
                if (remaining[buy.intentId] ?? 0) <= 0.00000001 {
                    buyIndex += 1
                }
                if (remaining[sell.intentId] ?? 0) <= 0.00000001 {
                    sellIndex += 1
                }
            }
            for intent in group.sorted(by: priorityOrder) {
                let quantity = remaining[intent.intentId] ?? 0
                guard quantity > 0.00000001 else { continue }
                residuals.append(copy(
                    intent,
                    requestedQuantity:
                        intent.side == .buy ? quantity : -quantity
                ))
            }
        }
        return NettingResult(
            transfers: transfers,
            residualIntents: residuals
        )
    }

    static func stableId(_ prefix: String, _ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "\(prefix)-" + String(format: "%016llx", hash)
    }

    private func priorityOrder(
        _ left: TradeIntent,
        _ right: TradeIntent
    ) -> Bool {
        left.priority == right.priority
            ? left.intentId < right.intentId
            : left.priority > right.priority
    }

    private func copy(
        _ value: TradeIntent,
        requestedQuantity: Double
    ) -> TradeIntent {
        TradeIntent(
            schemaVersion: value.schemaVersion,
            intentId: value.intentId,
            strategyId: value.strategyId,
            strategyVersion: value.strategyVersion,
            cycleId: value.cycleId,
            settlementCycle: value.settlementCycle,
            symbol: value.symbol,
            requestedQuantity: requestedQuantity,
            priority: value.priority,
            allowPartial: value.allowPartial,
            minimumEffectiveFill: value.minimumEffectiveFill,
            timeToLiveSeconds: value.timeToLiveSeconds,
            reasonCode: value.reasonCode,
            parameterVersion: value.parameterVersion,
            createdAt: value.createdAt
        )
    }
}

final class PartialFillAllocator {
    private let unit = 0.0001

    func allocate(
        fill: BrokerFill,
        demands: [TradeIntent],
        correlationId: String,
        now: Date
    ) -> FillAllocationResult {
        let matching = demands.filter {
            $0.symbol == fill.symbol && $0.side == fill.side
        }.sorted {
            $0.priority == $1.priority
                ? $0.intentId < $1.intentId
                : $0.priority > $1.priority
        }
        var allocated = Dictionary(
            uniqueKeysWithValues: matching.map { ($0.intentId, 0.0) }
        )
        var available = fill.quantity
        let priorityGroups = Dictionary(
            grouping: matching,
            by: \.priority
        )
        for priority in priorityGroups.keys.sorted(by: >) {
            guard available > 0,
                  let group = priorityGroups[priority] else { break }
            let values = group.sorted { $0.intentId < $1.intentId }
            let totalDemand = values.map(\.absoluteQuantity).reduce(0, +)
            if available >= totalDemand {
                for intent in values {
                    allocated[intent.intentId] = intent.absoluteQuantity
                }
                available -= totalDemand
                continue
            }
            var partial = values.filter(\.allowPartial)
            while !partial.isEmpty && available > 0 {
                let demand = partial.map(\.absoluteQuantity).reduce(0, +)
                let proposed = Dictionary(
                    uniqueKeysWithValues: partial.map {
                        (
                            $0.intentId,
                            roundDown(
                                available * $0.absoluteQuantity / demand
                            )
                        )
                    }
                )
                let unusable = partial.filter {
                    (proposed[$0.intentId] ?? 0) <
                        $0.minimumEffectiveFill
                }
                if unusable.isEmpty {
                    for intent in partial {
                        allocated[intent.intentId] = min(
                            intent.absoluteQuantity,
                            proposed[intent.intentId] ?? 0
                        )
                    }
                    let used = partial.map {
                        allocated[$0.intentId] ?? 0
                    }.reduce(0, +)
                    var remainder = available - used
                    for intent in partial.sorted(
                        by: { $0.intentId < $1.intentId }
                    ) {
                        guard remainder >= unit else { break }
                        let capacity = intent.absoluteQuantity -
                            (allocated[intent.intentId] ?? 0)
                        let addition = min(capacity, remainder)
                        allocated[intent.intentId, default: 0] += addition
                        remainder -= addition
                    }
                    available = remainder
                    break
                }
                let blocked = Set(unusable.map(\.intentId))
                partial.removeAll { blocked.contains($0.intentId) }
            }
            break
        }

        let allocations = matching.compactMap { intent
            -> VirtualAllocation? in
            let quantity = allocated[intent.intentId] ?? 0
            guard quantity > 0 else { return nil }
            let fee = fill.feeEstimate * quantity /
                max(fill.quantity, unit)
            return VirtualAllocation(
                schemaVersion: 1,
                allocationId: InternalNettingService.stableId(
                    "allocation",
                    "\(fill.fillId)|\(intent.intentId)|\(quantity)"
                ),
                fillId: fill.fillId,
                intentId: intent.intentId,
                strategyId: intent.strategyId,
                symbol: intent.symbol,
                side: intent.side,
                quantity: quantity,
                price: fill.price,
                fee: fee,
                correlationId: correlationId,
                createdAt: now
            )
        }
        let shortfalls = matching.compactMap { intent
            -> AllocationShortfall? in
            let amount = allocated[intent.intentId] ?? 0
            guard intent.absoluteQuantity - amount > 0.00000001 else {
                return nil
            }
            return AllocationShortfall(
                schemaVersion: 1,
                shortfallId: InternalNettingService.stableId(
                    "shortfall",
                    "\(fill.fillId)|\(intent.intentId)|\(amount)"
                ),
                intentId: intent.intentId,
                strategyId: intent.strategyId,
                symbol: intent.symbol,
                requestedQuantity: intent.absoluteQuantity,
                allocatedQuantity: amount,
                unfilledQuantity: intent.absoluteQuantity - amount,
                reason: intent.allowPartial
                    ? "Broker fill was insufficient after priority and minimum-fill allocation."
                    : "Full-or-zero demand could not be fully satisfied.",
                correlationId: correlationId,
                createdAt: now
            )
        }
        return FillAllocationResult(
            allocations: allocations,
            shortfalls: shortfalls
        )
    }

    private func roundDown(_ value: Double) -> Double {
        floor(value / unit) * unit
    }
}

final class DeterministicPaperBroker {
    private(set) var submissionAttempts = 0

    func submit(
        order: BrokerOrder,
        configuration: PaperBrokerConfiguration,
        now: Date
    ) -> BrokerSubmissionResult {
        submissionAttempts += 1
        if configuration.rejectOrders {
            return BrokerSubmissionResult(
                order: copy(
                    order,
                    state: .rejected,
                    message: "Paper risk policy rejected the order."
                ),
                fill: nil
            )
        }
        if configuration.expireOrders || now >= order.expiresAt {
            return BrokerSubmissionResult(
                order: copy(
                    order,
                    state: .expired,
                    message: "Paper order expired before a fill."
                ),
                fill: nil
            )
        }
        let ratio = min(max(configuration.fillRatio, 0), 1)
        let fillQuantity = floor(order.quantity * ratio * 10_000) /
            10_000
        guard fillQuantity > 0 else {
            return BrokerSubmissionResult(
                order: copy(
                    order,
                    state: .accepted,
                    message: "Paper order accepted and remains unfilled."
                ),
                fill: nil
            )
        }
        let direction = order.side == .buy ? 1.0 : -1.0
        let price = order.referencePrice * (
            1 + direction *
                configuration.slippageBasisPoints / 10_000
        )
        let slippage = abs(price - order.referencePrice) * fillQuantity
        let fee = max(
            configuration.minimumFee,
            configuration.feePerUnit * fillQuantity
        )
        let state: BrokerOrderState =
            fillQuantity >= order.quantity
                ? .fullyFilled
                : .partiallyFilled
        let completed = copy(
            order,
            state: state,
            message: state == .fullyFilled
                ? "Paper order filled in full."
                : "Paper order received a deterministic partial fill."
        )
        return BrokerSubmissionResult(
            order: completed,
            fill: BrokerFill(
                schemaVersion: 1,
                fillId: InternalNettingService.stableId(
                    "fill",
                    "\(order.orderId)|\(fillQuantity)|\(price)"
                ),
                orderId: order.orderId,
                correlationId: order.correlationId,
                symbol: order.symbol,
                side: order.side,
                quantity: fillQuantity,
                price: price,
                slippageEstimate: slippage,
                feeEstimate: fee,
                filledAt: now
            )
        )
    }

    private func copy(
        _ order: BrokerOrder,
        state: BrokerOrderState,
        message: String
    ) -> BrokerOrder {
        BrokerOrder(
            schemaVersion: order.schemaVersion,
            orderId: order.orderId,
            correlationId: order.correlationId,
            symbol: order.symbol,
            side: order.side,
            quantity: order.quantity,
            referencePrice: order.referencePrice,
            mode: order.mode,
            state: state,
            createdAt: order.createdAt,
            expiresAt: order.expiresAt,
            submissionAttempts: 1,
            statusMessage: message
        )
    }
}

final class LongbridgeLiveCommandFactory {
    func build(
        capability: LongbridgeExecutionCapability,
        order: BrokerOrder
    ) throws -> [String] {
        guard capability.syntheticFixture,
              capability.supportsMachineReadableOutput,
              capability.supportsOrderSubmission else {
            throw ExecutionServiceError.unsupportedLiveCapability
        }
        let values = [
            "symbol": order.symbol,
            "side": order.side.rawValue.lowercased(),
            "quantity": String(format: "%.4f", order.quantity),
            "correlation_id": order.correlationId
        ]
        return try capability.argumentTemplate.map { argument in
            var output = argument
            for (key, value) in values {
                output = output.replacingOccurrences(
                    of: "{\(key)}",
                    with: value
                )
            }
            guard !output.contains("{"),
                  !output.contains("}"),
                  output.count <= 256,
                  output.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  }) else {
                throw ExecutionServiceError.unsafeLiveArgument
            }
            return output
        }
    }
}

enum ExecutionServiceError: Error {
    case unsupportedLiveCapability
    case unsafeLiveArgument
}

final class LongbridgeLiveBrokerAdapter {
    private let commandFactory: LongbridgeLiveCommandFactory
    private(set) var submissionAttempts = 0

    init(commandFactory: LongbridgeLiveCommandFactory) {
        self.commandFactory = commandFactory
    }

    func submit(
        order: BrokerOrder,
        configuration: LiveAdapterConfiguration
    ) -> LiveSubmissionResult {
        guard configuration.enabled else {
            return disabled(
                order,
                "Explicit Live adapter configuration is disabled."
            )
        }
        guard !configuration.fixtureMode else {
            return disabled(
                order,
                "Fixture mode can never submit a Live order."
            )
        }
        guard configuration.executableURL != nil else {
            return disabled(
                order,
                "A locally installed CLI executable is required."
            )
        }
        let arguments: [String]
        do {
            arguments = try commandFactory.build(
                capability: configuration.capability,
                order: order
            )
        } catch {
            return LiveSubmissionResult(
                state: .rejected,
                order: copy(
                    order,
                    state: .rejected,
                    message: "The isolated synthetic Live command contract is unavailable."
                ),
                arguments: [],
                retryPermitted: false,
                message: "Live command construction failed safely."
            )
        }
        return LiveSubmissionResult(
            state: .rejected,
            order: copy(
                order,
                state: .rejected,
                message: "Live submission is unavailable until v1.1.3 verifies the Longbridge Terminal command mapping."
            ),
            arguments: arguments,
            retryPermitted: false,
            message: "The Live adapter is intentionally rejecting and did not start a process."
        )
    }

    private func disabled(
        _ order: BrokerOrder,
        _ message: String
    ) -> LiveSubmissionResult {
        LiveSubmissionResult(
            state: .disabled,
            order: copy(order, state: .rejected, message: message),
            arguments: [],
            retryPermitted: false,
            message: message
        )
    }

    private func copy(
        _ order: BrokerOrder,
        state: BrokerOrderState,
        message: String
    ) -> BrokerOrder {
        BrokerOrder(
            schemaVersion: order.schemaVersion,
            orderId: order.orderId,
            correlationId: order.correlationId,
            symbol: order.symbol,
            side: order.side,
            quantity: order.quantity,
            referencePrice: order.referencePrice,
            mode: order.mode,
            state: state,
            createdAt: order.createdAt,
            expiresAt: order.expiresAt,
            submissionAttempts: state == .rejected ? 0 : 1,
            statusMessage: message
        )
    }
}

final class VirtualLedgerService {
    func apply(
        existing: [VirtualLedgerPosition],
        intents: [TradeIntent],
        transfers: [InternalTransfer],
        allocations: [VirtualAllocation],
        markPrice: Double,
        totalRiskBudget: Double,
        now: Date
    ) -> [VirtualLedgerPosition] {
        let startingQuantities = Dictionary(
            uniqueKeysWithValues: existing.map {
                ($0.id, $0.virtualQuantity)
            }
        )
        var positions = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )
        for transfer in transfers {
            applyTrade(
                &positions,
                strategyId: transfer.buyerStrategyId,
                symbol: transfer.symbol,
                signedQuantity: transfer.quantity,
                price: transfer.referencePrice,
                fee: 0,
                intentId: transfer.buyerIntentId,
                allocationId: nil,
                transferId: transfer.transferId,
                now: now
            )
            applyTrade(
                &positions,
                strategyId: transfer.sellerStrategyId,
                symbol: transfer.symbol,
                signedQuantity: -transfer.quantity,
                price: transfer.referencePrice,
                fee: 0,
                intentId: transfer.sellerIntentId,
                allocationId: nil,
                transferId: transfer.transferId,
                now: now
            )
        }
        for allocation in allocations {
            applyTrade(
                &positions,
                strategyId: allocation.strategyId,
                symbol: allocation.symbol,
                signedQuantity: allocation.side == .buy
                    ? allocation.quantity
                    : -allocation.quantity,
                price: allocation.price,
                fee: allocation.fee,
                intentId: allocation.intentId,
                allocationId: allocation.allocationId,
                transferId: nil,
                now: now
            )
        }
        let targets = Dictionary(
            grouping: intents,
            by: { "\($0.strategyId)|\($0.symbol)" }
        ).mapValues {
            $0.map(\.requestedQuantity).reduce(0, +)
        }
        return positions.values.map { position in
            let target = (startingQuantities[position.id] ?? 0) +
                (targets[position.id] ?? 0)
            let unrealized =
                (markPrice - position.costBasis) *
                position.virtualQuantity
            let usage = abs(position.virtualQuantity * markPrice)
            return VirtualLedgerPosition(
                schemaVersion: 1,
                strategyId: position.strategyId,
                symbol: position.symbol,
                targetPosition: target,
                virtualQuantity: position.virtualQuantity,
                costBasis: position.costBasis,
                realizedPnl: position.realizedPnl,
                unrealizedPnl: unrealized,
                capitalUsage: usage,
                riskContribution: totalRiskBudget > 0
                    ? usage / totalRiskBudget
                    : 0,
                intentIds: position.intentIds,
                allocationIds: position.allocationIds,
                internalTransferIds: position.internalTransferIds,
                updatedAt: now
            )
        }.sorted {
            $0.strategyId == $1.strategyId
                ? $0.symbol < $1.symbol
                : $0.strategyId < $1.strategyId
        }
    }

    private func applyTrade(
        _ positions: inout [String: VirtualLedgerPosition],
        strategyId: String,
        symbol: String,
        signedQuantity: Double,
        price: Double,
        fee: Double,
        intentId: String,
        allocationId: String?,
        transferId: String?,
        now: Date
    ) {
        let key = "\(strategyId)|\(symbol)"
        let current = positions[key] ?? VirtualLedgerPosition(
            schemaVersion: 1,
            strategyId: strategyId,
            symbol: symbol,
            targetPosition: 0,
            virtualQuantity: 0,
            costBasis: 0,
            realizedPnl: 0,
            unrealizedPnl: 0,
            capitalUsage: 0,
            riskContribution: 0,
            intentIds: [],
            allocationIds: [],
            internalTransferIds: [],
            updatedAt: now
        )
        let oldQuantity = current.virtualQuantity
        let newQuantity = oldQuantity + signedQuantity
        var costBasis = current.costBasis
        var realized = current.realizedPnl - fee
        if oldQuantity == 0 || direction(oldQuantity) ==
            direction(signedQuantity) {
            let oldCost = abs(oldQuantity) * costBasis
            let newCost = abs(signedQuantity) * price
            costBasis = abs(newQuantity) > 0
                ? (oldCost + newCost) / abs(newQuantity)
                : 0
        } else {
            let closing = min(abs(oldQuantity), abs(signedQuantity))
            realized += (price - costBasis) * closing *
                direction(oldQuantity)
            if newQuantity == 0 {
                costBasis = 0
            } else if direction(newQuantity) != direction(oldQuantity) {
                costBasis = price
            }
        }
        positions[key] = VirtualLedgerPosition(
            schemaVersion: 1,
            strategyId: strategyId,
            symbol: symbol,
            targetPosition: current.targetPosition,
            virtualQuantity: newQuantity,
            costBasis: costBasis,
            realizedPnl: realized,
            unrealizedPnl: current.unrealizedPnl,
            capitalUsage: current.capitalUsage,
            riskContribution: current.riskContribution,
            intentIds: addUnique(current.intentIds, intentId),
            allocationIds: allocationId.map {
                addUnique(current.allocationIds, $0)
            } ?? current.allocationIds,
            internalTransferIds: transferId.map {
                addUnique(current.internalTransferIds, $0)
            } ?? current.internalTransferIds,
            updatedAt: now
        )
    }

    private func direction(_ value: Double) -> Double {
        value > 0 ? 1 : value < 0 ? -1 : 0
    }

    private func addUnique(
        _ values: [String],
        _ value: String
    ) -> [String] {
        values.contains(value) ? values : values + [value]
    }
}

struct ReconciliationResult {
    let events: [ReconciliationEvent]
    let riskEvents: [CriticalRiskEvent]
    let blockedSymbols: [String]
}

final class ReconciliationService {
    func reconcile(
        positions: [VirtualLedgerPosition],
        brokerPositions: [String: Double],
        correlationId: String,
        now: Date
    ) -> ReconciliationResult {
        let symbols = Set(
            positions.map(\.symbol) + Array(brokerPositions.keys)
        ).sorted()
        var events: [ReconciliationEvent] = []
        var risks: [CriticalRiskEvent] = []
        var blocked: [String] = []
        for symbol in symbols {
            let virtual = positions.filter {
                $0.symbol == symbol
            }.map(\.virtualQuantity).reduce(0, +)
            let broker = brokerPositions[symbol] ?? 0
            let difference = virtual - broker
            let mismatch = abs(difference) > 0.0001
            events.append(
                ReconciliationEvent(
                    schemaVersion: 1,
                    reconciliationId: InternalNettingService.stableId(
                        "reconciliation",
                        "\(correlationId)|\(symbol)|\(virtual)|\(broker)"
                    ),
                    symbol: symbol,
                    virtualQuantity: virtual,
                    brokerQuantity: broker,
                    difference: difference,
                    status: mismatch ? .mismatch : .reconciled,
                    blocksNewRisk: mismatch,
                    diagnostic: mismatch
                        ? "Inspect preserved intents, transfers, broker orders, fills, and virtual allocations. No ledger mutation is permitted by this diagnostic."
                        : "Virtual ownership matches the broker net position.",
                    correlationId: correlationId,
                    createdAt: now
                )
            )
            if mismatch {
                blocked.append(symbol)
                risks.append(
                    CriticalRiskEvent(
                        schemaVersion: 1,
                        riskEventId: InternalNettingService.stableId(
                            "risk",
                            "\(correlationId)|\(symbol)|\(difference)"
                        ),
                        symbol: symbol,
                        severity: "Critical",
                        message: "Virtual positions do not reconcile with the broker net position. New risk is blocked.",
                        persistent: true,
                        correlationId: correlationId,
                        createdAt: now
                    )
                )
            }
        }
        return ReconciliationResult(
            events: events,
            riskEvents: risks,
            blockedSymbols: blocked
        )
    }
}

final class ExecutionGateway {
    private let store: ExecutionStore
    private let auditStore: AuditEventStore
    private let netting: InternalNettingService
    private let allocator: PartialFillAllocator
    private let paperBroker: DeterministicPaperBroker
    private let liveBroker: LongbridgeLiveBrokerAdapter
    private let ledger: VirtualLedgerService
    private let reconciliation: ReconciliationService

    init(
        store: ExecutionStore,
        auditStore: AuditEventStore,
        netting: InternalNettingService,
        allocator: PartialFillAllocator,
        paperBroker: DeterministicPaperBroker,
        liveBroker: LongbridgeLiveBrokerAdapter,
        ledger: VirtualLedgerService,
        reconciliation: ReconciliationService
    ) {
        self.store = store
        self.auditStore = auditStore
        self.netting = netting
        self.allocator = allocator
        self.paperBroker = paperBroker
        self.liveBroker = liveBroker
        self.ledger = ledger
        self.reconciliation = reconciliation
    }

    func process(
        intents: [TradeIntent],
        contexts: [String: ExecutionGatewayContext],
        referencePrice: Double,
        referencePriceSource: String,
        paperConfiguration: PaperBrokerConfiguration,
        liveConfiguration: LiveAdapterConfiguration,
        brokerPositions: [String: Double]
    ) throws -> GatewayBatchResult {
        let state = try store.loadExecutionState()
        var decisions: [RiskDecision] = []
        var accepted: [TradeIntent] = []
        for intent in intents.sorted(by: priorityOrder) {
            let correlation = InternalNettingService.stableId(
                "correlation",
                "\(intent.cycleId)|\(intent.symbol)|\(intent.settlementCycle)"
            )
            let reason = validate(
                intent,
                context: contexts[intent.strategyId],
                state: state,
                referencePrice: referencePrice
            )
            let outcome: RiskDecisionOutcome =
                reason == nil ? .accepted : .rejected
            let decision = RiskDecision(
                schemaVersion: 1,
                decisionId: InternalNettingService.stableId(
                    "decision",
                    "\(intent.intentId)|\(outcome.rawValue)|\(reason ?? "")"
                ),
                intentId: intent.intentId,
                strategyId: intent.strategyId,
                symbol: intent.symbol,
                outcome: outcome,
                reason: reason ??
                    "All ordered gateway safety checks passed.",
                correlationId: correlation,
                createdAt: contexts[intent.strategyId]?.now ??
                    intent.createdAt
            )
            decisions.append(decision)
            audit(
                category: .riskDecision,
                action: "ExecutionRiskDecision",
                result: outcome == .accepted ? .accepted : .rejected,
                correlationId: correlation,
                context: [
                    "intent_id": intent.intentId,
                    "strategy_id": intent.strategyId,
                    "symbol": intent.symbol,
                    "result": outcome.rawValue,
                    "reason": decision.reason
                ]
            )
            if outcome == .accepted { accepted.append(intent) }
        }
        let now = contexts.values.map(\.now).max() ??
            intents.map(\.createdAt).max() ?? Date()
        let correlation = InternalNettingService.stableId(
            "correlation",
            accepted.map(\.intentId).sorted().joined(separator: "|")
        )
        let modeGroups = Dictionary(grouping: accepted) {
            contexts[$0.strategyId]?.mode ?? .paperOnly
        }
        let nettingResults = modeGroups.values.map {
            netting.net(
                $0,
                referencePrice: referencePrice,
                referencePriceSource: referencePriceSource,
                correlationId: correlation,
                now: now
            )
        }
        let transfers = nettingResults.flatMap(\.transfers)
        let residuals = nettingResults.flatMap(\.residualIntents)
        var orders: [BrokerOrder] = []
        var fills: [BrokerFill] = []
        var allocations: [VirtualAllocation] = []
        var shortfalls: [AllocationShortfall] = []
        let orderGroups = Dictionary(grouping: residuals) {
            let mode = contexts[$0.strategyId]?.mode.rawValue ??
                StrategyMode.paperOnly.rawValue
            return "\($0.symbol)|\($0.settlementCycle)|\($0.side.rawValue)|\(mode)"
        }
        for key in orderGroups.keys.sorted() {
            guard let group = orderGroups[key],
                  let first = group.first,
                  let context = contexts[first.strategyId] else {
                continue
            }
            let orderCorrelation = InternalNettingService.stableId(
                "correlation",
                group.map(\.intentId).sorted().joined(separator: "|")
            )
            let expiry = group.map {
                $0.createdAt.addingTimeInterval(
                    TimeInterval($0.timeToLiveSeconds)
                )
            }.min() ?? now
            var order = BrokerOrder(
                schemaVersion: 1,
                orderId: InternalNettingService.stableId(
                    "order",
                    "\(orderCorrelation)|\(first.symbol)|\(first.side.rawValue)"
                ),
                correlationId: orderCorrelation,
                symbol: first.symbol,
                side: first.side,
                quantity: group.map(\.absoluteQuantity).reduce(0, +),
                referencePrice: referencePrice,
                mode: context.mode,
                state: .accepted,
                createdAt: now,
                expiresAt: expiry,
                submissionAttempts: 0,
                statusMessage:
                    "Order constructed from residual net strategy demand."
            )
            var paperFill: BrokerFill?
            if context.mode == .paperOnly {
                let submission = paperBroker.submit(
                    order: order,
                    configuration: paperConfiguration,
                    now: now
                )
                order = submission.order
                paperFill = submission.fill
            } else {
                order = liveBroker.submit(
                    order: order,
                    configuration: liveConfiguration
                ).order
            }
            orders.append(order)
            if let fill = paperFill {
                fills.append(fill)
                let result = allocator.allocate(
                    fill: fill,
                    demands: group,
                    correlationId: order.correlationId,
                    now: now
                )
                allocations.append(contentsOf: result.allocations)
                shortfalls.append(contentsOf: result.shortfalls)
            }
        }
        let updatedLedger = ledger.apply(
            existing: state.ledgerPositions,
            intents: accepted,
            transfers: transfers,
            allocations: allocations,
            markPrice: referencePrice,
            totalRiskBudget: contexts.values
                .map(\.capitalBudget).reduce(0, +),
            now: now
        )
        var updatedBroker = brokerPositions
        for fill in fills {
            updatedBroker[fill.symbol, default: 0] +=
                fill.side == .buy ? fill.quantity : -fill.quantity
        }
        let reconciled = reconciliation.reconcile(
            positions: updatedLedger,
            brokerPositions: updatedBroker,
            correlationId: correlation,
            now: now
        )
        let blocked = Set(reconciled.blockedSymbols)
        let newState = ExecutionStateSnapshot(
            schemaVersion: 1,
            intents: state.intents + intents,
            riskDecisions: state.riskDecisions + decisions,
            internalTransfers: state.internalTransfers + transfers,
            brokerOrders: state.brokerOrders + orders,
            brokerFills: state.brokerFills + fills,
            virtualAllocations:
                state.virtualAllocations + allocations,
            allocationShortfalls:
                state.allocationShortfalls + shortfalls,
            ledgerPositions: updatedLedger,
            reconciliations:
                state.reconciliations + reconciled.events,
            riskEvents: state.riskEvents + reconciled.riskEvents,
            blockedSymbols: blocked
        )
        try store.saveExecutionState(newState)
        for item in reconciled.events {
            audit(
                category: .reconciliation,
                action: "VirtualLedgerReconciliation",
                result: item.status == .reconciled
                    ? .completed
                    : .failed,
                correlationId: item.correlationId,
                context: [
                    "symbol": item.symbol,
                    "status": item.status.rawValue,
                    "blocks_new_risk":
                        item.blocksNewRisk ? "true" : "false",
                    "difference": String(item.difference)
                ]
            )
        }
        return GatewayBatchResult(
            state: newState,
            decisions: decisions,
            transfers: transfers,
            orders: orders,
            fills: fills,
            allocations: allocations,
            shortfalls: shortfalls,
            reconciliations: reconciled.events
        )
    }

    private func validate(
        _ intent: TradeIntent,
        context: ExecutionGatewayContext?,
        state: ExecutionStateSnapshot,
        referencePrice: Double
    ) -> String? {
        guard let context else {
            return "Strategy execution context is missing."
        }
        let currentVirtualQuantity = state.ledgerPositions.first {
            $0.strategyId == intent.strategyId &&
                $0.symbol == intent.symbol
        }?.virtualQuantity ?? 0
        if state.blockedSymbols.contains(intent.symbol) &&
            abs(
                currentVirtualQuantity +
                intent.requestedQuantity
            ) > abs(currentVirtualQuantity) {
            return "New risk is blocked by an unresolved reconciliation mismatch."
        }
        let exposure = intent.absoluteQuantity * referencePrice
        if context.mode == .live {
            guard context.globalLiveLock else {
                return "Global Live Lock is OFF."
            }
            guard let authorization = context.authorization,
                  authorization.enabled,
                  authorization.strategyId == intent.strategyId,
                  authorization.parameterVersion ==
                    context.parameterVersion,
                  context.now >= authorization.validFrom,
                  context.now < authorization.expiresAt,
                  authorization.allowedMarkets.contains(
                    where: {
                        $0.caseInsensitiveCompare(context.market) ==
                            .orderedSame
                    }
                  ),
                  authorization.allowedSymbolsOrUniverse.contains(
                    where: {
                        $0.caseInsensitiveCompare(intent.symbol) ==
                            .orderedSame ||
                        $0 == "fixture-liquid-equities"
                    }
                  ) else {
                return "Live authorization is missing, expired, or incompatible."
            }
            if authorization.maximumOrderFrequency <= 0 ||
                Decimal(exposure) >
                    authorization.maximumSinglePositionExposure ||
                Decimal(exposure) >
                    authorization.maximumCapital *
                    authorization.maximumStrategyAllocation ||
                Decimal(context.dailyLoss) >
                    authorization.maximumDailyLoss ||
                Decimal(context.drawdown) >
                    authorization.maximumDrawdown ||
                (context.outsideRegularHours &&
                 !authorization.outsideRegularHoursPermission) {
                return "Live authorization risk bounds were exceeded."
            }
            guard context.cliReady else {
                return "Longbridge CLI is not Ready."
            }
            guard context.liveAdapterEnabled else {
                return "Explicit Live adapter configuration is disabled."
            }
            guard !context.fixtureMode else {
                return "Fixture mode can never submit a Live order."
            }
        }
        guard context.dataFresh else { return "Market data is stale." }
        guard context.marketAllowed else {
            return "The current market state does not allow this order."
        }
        guard context.strategyHealth == .healthy else {
            return "Strategy health is not Healthy."
        }
        if context.transitionActive {
            if context.transitionPolicy == .freeze {
                return "Live-to-Paper Freeze blocks all strategy orders."
            }
            if abs(
                currentVirtualQuantity +
                intent.requestedQuantity
            ) > abs(currentVirtualQuantity) {
                return context.transitionPolicy == .controlledExit
                    ? "Controlled exit accepts only risk-reducing policy intents."
                    : "Stop Opening Risk blocks position expansion."
            }
        }
        guard context.capitalBudget > 0 else {
            return "Strategy capital budget is unavailable."
        }
        if exposure > context.capitalBudget ||
            exposure > context.maximumPositionExposure {
            return "Capital budget or single-position limit was exceeded."
        }
        if context.now >= intent.createdAt.addingTimeInterval(
            TimeInterval(intent.timeToLiveSeconds)
        ) {
            return "Trade intent expired before gateway processing."
        }
        if state.intents.contains(where: {
            $0.intentId == intent.intentId
        }) {
            return "Duplicate intent identifier was rejected."
        }
        return nil
    }

    private func priorityOrder(
        _ left: TradeIntent,
        _ right: TradeIntent
    ) -> Bool {
        left.priority == right.priority
            ? left.intentId < right.intentId
            : left.priority > right.priority
    }

    private func audit(
        category: AuditEventCategory,
        action: String,
        result: AuditResult,
        correlationId: String,
        context: [String: String]
    ) {
        try? auditStore.appendAuditEvent(
            AuditEvent(
                id: InternalNettingService.stableId(
                    "audit",
                    "\(action)|\(correlationId)|\(context["intent_id"] ?? "")"
                ),
                occurredAt: Date(),
                category: category,
                action: action,
                result: result,
                actor: "execution-gateway",
                correlationID: correlationId,
                context: context
            )
        )
    }
}
