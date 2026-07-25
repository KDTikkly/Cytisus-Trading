using System.Security.Cryptography;
using System.Text;
using System.IO;

namespace CytisusTrading.Windows;

public sealed class LocalStudioService
{
    private static readonly string[] AllowedExtensions =
    {
        ".py", ".json", ".md", ".txt", ".yaml", ".yml"
    };

    private readonly ILocalStudioStore _store;
    private readonly IAuditEventStore _auditStore;

    public LocalStudioService(
        ILocalStudioStore store,
        IAuditEventStore auditStore)
    {
        _store = store;
        _auditStore = auditStore;
    }

    public LocalStudioState LoadOrCreateFixtureState()
    {
        var current = _store.LoadLocalStudioState();
        if (current.Projects.Count > 0)
        {
            return current;
        }

        var now = DateTimeOffset.UtcNow;
        var state = LocalStudioState.Empty with
        {
            Projects = new[]
            {
                new AlgorithmProject(
                    "project-ma-demo",
                    "Moving Average Research",
                    "Research",
                    1,
                    new[]
                    {
                        new AlgorithmProjectVersion(
                            1,
                            now,
                            "Fixture",
                            new[]
                            {
                                new AlgorithmProjectFile(
                                    "strategy.py",
                                    Sha256("def signal(prices): return prices\n"),
                                    42)
                            })
                    })
            },
            ExecutionModules = new[]
            {
                new ExecutionModuleRecord(
                    "twap-fixture",
                    "TWAP Fixture",
                    "1.0.0",
                    "PaperValidationOnly",
                    true)
            },
            Accounts = new[]
            {
                new LongbridgeAccountFixture(
                    "fixture-local-paper",
                    "Local Paper",
                    "LocalPaper",
                    "US",
                    true),
                new LongbridgeAccountFixture(
                    "fixture-longbridge-live",
                    "Longbridge Live Fixture",
                    "LongbridgeLive",
                    "US",
                    true)
            },
            AccountMappings = new[]
            {
                new StrategyAccountMapping(
                    "official-fixture-strategy",
                    "fixture-local-paper",
                    "US",
                    "SyntheticFixture")
            }
        };
        _store.SaveLocalStudioState(state);
        AppendAudit(
            AuditEventCategory.AlgorithmProject,
            "InitializeFixtureStudio",
            AuditResult.Completed,
            new Dictionary<string, string>
            {
                ["project_count"] = state.Projects.Count.ToString(),
                ["synthetic_account_count"] = state.Accounts.Count.ToString()
            });
        return state;
    }

    public AlgorithmProjectVersion ApplyAgentPatch(
        string projectRoot,
        AlgorithmProject project,
        AgentProjectPatch patch,
        int maximumTokenCost)
    {
        if (patch.ProjectId != project.ProjectId)
        {
            throw new InvalidOperationException("The patch targets another project.");
        }
        if (patch.EstimatedTokenCost < 0 ||
            patch.EstimatedTokenCost > maximumTokenCost)
        {
            throw new InvalidOperationException("The patch exceeds the Agent cost limit.");
        }

        var relative = patch.RelativePath.Replace('\\', '/');
        if (Path.IsPathFullyQualified(relative) ||
            relative.Split('/').Any(segment => segment is "" or "." or "..") ||
            !AllowedExtensions.Contains(
                Path.GetExtension(relative),
                StringComparer.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "Agent patches are limited to approved project files.");
        }

        var fullRoot = Path.GetFullPath(projectRoot);
        var fullPath = Path.GetFullPath(Path.Combine(fullRoot, relative));
        if (!fullPath.StartsWith(
                fullRoot + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("The patch escaped the project sandbox.");
        }

        var file = new AlgorithmProjectFile(
            relative,
            Sha256(patch.NewContent),
            Encoding.UTF8.GetByteCount(patch.NewContent));
        var version = new AlgorithmProjectVersion(
            project.CurrentVersion + 1,
            DateTimeOffset.UtcNow,
            "AgentPatch",
            new[] { file });
        AppendAudit(
            AuditEventCategory.AlgorithmProject,
            "ValidateAgentProjectPatch",
            AuditResult.Accepted,
            new Dictionary<string, string>
            {
                ["project_id"] = project.ProjectId,
                ["patch_id"] = patch.PatchId,
                ["candidate_version"] = version.Version.ToString()
            });
        return version;
    }

    public static IReadOnlyList<ComputeDevice> DiscoverFixtureDevices()
    {
        return new[]
        {
            new ComputeDevice(
                "cpu",
                ComputeDeviceType.Cpu,
                "Generic",
                "CPU",
                ".NET and native C ABI",
                null,
                new[] { "FP64", "FP32" },
                new[] { "ManagedCPU", "NativeCPU" },
                true,
                true,
                ComputeHealth.Ready,
                "Deterministic CPU fallback is always available."),
            new ComputeDevice(
                "nvidia-cuda",
                ComputeDeviceType.NvidiaCuda,
                "NVIDIA",
                "CUDA",
                "Not loaded",
                null,
                Array.Empty<string>(),
                new[] { "CUDA", "ONNXRuntimeCUDA" },
                false,
                false,
                ComputeHealth.Unavailable,
                "No runtime provider was validated."),
            new ComputeDevice(
                "npu",
                ComputeDeviceType.Npu,
                "Runtime",
                "NPU",
                "Not loaded",
                null,
                Array.Empty<string>(),
                new[] { "QNN", "OpenVINO", "VitisAI", "CoreML" },
                false,
                false,
                ComputeHealth.Unavailable,
                "No ONNX execution provider was validated.")
        };
    }

    public static ComputeDevice SelectDevice(
        IReadOnlyList<ComputeDevice> devices,
        ComputePolicy policy)
    {
        var preferred = devices.FirstOrDefault(item =>
            item.DeviceId == policy.PreferredDeviceId &&
            item.Health == ComputeHealth.Ready);
        if (preferred is not null)
        {
            return preferred;
        }
        if (policy.AllowCpuFallback)
        {
            return devices.First(item =>
                item.Type == ComputeDeviceType.Cpu &&
                item.Health == ComputeHealth.Ready);
        }
        throw new InvalidOperationException("The preferred compute device is unavailable.");
    }

    public static AgentOrderEvaluation EvaluateAgentOrder(
        AgentOrderAuthorization authorization,
        AgentOrderIntent intent,
        decimal priorDailyNotional,
        int priorOrderCount,
        DateTimeOffset now,
        decimal currentPositionValue = 0,
        decimal currentDailyLoss = 0)
    {
        var notional = intent.Quantity * intent.ReferencePrice;
        if (authorization.Revoked)
        {
            return new AgentOrderEvaluation(
                AgentOrderDecision.Revoked,
                "Authorization was revoked.",
                notional);
        }
        if (now >= authorization.ExpiresAt)
        {
            return new AgentOrderEvaluation(
                AgentOrderDecision.Expired,
                "Authorization expired.",
                notional);
        }
        if ((authorization.ValidFrom is not null &&
             now < authorization.ValidFrom) ||
            (intent.ExpiresAt is not null && now >= intent.ExpiresAt))
        {
            return new AgentOrderEvaluation(
                AgentOrderDecision.Expired,
                "The authorization or intent is outside its time window.",
                notional);
        }
        if (authorization.AuthorizationId != intent.AuthorizationId ||
            !authorization.AllowedStrategies.Contains(
                intent.StrategyId,
                StringComparer.Ordinal) ||
            !authorization.AllowedSymbols.Contains(
                intent.Symbol,
                StringComparer.Ordinal))
        {
            return new AgentOrderEvaluation(
                AgentOrderDecision.Rejected,
                "The strategy or symbol is outside the authorization.",
                notional);
        }
        if ((authorization.AllowedAccounts?.Count > 0 &&
             !authorization.AllowedAccounts.Contains(
                 intent.AccountId,
                 StringComparer.Ordinal)) ||
            (authorization.AllowedMarkets?.Count > 0 &&
             !authorization.AllowedMarkets.Contains(
                 intent.Market,
                 StringComparer.Ordinal)) ||
            (authorization.AllowedOrderTypes?.Count > 0 &&
             !authorization.AllowedOrderTypes.Contains(
                 intent.OrderType,
                 StringComparer.Ordinal)) ||
            intent.Confidence < authorization.MinimumConfidence ||
            (intent.OutsideRegularHours &&
             !authorization.OutsideRegularHoursPermission))
        {
            return new AgentOrderEvaluation(
                AgentOrderDecision.Rejected,
                "The account, market, order type, confidence, or trading-hours boundary failed.",
                notional);
        }
        if (notional > authorization.MaxNotionalPerOrder ||
            priorDailyNotional + notional > authorization.MaxDailyNotional ||
            priorOrderCount >= authorization.MaxOrdersPerDay ||
            currentPositionValue + notional > authorization.MaximumPosition ||
            currentDailyLoss > authorization.MaximumDailyLoss)
        {
            return new AgentOrderEvaluation(
                AgentOrderDecision.Rejected,
                "An authorization limit would be exceeded.",
                notional);
        }

        var decision = authorization.Mode switch
        {
            AgentOrderPermissionMode.SuggestOnly =>
                AgentOrderDecision.Suggested,
            AgentOrderPermissionMode.ConfirmEveryOrder =>
                AgentOrderDecision.PendingConfirmation,
            AgentOrderPermissionMode.BoundedAutonomy =>
                AgentOrderDecision.Authorized,
            _ => AgentOrderDecision.Rejected
        };
        return new AgentOrderEvaluation(
            decision,
            "The intent passed the configured authorization boundary.",
            notional);
    }

    public static ExecutionModuleProposal CreateExecutionProposal(
        string intentId,
        string symbol,
        string side,
        decimal quantity,
        decimal referencePrice)
    {
        return new ExecutionModuleProposal(
            $"proposal-{intentId}",
            "twap-fixture",
            intentId,
            symbol,
            side,
            quantity,
            referencePrice,
            true,
            "Synthetic child proposal; the Execution Gateway remains authoritative.");
    }

    private static string Sha256(string value)
    {
        return Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(value)))
            .ToLowerInvariant();
    }

    private void AppendAudit(
        AuditEventCategory category,
        string action,
        AuditResult result,
        IReadOnlyDictionary<string, string> context)
    {
        _auditStore.AppendAuditEvent(
            new AuditEvent(
                Guid.NewGuid().ToString("D"),
                DateTimeOffset.UtcNow,
                category,
                action,
                result,
                "LocalStudio",
                Guid.NewGuid().ToString("D"),
                context));
    }
}
