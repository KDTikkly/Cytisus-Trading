namespace CytisusTrading.Windows;

public interface IStrategyModeService
{
    ModeSelectionResult SelectMode(
        StrategyMode requestedMode,
        bool globalLiveLock,
        StrategyManifest manifest,
        int parameterVersion,
        LiveAuthorization? authorization,
        string market,
        DateTimeOffset now);
}

public sealed class StrategyModeService : IStrategyModeService
{
    public ModeSelectionResult SelectMode(
        StrategyMode requestedMode,
        bool globalLiveLock,
        StrategyManifest manifest,
        int parameterVersion,
        LiveAuthorization? authorization,
        string market,
        DateTimeOffset now)
    {
        if (requestedMode == StrategyMode.PaperOnly)
        {
            return new ModeSelectionResult(
                true,
                StrategyMode.PaperOnly,
                "Local Paper selected. It does not require or invoke Longbridge CLI.");
        }
        if (!globalLiveLock)
        {
            return Rejected("Global Live Lock is OFF.");
        }
        if (!manifest.SupportedModes.Contains(StrategyMode.Live))
        {
            return Rejected("The strategy does not support Live mode.");
        }
        if (authorization is null || !authorization.Enabled)
        {
            return Rejected("A valid Live authorization is required.");
        }
        if (!string.Equals(
                authorization.StrategyId,
                manifest.StrategyId,
                StringComparison.Ordinal) ||
            authorization.ParameterVersion != parameterVersion)
        {
            return Rejected(
                "The Live authorization is incompatible with this strategy or parameter version.");
        }
        if (now < authorization.ValidFrom || now >= authorization.ExpiresAt)
        {
            return Rejected("The Live authorization is not currently valid.");
        }
        if (!authorization.AllowedMarkets.Contains(
                market,
                StringComparer.OrdinalIgnoreCase) ||
            authorization.MaximumOrderFrequency <= 0 ||
            authorization.MaximumCapital <= 0)
        {
            return Rejected(
                "The Live authorization does not permit the current market or risk bounds.");
        }

        return new ModeSelectionResult(
            true,
            StrategyMode.Live,
            "Live mode is selected, but the Longbridge adapter remains intentionally rejecting until v1.1.3 command verification.");
    }

    private static ModeSelectionResult Rejected(string message)
    {
        return new ModeSelectionResult(false, StrategyMode.PaperOnly, message);
    }
}

public interface ILiveBrokerAdapter
{
    int SubmissionAttempts { get; }
    string Submit(StrategyIntentRecord intent);
}

public sealed class RejectingLiveBrokerAdapter : ILiveBrokerAdapter
{
    public int SubmissionAttempts { get; private set; }

    public string Submit(StrategyIntentRecord intent)
    {
        SubmissionAttempts += 1;
        return "Rejected: Live broker submission remains unavailable. v1.1.3 validates authentication and Paper readiness only.";
    }
}

public sealed class StrategyIntentRouter
{
    public string Route(
        StrategyMode mode,
        StrategyIntentRecord intent,
        ILiveBrokerAdapter liveAdapter)
    {
        if (mode == StrategyMode.PaperOnly)
        {
            return "PaperLifecycleRecorded";
        }
        return liveAdapter.Submit(intent);
    }
}
