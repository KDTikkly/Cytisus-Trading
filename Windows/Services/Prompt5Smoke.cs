using System.IO;

namespace CytisusTrading.Windows;

public static class Prompt5Smoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            Directory.CreateDirectory(rootDirectory);
            var fixtures = new ExecutionFixtureService();
            var cycle = fixtures.LoadPaperGatewayFixture();
            var capability = fixtures.LoadExecutionCapability();
            var failure = fixtures.LoadReconciliationFailure();
            var netting = new InternalNettingService();
            var allocator = new PartialFillAllocator();
            var paperBroker = new DeterministicPaperBroker();
            var liveBroker = new LongbridgeLiveBrokerAdapter(
                new LongbridgeLiveCommandFactory());
            var ledger = new VirtualLedgerService();
            var reconciliation = new ReconciliationService();

            var netted = netting.Net(
                cycle.Intents,
                cycle.ReferencePrice,
                cycle.ReferencePriceSource,
                "smoke-netting",
                cycle.AsOf);
            Require(
                netted.Transfers.Count == 1 &&
                netted.Transfers[0].Quantity == 60m &&
                netted.ResidualIntents.Sum(item =>
                    item.AbsoluteQuantity) == 80m,
                "Internal netting did not preserve deterministic residual demand.");

            var partialFill = new BrokerFill(
                1,
                "fill-smoke-partial",
                "order-smoke-partial",
                "correlation-smoke-partial",
                cycle.Symbol,
                OrderSide.Buy,
                40m,
                cycle.ReferencePrice,
                0,
                0.25m,
                cycle.AsOf);
            var partial = allocator.Allocate(
                partialFill,
                netted.ResidualIntents,
                partialFill.CorrelationId,
                cycle.AsOf);
            Require(
                partial.Allocations.Count == 1 &&
                partial.Allocations[0].Quantity == 40m &&
                partial.Shortfalls.Any(item =>
                    item.UnfilledQuantity == 40m),
                "Partial-fill priority or full-or-zero allocation failed.");

            var store = new JsonFilePersistentStore(rootDirectory);
            store.InitializeSchema();
            store.SaveExecutionState(
                ExecutionStateSnapshot.Empty with
                {
                    LedgerPositions = cycle.StartingLedger
                        .Select(item => new VirtualLedgerPosition(
                            1,
                            item.StrategyId,
                            cycle.Symbol,
                            item.VirtualQuantity,
                            item.VirtualQuantity,
                            item.CostBasis,
                            0,
                            (cycle.ReferencePrice - item.CostBasis) *
                                item.VirtualQuantity,
                            item.VirtualQuantity *
                                cycle.ReferencePrice,
                            0,
                            Array.Empty<string>(),
                            Array.Empty<string>(),
                            Array.Empty<string>(),
                            cycle.AsOf))
                        .ToArray()
                });
            var gateway = new ExecutionGateway(
                store,
                store,
                netting,
                allocator,
                paperBroker,
                liveBroker,
                ledger,
                reconciliation);
            var contexts = cycle.Intents
                .Select(item => item.StrategyId)
                .Distinct(StringComparer.Ordinal)
                .ToDictionary(
                    strategyId => strategyId,
                    _ => new ExecutionGatewayContext(
                        StrategyMode.PaperOnly,
                        false,
                        null,
                        true,
                        true,
                        HealthState.Healthy,
                        1_000_000m,
                        1_000_000m,
                        false,
                        false,
                        true,
                        1,
                        cycle.Market,
                        cycle.AsOf),
                    StringComparer.Ordinal);
            var completed = gateway.Process(
                cycle.Intents,
                contexts,
                cycle.ReferencePrice,
                cycle.ReferencePriceSource,
                new PaperBrokerConfiguration(
                    cycle.PaperFillRatio,
                    2,
                    0.005m,
                    0.25m,
                    false,
                    false),
                new LiveAdapterConfiguration(
                    false,
                    true,
                    string.Empty,
                    TimeSpan.FromSeconds(1),
                    capability),
                new Dictionary<string, decimal>(
                    StringComparer.Ordinal)
                {
                    [cycle.Symbol] = cycle.StartingBrokerQuantity
                });
            Require(
                completed.Fills.Count == 1 &&
                completed.Fills[0].Quantity == 40m &&
                completed.State.LedgerPositions.Sum(item =>
                    item.VirtualQuantity) == 100m &&
                completed.Reconciliations.All(item =>
                    item.Status == ReconciliationStatus.Reconciled),
                "The complete strategy-intent-to-Local-Paper-fill cycle failed.");
            Require(
                liveBroker.SubmissionAttempts == 0 &&
                completed.Decisions.All(item =>
                    item.Outcome == RiskDecisionOutcome.Accepted),
                "Unavailable Longbridge CLI blocked or entered Local Paper.");

            var failureLedger = new[]
            {
                new VirtualLedgerPosition(
                    1,
                    "fixture-reconciliation",
                    failure.Symbol,
                    failure.VirtualQuantity,
                    failure.VirtualQuantity,
                    100,
                    0,
                    0,
                    0,
                    0,
                    Array.Empty<string>(),
                    Array.Empty<string>(),
                    Array.Empty<string>(),
                    failure.AsOf)
            };
            var reconciled = reconciliation.Reconcile(
                failureLedger,
                new Dictionary<string, decimal>(
                    StringComparer.Ordinal)
                {
                    [failure.Symbol] = failure.BrokerQuantity
                },
                "smoke-reconciliation",
                failure.AsOf);
            Require(
                reconciled.Events.Single().Status ==
                    failure.ExpectedStatus &&
                reconciled.Events.Single().BlocksNewRisk ==
                    failure.ExpectedBlocksNewRisk &&
                reconciled.RiskEvents.Single().Persistent,
                "Virtual-ledger reconciliation did not create a persistent risk block.");

            var syntheticOrder = completed.Orders.Single();
            var rejected = liveBroker.Submit(
                syntheticOrder with { Mode = StrategyMode.Live },
                new LiveAdapterConfiguration(
                    true,
                    false,
                    "synthetic-longbridge-terminal",
                    TimeSpan.FromSeconds(1),
                    capability));
            var prohibited = new[]
            {
                "status",
                "market",
                "bars",
                "snapshot",
                "account",
                "positions",
                "--output",
                "--json"
            };
            Require(
                rejected.State == LiveSubmissionState.Rejected &&
                liveBroker.SubmissionAttempts == 0 &&
                !rejected.RetryPermitted &&
                rejected.Arguments.All(argument =>
                    !prohibited.Contains(
                        argument,
                        StringComparer.OrdinalIgnoreCase)),
                "The Live adapter did not remain a process-free rejecting boundary.");

            Console.WriteLine("Prompt 5 smoke checks passed.");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                $"Prompt 5 smoke checks failed: {exception.Message}");
            return 1;
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }
}
