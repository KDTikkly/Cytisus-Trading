using System.IO;
using System.Reflection;

namespace CytisusTrading.Windows;

public static class V112Smoke
{
    public static int Run(string rootDirectory)
    {
        try
        {
            var store = new JsonFilePersistentStore(rootDirectory);
            store.InitializeSchema();
            Require(store.GetSchemaVersion().Version == 7, "Schema migration failed.");

            var service = new LocalStudioService(store, store);
            var state = service.LoadOrCreateFixtureState();
            Require(state.Projects.Count == 1, "Fixture project is missing.");
            Require(
                service.LoadOrCreateFixtureState().Projects.Count == 1,
                "Studio state did not persist idempotently.");

            var devices = LocalStudioService.DiscoverFixtureDevices();
            var selected = LocalStudioService.SelectDevice(
                devices,
                new ComputePolicy("nvidia-cuda", true, 1, 2, 268_435_456));
            Require(selected.Type == ComputeDeviceType.Cpu, "CPU fallback failed.");

            var project = state.Projects[0];
            var version = service.ApplyAgentPatch(
                Path.Combine(rootDirectory, "projects", project.ProjectId),
                project,
                new AgentProjectPatch(
                    "patch-1",
                    project.ProjectId,
                    "strategy.py",
                    "def signal(prices): return prices[-1]\n",
                    "Keep the fixture deterministic.",
                    20),
                100);
            Require(version.Version == 2, "Agent patch versioning failed.");
            Require(
                store.LoadAuditEvents(10).Any(item =>
                    item.Category == AuditEventCategory.AlgorithmProject),
                "Algorithm Studio audit events were not persisted.");
            RequireThrows(
                () => service.ApplyAgentPatch(
                    Path.Combine(rootDirectory, "projects", project.ProjectId),
                    project,
                    new AgentProjectPatch(
                        "patch-shell",
                        project.ProjectId,
                        "../run.cmd",
                        "powershell -Command Get-ChildItem",
                        "This must be rejected.",
                        20),
                    100),
                "The project sandbox accepted a shell or traversal path.");

            var authorization = new AgentOrderAuthorization(
                "auth-fixture",
                AgentOrderPermissionMode.BoundedAutonomy,
                new[] { "official-fixture-strategy" },
                new[] { "AAPL.US" },
                2_000m,
                5_000m,
                3,
                DateTimeOffset.UtcNow.AddHours(1),
                false);
            var intent = new AgentOrderIntent(
                "agent-intent-1",
                authorization.AuthorizationId,
                "official-fixture-strategy",
                "AAPL.US",
                "Buy",
                5m,
                190m,
                DateTimeOffset.UtcNow);
            var evaluation = LocalStudioService.EvaluateAgentOrder(
                authorization,
                intent,
                0m,
                0,
                DateTimeOffset.UtcNow);
            Require(
                evaluation.Decision == AgentOrderDecision.Authorized,
                "Bounded Agent authorization failed.");
            Require(
                LocalStudioService.EvaluateAgentOrder(
                    authorization with
                    {
                        Mode = AgentOrderPermissionMode.SuggestOnly
                    },
                    intent,
                    0m,
                    0,
                    DateTimeOffset.UtcNow).Decision ==
                    AgentOrderDecision.Suggested,
                "SuggestOnly mode failed.");
            Require(
                LocalStudioService.EvaluateAgentOrder(
                    authorization with
                    {
                        Mode = AgentOrderPermissionMode.ConfirmEveryOrder
                    },
                    intent,
                    0m,
                    0,
                    DateTimeOffset.UtcNow).Decision ==
                    AgentOrderDecision.PendingConfirmation,
                "ConfirmEveryOrder mode failed.");
            Require(
                LocalStudioService.EvaluateAgentOrder(
                    authorization with { Revoked = true },
                    intent,
                    0m,
                    0,
                    DateTimeOffset.UtcNow).Decision ==
                    AgentOrderDecision.Revoked,
                "Authorization revocation failed.");
            Require(
                LocalStudioService.EvaluateAgentOrder(
                    authorization,
                    intent with { Quantity = 50m },
                    0m,
                    0,
                    DateTimeOffset.UtcNow).Decision ==
                    AgentOrderDecision.Rejected,
                "The per-order notional limit failed.");

            var proposal = LocalStudioService.CreateExecutionProposal(
                intent.IntentId,
                intent.Symbol,
                intent.Side,
                intent.Quantity,
                intent.ReferencePrice);
            Require(
                proposal.RequiresExecutionGateway,
                "Execution proposal bypassed the gateway.");
            Require(
                !new[]
                {
                    "status",
                    "market bars",
                    "market snapshot",
                    "account positions",
                    "--output json",
                    "--json"
                }.Any(command =>
                    proposal.Reason.Contains(command, StringComparison.Ordinal)),
                "A provisional CLI command became an execution dependency.");
            var accountFields = typeof(LongbridgeAccountFixture)
                .GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Select(property => property.Name)
                .ToArray();
            Require(
                !accountFields.Any(name =>
                    name.Contains("Token", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("Secret", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("Credential", StringComparison.OrdinalIgnoreCase)),
                "The synthetic account contract exposed credential material.");
            var manualOrderActions = typeof(MainWindow)
                .GetMethods(
                    BindingFlags.Public |
                    BindingFlags.NonPublic |
                    BindingFlags.Instance)
                .Select(method => method.Name)
                .Where(name =>
                    name.Contains("ManualOrder", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("BuyOrder", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("SellOrder", StringComparison.OrdinalIgnoreCase))
                .ToArray();
            Require(
                manualOrderActions.Length == 0,
                "A manual order action exists in the native window.");

            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
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

    private static void RequireThrows(Action action, string message)
    {
        try
        {
            action();
        }
        catch (InvalidOperationException)
        {
            return;
        }
        throw new InvalidOperationException(message);
    }
}
