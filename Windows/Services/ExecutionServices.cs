using System.Globalization;
namespace CytisusTrading.Windows;

public sealed record NettingResult(
    IReadOnlyList<InternalTransfer> Transfers,
    IReadOnlyList<TradeIntent> ResidualIntents);

public sealed record FillAllocationResult(
    IReadOnlyList<VirtualAllocation> Allocations,
    IReadOnlyList<AllocationShortfall> Shortfalls);

public interface IInternalNettingService
{
    NettingResult Net(
        IReadOnlyList<TradeIntent> intents,
        decimal referencePrice,
        string referencePriceSource,
        string correlationId,
        DateTimeOffset now);
}

public sealed class InternalNettingService : IInternalNettingService
{
    public NettingResult Net(
        IReadOnlyList<TradeIntent> intents,
        decimal referencePrice,
        string referencePriceSource,
        string correlationId,
        DateTimeOffset now)
    {
        var transfers = new List<InternalTransfer>();
        var residuals = new List<TradeIntent>();
        foreach (var group in intents
                     .GroupBy(intent => new
                     {
                         intent.Symbol,
                         intent.SettlementCycle
                     })
                     .OrderBy(group => group.Key.Symbol, StringComparer.Ordinal)
                     .ThenBy(group => group.Key.SettlementCycle, StringComparer.Ordinal))
        {
            var buys = group
                .Where(intent => intent.RequestedQuantity > 0)
                .OrderByDescending(intent => intent.Priority)
                .ThenBy(intent => intent.IntentId, StringComparer.Ordinal)
                .ToArray();
            var sells = group
                .Where(intent => intent.RequestedQuantity < 0)
                .OrderByDescending(intent => intent.Priority)
                .ThenBy(intent => intent.IntentId, StringComparer.Ordinal)
                .ToArray();
            var remaining = group.ToDictionary(
                intent => intent.IntentId,
                intent => intent.AbsoluteQuantity,
                StringComparer.Ordinal);
            var buyIndex = 0;
            var sellIndex = 0;
            while (buyIndex < buys.Length && sellIndex < sells.Length)
            {
                var buy = buys[buyIndex];
                var sell = sells[sellIndex];
                var quantity = Math.Min(
                    remaining[buy.IntentId],
                    remaining[sell.IntentId]);
                if (quantity > 0)
                {
                    transfers.Add(new InternalTransfer(
                        1,
                        StableId(
                            "transfer",
                            $"{buy.IntentId}|{sell.IntentId}|{quantity}"),
                        group.Key.Symbol,
                        group.Key.SettlementCycle,
                        buy.StrategyId,
                        sell.StrategyId,
                        quantity,
                        referencePrice,
                        referencePriceSource,
                        buy.IntentId,
                        sell.IntentId,
                        correlationId,
                        now));
                    remaining[buy.IntentId] -= quantity;
                    remaining[sell.IntentId] -= quantity;
                }
                if (remaining[buy.IntentId] <= 0.00000001m)
                {
                    buyIndex += 1;
                }
                if (remaining[sell.IntentId] <= 0.00000001m)
                {
                    sellIndex += 1;
                }
            }
            residuals.AddRange(group
                .OrderByDescending(intent => intent.Priority)
                .ThenBy(intent => intent.IntentId, StringComparer.Ordinal)
                .Where(intent => remaining[intent.IntentId] > 0.00000001m)
                .Select(intent => intent with
                {
                    RequestedQuantity =
                        intent.Side == OrderSide.Buy
                            ? remaining[intent.IntentId]
                            : -remaining[intent.IntentId]
                }));
        }
        return new NettingResult(transfers, residuals);
    }

    internal static string StableId(string prefix, string value)
    {
        const ulong offset = 14695981039346656037;
        const ulong prime = 1099511628211;
        var hash = offset;
        foreach (var item in System.Text.Encoding.UTF8.GetBytes(value))
        {
            hash ^= item;
            hash *= prime;
        }
        return $"{prefix}-{hash:x16}";
    }
}

public interface IPartialFillAllocator
{
    FillAllocationResult Allocate(
        BrokerFill fill,
        IReadOnlyList<TradeIntent> demands,
        string correlationId,
        DateTimeOffset now);
}

public sealed class PartialFillAllocator : IPartialFillAllocator
{
    private const decimal Unit = 0.0001m;

    public FillAllocationResult Allocate(
        BrokerFill fill,
        IReadOnlyList<TradeIntent> demands,
        string correlationId,
        DateTimeOffset now)
    {
        var matching = demands
            .Where(intent =>
                intent.Symbol == fill.Symbol &&
                intent.Side == fill.Side)
            .OrderByDescending(intent => intent.Priority)
            .ThenBy(intent => intent.IntentId, StringComparer.Ordinal)
            .ToArray();
        var allocated = matching.ToDictionary(
            intent => intent.IntentId,
            _ => 0m,
            StringComparer.Ordinal);
        var available = fill.Quantity;
        foreach (var group in matching.GroupBy(intent => intent.Priority)
                     .OrderByDescending(group => group.Key))
        {
            if (available <= 0)
            {
                break;
            }
            var values = group.OrderBy(
                intent => intent.IntentId,
                StringComparer.Ordinal).ToArray();
            var totalDemand = values.Sum(intent => intent.AbsoluteQuantity);
            if (available >= totalDemand)
            {
                foreach (var intent in values)
                {
                    allocated[intent.IntentId] = intent.AbsoluteQuantity;
                }
                available -= totalDemand;
                continue;
            }

            var partial = values.Where(intent => intent.AllowPartial).ToList();
            while (partial.Count > 0 && available > 0)
            {
                var demand = partial.Sum(intent => intent.AbsoluteQuantity);
                var proposed = partial.ToDictionary(
                    intent => intent.IntentId,
                    intent => RoundDown(
                        available * intent.AbsoluteQuantity / demand),
                    StringComparer.Ordinal);
                var unusable = partial.Where(intent =>
                        proposed[intent.IntentId] <
                        intent.MinimumEffectiveFill)
                    .ToArray();
                if (unusable.Length == 0)
                {
                    foreach (var intent in partial)
                    {
                        allocated[intent.IntentId] =
                            Math.Min(
                                intent.AbsoluteQuantity,
                                proposed[intent.IntentId]);
                    }
                    var used = partial.Sum(intent =>
                        allocated[intent.IntentId]);
                    var remainder = available - used;
                    foreach (var intent in partial
                                 .OrderBy(item => item.IntentId, StringComparer.Ordinal))
                    {
                        if (remainder < Unit)
                        {
                            break;
                        }
                        var capacity =
                            intent.AbsoluteQuantity -
                            allocated[intent.IntentId];
                        var addition = Math.Min(capacity, remainder);
                        allocated[intent.IntentId] += addition;
                        remainder -= addition;
                    }
                    available = remainder;
                    break;
                }
                partial.RemoveAll(intent => unusable.Contains(intent));
            }
            break;
        }

        var allocations = matching
            .Where(intent => allocated[intent.IntentId] > 0)
            .Select(intent =>
            {
                var quantity = allocated[intent.IntentId];
                var fee = fill.FeeEstimate *
                    quantity / Math.Max(fill.Quantity, Unit);
                return new VirtualAllocation(
                    1,
                    InternalNettingService.StableId(
                        "allocation",
                        $"{fill.FillId}|{intent.IntentId}|{quantity}"),
                    fill.FillId,
                    intent.IntentId,
                    intent.StrategyId,
                    intent.Symbol,
                    intent.Side,
                    quantity,
                    fill.Price,
                    fee,
                    correlationId,
                    now);
            })
            .ToArray();
        var shortfalls = matching
            .Where(intent =>
                intent.AbsoluteQuantity - allocated[intent.IntentId] >
                0.00000001m)
            .Select(intent =>
            {
                var amount = allocated[intent.IntentId];
                return new AllocationShortfall(
                    1,
                    InternalNettingService.StableId(
                        "shortfall",
                        $"{fill.FillId}|{intent.IntentId}|{amount}"),
                    intent.IntentId,
                    intent.StrategyId,
                    intent.Symbol,
                    intent.AbsoluteQuantity,
                    amount,
                    intent.AbsoluteQuantity - amount,
                    intent.AllowPartial
                        ? "Broker fill was insufficient after priority and minimum-fill allocation."
                        : "Full-or-zero demand could not be fully satisfied.",
                    correlationId,
                    now);
            })
            .ToArray();
        return new FillAllocationResult(allocations, shortfalls);
    }

    private static decimal RoundDown(decimal value)
    {
        return decimal.Floor(value / Unit) * Unit;
    }
}

public interface IPaperBroker
{
    int SubmissionAttempts { get; }
    BrokerSubmissionResult Submit(
        BrokerOrder order,
        PaperBrokerConfiguration configuration,
        DateTimeOffset now);
}

public sealed class DeterministicPaperBroker : IPaperBroker
{
    public int SubmissionAttempts { get; private set; }

    public BrokerSubmissionResult Submit(
        BrokerOrder order,
        PaperBrokerConfiguration configuration,
        DateTimeOffset now)
    {
        SubmissionAttempts += 1;
        if (configuration.RejectOrders)
        {
            return new BrokerSubmissionResult(
                order with
                {
                    State = BrokerOrderState.Rejected,
                    SubmissionAttempts = 1,
                    StatusMessage = "Paper risk policy rejected the order."
                },
                null);
        }
        if (configuration.ExpireOrders || now >= order.ExpiresAt)
        {
            return new BrokerSubmissionResult(
                order with
                {
                    State = BrokerOrderState.Expired,
                    SubmissionAttempts = 1,
                    StatusMessage = "Paper order expired before a fill."
                },
                null);
        }
        var ratio = Math.Clamp(configuration.FillRatio, 0, 1);
        var fillQuantity = decimal.Round(
            order.Quantity * ratio,
            4,
            MidpointRounding.ToZero);
        if (fillQuantity <= 0)
        {
            return new BrokerSubmissionResult(
                order with
                {
                    State = BrokerOrderState.Accepted,
                    SubmissionAttempts = 1,
                    StatusMessage = "Paper order accepted and remains unfilled."
                },
                null);
        }
        var direction = order.Side == OrderSide.Buy ? 1m : -1m;
        var price = order.ReferencePrice *
            (1 + direction *
                configuration.SlippageBasisPoints / 10_000m);
        var slippage = Math.Abs(price - order.ReferencePrice) *
            fillQuantity;
        var fee = Math.Max(
            configuration.MinimumFee,
            configuration.FeePerUnit * fillQuantity);
        var state = fillQuantity >= order.Quantity
            ? BrokerOrderState.FullyFilled
            : BrokerOrderState.PartiallyFilled;
        var completedOrder = order with
        {
            State = state,
            SubmissionAttempts = 1,
            StatusMessage = state == BrokerOrderState.FullyFilled
                ? "Paper order filled in full."
                : "Paper order received a deterministic partial fill."
        };
        return new BrokerSubmissionResult(
            completedOrder,
            new BrokerFill(
                1,
                InternalNettingService.StableId(
                    "fill",
                    $"{order.OrderId}|{fillQuantity}|{price}"),
                order.OrderId,
                order.CorrelationId,
                order.Symbol,
                order.Side,
                fillQuantity,
                price,
                slippage,
                fee,
                now));
    }
}

public sealed class LongbridgeLiveCommandFactory
{
    public IReadOnlyList<string> Build(
        LongbridgeExecutionCapability capability,
        BrokerOrder order)
    {
        if (!capability.SyntheticFixture ||
            !capability.SupportsMachineReadableOutput ||
            !capability.SupportsOrderSubmission)
        {
            throw new NotSupportedException(
                "The isolated synthetic Live command contract is unavailable.");
        }
        var values = new Dictionary<string, string>(
            StringComparer.Ordinal)
        {
            ["symbol"] = order.Symbol,
            ["side"] = order.Side.ToString().ToLowerInvariant(),
            ["quantity"] = order.Quantity.ToString(
                "0.####",
                CultureInfo.InvariantCulture),
            ["correlation_id"] = order.CorrelationId
        };
        return capability.ArgumentTemplate.Select(argument =>
        {
            var output = argument;
            foreach (var pair in values)
            {
                output = output.Replace(
                    $"{{{pair.Key}}}",
                    pair.Value,
                    StringComparison.Ordinal);
            }
            if (output.Contains('{') ||
                output.Contains('}') ||
                output.Any(char.IsControl) ||
                output.Length > 256)
            {
                throw new InvalidOperationException(
                    "The Live command template contains an unsafe or unresolved value.");
            }
            return output;
        }).ToArray();
    }
}

public interface ILongbridgeLiveBrokerAdapter
{
    int SubmissionAttempts { get; }
    LiveSubmissionResult Submit(
        BrokerOrder order,
        LiveAdapterConfiguration configuration);
}

public sealed class LongbridgeLiveBrokerAdapter :
    ILongbridgeLiveBrokerAdapter
{
    private readonly LongbridgeLiveCommandFactory _commandFactory;

    public LongbridgeLiveBrokerAdapter(
        LongbridgeLiveCommandFactory commandFactory)
    {
        _commandFactory = commandFactory;
    }

    public int SubmissionAttempts { get; private set; }

    public LiveSubmissionResult Submit(
        BrokerOrder order,
        LiveAdapterConfiguration configuration)
    {
        if (!configuration.Enabled)
        {
            return Disabled(order, "Explicit Live adapter configuration is disabled.");
        }
        if (configuration.FixtureMode)
        {
            return Disabled(order, "Fixture mode can never submit a Live order.");
        }
        if (string.IsNullOrWhiteSpace(configuration.ExecutablePath))
        {
            return Disabled(order, "A locally installed CLI executable is required.");
        }
        IReadOnlyList<string> arguments;
        try
        {
            arguments = _commandFactory.Build(
                configuration.Capability,
                order);
        }
        catch (Exception exception) when (
            exception is NotSupportedException or InvalidOperationException)
        {
            return new LiveSubmissionResult(
                LiveSubmissionState.Rejected,
                order with
                {
                    State = BrokerOrderState.Rejected,
                    StatusMessage = exception.Message
                },
                Array.Empty<string>(),
                false,
                exception.Message);
        }

        return new LiveSubmissionResult(
            LiveSubmissionState.Rejected,
            order with
            {
                State = BrokerOrderState.Rejected,
                SubmissionAttempts = 0,
                StatusMessage =
                    "Live submission is unavailable until v1.1.3 verifies the Longbridge Terminal command mapping."
            },
            arguments,
            false,
            "The Live adapter is intentionally rejecting and did not start a process.");
    }

    private static LiveSubmissionResult Disabled(
        BrokerOrder order,
        string message)
    {
        return new LiveSubmissionResult(
            LiveSubmissionState.Disabled,
            order with
            {
                State = BrokerOrderState.Rejected,
                StatusMessage = message
            },
            Array.Empty<string>(),
            false,
            message);
    }

}

public sealed class VirtualLedgerService
{
    public IReadOnlyList<VirtualLedgerPosition> Apply(
        IReadOnlyList<VirtualLedgerPosition> existing,
        IReadOnlyList<TradeIntent> intents,
        IReadOnlyList<InternalTransfer> transfers,
        IReadOnlyList<VirtualAllocation> allocations,
        decimal markPrice,
        decimal totalRiskBudget,
        DateTimeOffset now)
    {
        var startingQuantities = existing.ToDictionary(
            position => position.PositionKey,
            position => position.VirtualQuantity,
            StringComparer.Ordinal);
        var positions = existing.ToDictionary(
            position => position.PositionKey,
            position => position,
            StringComparer.Ordinal);
        foreach (var transfer in transfers)
        {
            ApplyTrade(
                positions,
                transfer.BuyerStrategyId,
                transfer.Symbol,
                transfer.Quantity,
                transfer.ReferencePrice,
                0,
                transfer.BuyerIntentId,
                null,
                transfer.TransferId,
                now);
            ApplyTrade(
                positions,
                transfer.SellerStrategyId,
                transfer.Symbol,
                -transfer.Quantity,
                transfer.ReferencePrice,
                0,
                transfer.SellerIntentId,
                null,
                transfer.TransferId,
                now);
        }
        foreach (var allocation in allocations)
        {
            ApplyTrade(
                positions,
                allocation.StrategyId,
                allocation.Symbol,
                allocation.Side == OrderSide.Buy
                    ? allocation.Quantity
                    : -allocation.Quantity,
                allocation.Price,
                allocation.Fee,
                allocation.IntentId,
                allocation.AllocationId,
                null,
                now);
        }
        var targets = intents
            .GroupBy(intent => $"{intent.StrategyId}|{intent.Symbol}")
            .ToDictionary(
                group => group.Key,
                group => group.Sum(intent => intent.RequestedQuantity),
                StringComparer.Ordinal);
        return positions.Values.Select(position =>
        {
            var target =
                startingQuantities.GetValueOrDefault(
                    position.PositionKey) +
                targets.GetValueOrDefault(position.PositionKey);
            var unrealized =
                (markPrice - position.CostBasis) *
                position.VirtualQuantity;
            var usage = Math.Abs(position.VirtualQuantity * markPrice);
            return position with
            {
                TargetPosition = target,
                UnrealizedPnl = unrealized,
                CapitalUsage = usage,
                RiskContribution = totalRiskBudget > 0
                    ? usage / totalRiskBudget
                    : 0,
                UpdatedAt = now
            };
        })
        .OrderBy(position => position.StrategyId, StringComparer.Ordinal)
        .ThenBy(position => position.Symbol, StringComparer.Ordinal)
        .ToArray();
    }

    private static void ApplyTrade(
        IDictionary<string, VirtualLedgerPosition> positions,
        string strategyId,
        string symbol,
        decimal signedQuantity,
        decimal price,
        decimal fee,
        string intentId,
        string? allocationId,
        string? transferId,
        DateTimeOffset now)
    {
        var key = $"{strategyId}|{symbol}";
        positions.TryGetValue(key, out var existing);
        var current = existing ?? new VirtualLedgerPosition(
                1,
                strategyId,
                symbol,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                Array.Empty<string>(),
                Array.Empty<string>(),
                Array.Empty<string>(),
                now);
        var oldQuantity = current.VirtualQuantity;
        var newQuantity = oldQuantity + signedQuantity;
        var costBasis = current.CostBasis;
        var realized = current.RealizedPnl - fee;
        if (oldQuantity == 0 ||
            Math.Sign(oldQuantity) == Math.Sign(signedQuantity))
        {
            var oldCost = Math.Abs(oldQuantity) * costBasis;
            var newCost = Math.Abs(signedQuantity) * price;
            costBasis = Math.Abs(newQuantity) > 0
                ? (oldCost + newCost) / Math.Abs(newQuantity)
                : 0;
        }
        else
        {
            var closing = Math.Min(
                Math.Abs(oldQuantity),
                Math.Abs(signedQuantity));
            realized +=
                (price - costBasis) *
                closing *
                Math.Sign(oldQuantity);
            if (newQuantity == 0)
            {
                costBasis = 0;
            }
            else if (Math.Sign(newQuantity) != Math.Sign(oldQuantity))
            {
                costBasis = price;
            }
        }
        positions[key] = current with
        {
            VirtualQuantity = newQuantity,
            CostBasis = costBasis,
            RealizedPnl = realized,
            IntentIds = AddUnique(current.IntentIds, intentId),
            AllocationIds = allocationId is null
                ? current.AllocationIds
                : AddUnique(current.AllocationIds, allocationId),
            InternalTransferIds = transferId is null
                ? current.InternalTransferIds
                : AddUnique(current.InternalTransferIds, transferId),
            UpdatedAt = now
        };
    }

    private static IReadOnlyList<string> AddUnique(
        IReadOnlyList<string> values,
        string value)
    {
        return values.Contains(value, StringComparer.Ordinal)
            ? values
            : values.Concat(new[] { value }).ToArray();
    }
}

public sealed record ReconciliationResult(
    IReadOnlyList<ReconciliationEvent> Events,
    IReadOnlyList<CriticalRiskEvent> RiskEvents,
    IReadOnlyList<string> BlockedSymbols);

public sealed class ReconciliationService
{
    private const decimal Tolerance = 0.0001m;

    public ReconciliationResult Reconcile(
        IReadOnlyList<VirtualLedgerPosition> positions,
        IReadOnlyDictionary<string, decimal> brokerPositions,
        string correlationId,
        DateTimeOffset now)
    {
        var symbols = positions.Select(position => position.Symbol)
            .Concat(brokerPositions.Keys)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(symbol => symbol, StringComparer.Ordinal)
            .ToArray();
        var events = new List<ReconciliationEvent>();
        var risks = new List<CriticalRiskEvent>();
        var blocked = new List<string>();
        foreach (var symbol in symbols)
        {
            var virtualQuantity = positions
                .Where(position => position.Symbol == symbol)
                .Sum(position => position.VirtualQuantity);
            var brokerQuantity = brokerPositions.GetValueOrDefault(symbol);
            var difference = virtualQuantity - brokerQuantity;
            var mismatch = Math.Abs(difference) > Tolerance;
            events.Add(new ReconciliationEvent(
                1,
                InternalNettingService.StableId(
                    "reconciliation",
                    $"{correlationId}|{symbol}|{virtualQuantity}|{brokerQuantity}"),
                symbol,
                virtualQuantity,
                brokerQuantity,
                difference,
                mismatch
                    ? ReconciliationStatus.Mismatch
                    : ReconciliationStatus.Reconciled,
                mismatch,
                mismatch
                    ? "Inspect preserved intents, transfers, broker orders, fills, and virtual allocations. No ledger mutation is permitted by this diagnostic."
                    : "Virtual ownership matches the broker net position.",
                correlationId,
                now));
            if (mismatch)
            {
                blocked.Add(symbol);
                risks.Add(new CriticalRiskEvent(
                    1,
                    InternalNettingService.StableId(
                        "risk",
                        $"{correlationId}|{symbol}|{difference}"),
                    symbol,
                    "Critical",
                    "Virtual positions do not reconcile with the broker net position. New risk is blocked.",
                    true,
                    correlationId,
                    now));
            }
        }
        return new ReconciliationResult(events, risks, blocked);
    }
}

public sealed class ExecutionGateway
{
    private readonly IExecutionStore _store;
    private readonly IAuditEventStore _auditStore;
    private readonly IInternalNettingService _netting;
    private readonly IPartialFillAllocator _allocator;
    private readonly IPaperBroker _paperBroker;
    private readonly ILongbridgeLiveBrokerAdapter _liveBroker;
    private readonly VirtualLedgerService _ledger;
    private readonly ReconciliationService _reconciliation;

    public ExecutionGateway(
        IExecutionStore store,
        IAuditEventStore auditStore,
        IInternalNettingService netting,
        IPartialFillAllocator allocator,
        IPaperBroker paperBroker,
        ILongbridgeLiveBrokerAdapter liveBroker,
        VirtualLedgerService ledger,
        ReconciliationService reconciliation)
    {
        _store = store;
        _auditStore = auditStore;
        _netting = netting;
        _allocator = allocator;
        _paperBroker = paperBroker;
        _liveBroker = liveBroker;
        _ledger = ledger;
        _reconciliation = reconciliation;
    }

    public GatewayBatchResult Process(
        IReadOnlyList<TradeIntent> intents,
        IReadOnlyDictionary<string, ExecutionGatewayContext> contexts,
        decimal referencePrice,
        string referencePriceSource,
        PaperBrokerConfiguration paperConfiguration,
        LiveAdapterConfiguration liveConfiguration,
        IReadOnlyDictionary<string, decimal> brokerPositions)
    {
        var state = _store.LoadExecutionState();
        var decisions = new List<RiskDecision>();
        var accepted = new List<TradeIntent>();
        foreach (var intent in intents
                     .OrderByDescending(item => item.Priority)
                     .ThenBy(item => item.IntentId, StringComparer.Ordinal))
        {
            var correlationId = InternalNettingService.StableId(
                "correlation",
                $"{intent.CycleId}|{intent.Symbol}|{intent.SettlementCycle}");
            var reason = Validate(
                intent,
                contexts.GetValueOrDefault(intent.StrategyId),
                state,
                referencePrice);
            var outcome = reason is null
                ? RiskDecisionOutcome.Accepted
                : RiskDecisionOutcome.Rejected;
            var decision = new RiskDecision(
                1,
                InternalNettingService.StableId(
                    "decision",
                    $"{intent.IntentId}|{outcome}|{reason}"),
                intent.IntentId,
                intent.StrategyId,
                intent.Symbol,
                outcome,
                reason ?? "All ordered gateway safety checks passed.",
                correlationId,
                contexts.GetValueOrDefault(intent.StrategyId)?.Now ??
                    intent.CreatedAt);
            decisions.Add(decision);
            Audit(
                AuditEventCategory.RiskDecision,
                "ExecutionRiskDecision",
                outcome == RiskDecisionOutcome.Accepted
                    ? AuditResult.Accepted
                    : AuditResult.Rejected,
                correlationId,
                new Dictionary<string, string>
                {
                    ["intent_id"] = intent.IntentId,
                    ["strategy_id"] = intent.StrategyId,
                    ["symbol"] = intent.Symbol,
                    ["result"] = outcome.ToString(),
                    ["reason"] = decision.Reason
                });
            if (outcome == RiskDecisionOutcome.Accepted)
            {
                accepted.Add(intent);
            }
        }
        var now = contexts.Values.Select(context => context.Now)
            .DefaultIfEmpty(intents.Select(intent => intent.CreatedAt)
                .DefaultIfEmpty(DateTimeOffset.UtcNow).Max())
            .Max();
        var correlation = InternalNettingService.StableId(
            "correlation",
            string.Join(
                "|",
                accepted.Select(intent => intent.IntentId)
                    .OrderBy(value => value, StringComparer.Ordinal)));
        var nettingResults = accepted
            .GroupBy(intent => contexts[intent.StrategyId].Mode)
            .Select(group => _netting.Net(
                group.ToArray(),
                referencePrice,
                referencePriceSource,
                correlation,
                now))
            .ToArray();
        var nettedTransfers = nettingResults
            .SelectMany(result => result.Transfers)
            .ToArray();
        var residualIntents = nettingResults
            .SelectMany(result => result.ResidualIntents)
            .ToArray();
        var orders = new List<BrokerOrder>();
        var fills = new List<BrokerFill>();
        var allocations = new List<VirtualAllocation>();
        var shortfalls = new List<AllocationShortfall>();
        foreach (var transfer in nettedTransfers)
        {
            Audit(
                AuditEventCategory.InternalTransfer,
                "InternalTransferCreated",
                AuditResult.Completed,
                transfer.CorrelationId,
                new Dictionary<string, string>
                {
                    ["transfer_id"] = transfer.TransferId,
                    ["symbol"] = transfer.Symbol,
                    ["quantity"] = transfer.Quantity.ToString(
                        CultureInfo.InvariantCulture),
                    ["reference_price_source"] =
                        transfer.ReferencePriceSource
                });
        }
        foreach (var group in residualIntents.GroupBy(intent => new
                 {
                     intent.Symbol,
                     intent.SettlementCycle,
                     intent.Side,
                     Mode = contexts[intent.StrategyId].Mode
                 }))
        {
            var groupIntents = group.ToArray();
            var context = contexts[groupIntents[0].StrategyId];
            var orderCorrelation = InternalNettingService.StableId(
                "correlation",
                string.Join(
                    "|",
                    groupIntents.Select(intent => intent.IntentId)
                        .OrderBy(value => value, StringComparer.Ordinal)));
            var order = new BrokerOrder(
                1,
                InternalNettingService.StableId(
                    "order",
                    $"{orderCorrelation}|{group.Key.Symbol}|{group.Key.Side}"),
                orderCorrelation,
                group.Key.Symbol,
                group.Key.Side,
                groupIntents.Sum(intent => intent.AbsoluteQuantity),
                referencePrice,
                context.Mode,
                BrokerOrderState.Accepted,
                now,
                groupIntents.Min(intent =>
                    intent.CreatedAt.AddSeconds(
                        intent.TimeToLiveSeconds)),
                0,
                "Order constructed from residual net strategy demand.");
            BrokerSubmissionResult? paper = null;
            if (context.Mode == StrategyMode.PaperOnly)
            {
                paper = _paperBroker.Submit(
                    order,
                    paperConfiguration,
                    now);
                order = paper.Order;
            }
            else
            {
                order = _liveBroker.Submit(
                    order,
                    liveConfiguration).Order;
            }
            orders.Add(order);
            Audit(
                AuditEventCategory.BrokerOrder,
                "BrokerOrderLifecycle",
                order.State == BrokerOrderState.Rejected
                    ? AuditResult.Rejected
                    : AuditResult.Completed,
                order.CorrelationId,
                new Dictionary<string, string>
                {
                    ["order_id"] = order.OrderId,
                    ["symbol"] = order.Symbol,
                    ["side"] = order.Side.ToString(),
                    ["quantity"] = order.Quantity.ToString(
                        CultureInfo.InvariantCulture),
                    ["mode"] = order.Mode.ToString(),
                    ["state"] = order.State.ToString()
                });
            if (paper?.Fill is { } fill)
            {
                fills.Add(fill);
                var result = _allocator.Allocate(
                    fill,
                    groupIntents,
                    order.CorrelationId,
                    now);
                allocations.AddRange(result.Allocations);
                shortfalls.AddRange(result.Shortfalls);
            }
        }

        var updatedLedger = _ledger.Apply(
            state.LedgerPositions,
            accepted,
            nettedTransfers,
            allocations,
            referencePrice,
            contexts.Values.Select(context => context.CapitalBudget)
                .DefaultIfEmpty(0)
                .Sum(),
            now);
        var updatedBroker = brokerPositions.ToDictionary(
            pair => pair.Key,
            pair => pair.Value,
            StringComparer.Ordinal);
        foreach (var fill in fills)
        {
            updatedBroker[fill.Symbol] =
                updatedBroker.GetValueOrDefault(fill.Symbol) +
                (fill.Side == OrderSide.Buy
                    ? fill.Quantity
                    : -fill.Quantity);
        }
        var reconciled = _reconciliation.Reconcile(
            updatedLedger,
            updatedBroker,
            correlation,
            now);
        var blocked = reconciled.BlockedSymbols
            .Distinct(StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        var newState = new ExecutionStateSnapshot(
            1,
            state.Intents.Concat(intents).ToArray(),
            state.RiskDecisions.Concat(decisions).ToArray(),
            state.InternalTransfers.Concat(nettedTransfers).ToArray(),
            state.BrokerOrders.Concat(orders).ToArray(),
            state.BrokerFills.Concat(fills).ToArray(),
            state.VirtualAllocations.Concat(allocations).ToArray(),
            state.AllocationShortfalls.Concat(shortfalls).ToArray(),
            updatedLedger,
            state.Reconciliations.Concat(reconciled.Events).ToArray(),
            state.RiskEvents.Concat(reconciled.RiskEvents).ToArray(),
            blocked);
        _store.SaveExecutionState(newState);
        foreach (var item in reconciled.Events)
        {
            Audit(
                AuditEventCategory.Reconciliation,
                "VirtualLedgerReconciliation",
                item.Status == ReconciliationStatus.Reconciled
                    ? AuditResult.Completed
                    : AuditResult.Failed,
                item.CorrelationId,
                new Dictionary<string, string>
                {
                    ["symbol"] = item.Symbol,
                    ["status"] = item.Status.ToString(),
                    ["blocks_new_risk"] =
                        item.BlocksNewRisk ? "true" : "false",
                    ["difference"] = item.Difference.ToString(
                        CultureInfo.InvariantCulture)
                });
        }
        return new GatewayBatchResult(
            newState,
            decisions,
            nettedTransfers,
            orders,
            fills,
            allocations,
            shortfalls,
            reconciled.Events);
    }

    private static string? Validate(
        TradeIntent intent,
        ExecutionGatewayContext? context,
        ExecutionStateSnapshot state,
        decimal referencePrice)
    {
        if (context is null)
        {
            return "Strategy execution context is missing.";
        }
        var currentVirtualQuantity = state.LedgerPositions
            .FirstOrDefault(position =>
                position.StrategyId == intent.StrategyId &&
                position.Symbol == intent.Symbol)
            ?.VirtualQuantity ?? 0;
        if (state.BlockedSymbols.Contains(
                intent.Symbol,
                StringComparer.Ordinal) &&
            Math.Abs(
                currentVirtualQuantity +
                intent.RequestedQuantity) >
            Math.Abs(currentVirtualQuantity))
        {
            return "New risk is blocked by an unresolved reconciliation mismatch.";
        }
        if (context.Mode == StrategyMode.Live)
        {
            if (!context.GlobalLiveLock)
            {
                return "Global Live Lock is OFF.";
            }
            var authorization = context.Authorization;
            if (authorization is null ||
                !authorization.Enabled ||
                authorization.StrategyId != intent.StrategyId ||
                authorization.ParameterVersion !=
                    context.ParameterVersion ||
                context.Now < authorization.ValidFrom ||
                context.Now >= authorization.ExpiresAt ||
                !authorization.AllowedMarkets.Contains(
                    context.Market,
                    StringComparer.OrdinalIgnoreCase) ||
                (!authorization.AllowedSymbolsOrUniverse.Contains(
                    intent.Symbol,
                    StringComparer.OrdinalIgnoreCase) &&
                 !authorization.AllowedSymbolsOrUniverse.Contains(
                    "fixture-liquid-equities",
                    StringComparer.OrdinalIgnoreCase)))
            {
                return "Live authorization is missing, expired, or incompatible.";
            }
            if (authorization.MaximumOrderFrequency <= 0 ||
                exposureLimit(intent, referencePrice) >
                    authorization.MaximumSinglePositionExposure ||
                exposureLimit(intent, referencePrice) >
                    authorization.MaximumCapital *
                    authorization.MaximumStrategyAllocation ||
                context.DailyLoss >
                    authorization.MaximumDailyLoss ||
                context.Drawdown >
                    authorization.MaximumDrawdown ||
                (context.OutsideRegularHours &&
                 !authorization.OutsideRegularHoursPermission))
            {
                return "Live authorization risk bounds were exceeded.";
            }
            if (!context.CliReady)
            {
                return "Longbridge CLI is not Ready.";
            }
            if (!context.LiveAdapterEnabled)
            {
                return "Explicit Live adapter configuration is disabled.";
            }
            if (context.FixtureMode)
            {
                return "Fixture mode can never submit a Live order.";
            }
        }
        if (!context.DataFresh)
        {
            return "Market data is stale.";
        }
        if (!context.MarketAllowed)
        {
            return "The current market state does not allow this order.";
        }
        if (context.StrategyHealth != HealthState.Healthy)
        {
            return "Strategy health is not Healthy.";
        }
        if (context.TransitionActive)
        {
            if (context.TransitionPolicy ==
                LiveToPaperTransition.Freeze)
            {
                return "Live-to-Paper Freeze blocks all strategy orders.";
            }
            if (Math.Abs(
                    currentVirtualQuantity +
                    intent.RequestedQuantity) >
                Math.Abs(currentVirtualQuantity))
            {
                return context.TransitionPolicy ==
                    LiveToPaperTransition.ControlledExit
                    ? "Controlled exit accepts only risk-reducing policy intents."
                    : "Stop Opening Risk blocks position expansion.";
            }
        }
        if (context.CapitalBudget <= 0)
        {
            return "Strategy capital budget is unavailable.";
        }
        var exposure = intent.AbsoluteQuantity * referencePrice;
        if (exposure > context.CapitalBudget ||
            exposure > context.MaximumPositionExposure)
        {
            return "Capital budget or single-position limit was exceeded.";
        }
        if (context.Now >= intent.CreatedAt.AddSeconds(
                intent.TimeToLiveSeconds))
        {
            return "Trade intent expired before gateway processing.";
        }
        if (state.Intents.Any(existing =>
                existing.IntentId == intent.IntentId))
        {
            return "Duplicate intent identifier was rejected.";
        }
        return null;
    }

    private static decimal exposureLimit(
        TradeIntent intent,
        decimal referencePrice)
    {
        return intent.AbsoluteQuantity * referencePrice;
    }

    private void Audit(
        AuditEventCategory category,
        string action,
        AuditResult result,
        string correlationId,
        IReadOnlyDictionary<string, string> context)
    {
        _auditStore.AppendAuditEvent(new AuditEvent(
            InternalNettingService.StableId(
                "audit",
                $"{action}|{correlationId}|{context.GetValueOrDefault("intent_id")}"),
            DateTimeOffset.UtcNow,
            category,
            action,
            result,
            "execution-gateway",
            correlationId,
            context));
    }
}
