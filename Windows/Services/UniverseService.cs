namespace CytisusTrading.Windows;

public interface IUniverseService
{
    UniverseSnapshot BuildDailySnapshot(
        DateTimeOffset snapshotTime,
        UniverseConfiguration configuration,
        SecurityListSnapshot securities,
        BrokerPositionSnapshot positions);
}

public sealed class UniverseService : IUniverseService
{
    public UniverseSnapshot BuildDailySnapshot(
        DateTimeOffset snapshotTime,
        UniverseConfiguration configuration,
        SecurityListSnapshot securities,
        BrokerPositionSnapshot positions)
    {
        var heldSymbols = positions.Positions
            .Where(position => position.Quantity != 0)
            .Select(position => position.Symbol)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var date = snapshotTime.ToUniversalTime().ToString("yyyy-MM-dd");

        var entries = securities.Securities
            .OrderBy(security => security.Symbol, StringComparer.Ordinal)
            .Select(security => Evaluate(
                date,
                configuration,
                securities.SourceVersion,
                security,
                heldSymbols.Contains(security.Symbol)))
            .ToArray();

        return new UniverseSnapshot(
            1,
            date,
            configuration.Market,
            configuration.RuleVersion,
            securities.SourceVersion,
            snapshotTime.ToUniversalTime(),
            entries);
    }

    private static UniverseEntry Evaluate(
        string date,
        UniverseConfiguration configuration,
        string sourceVersion,
        SecurityReference security,
        bool alreadyHeld)
    {
        var reason = ExclusionReason(configuration, security);
        var included = reason is null;
        var disposition = included
            ? UniverseDisposition.Included
            : alreadyHeld
                ? UniverseDisposition.ReduceOnly
                : UniverseDisposition.Excluded;
        var displayReason = included
            ? "Included: all daily universe rules passed."
            : disposition == UniverseDisposition.ReduceOnly
                ? $"Reduce Only: {reason}"
                : $"Excluded: {reason}";

        return new UniverseEntry(
            date,
            security.Symbol,
            included,
            disposition,
            displayReason,
            new UniverseLiquidityMetrics(
                security.LastPrice,
                security.AverageDailyVolume,
                security.AverageDailyValue),
            new UniverseDataCoverage(
                security.ListingAgeDays,
                security.HistoryCoverageDays),
            security.Industry,
            configuration.RuleVersion,
            sourceVersion);
    }

    private static string? ExclusionReason(
        UniverseConfiguration configuration,
        SecurityReference security)
    {
        if (!security.Tradable)
        {
            return "security is not tradable";
        }

        if (security.LastPrice < configuration.MinimumPrice)
        {
            return "price is below the configured minimum";
        }

        if (security.AverageDailyVolume <
            configuration.MinimumAverageDailyVolume)
        {
            return "liquidity is below the configured minimum";
        }

        if (security.ListingAgeDays < configuration.MinimumListingAgeDays)
        {
            return "listing age is below the configured minimum";
        }

        if (security.HistoryCoverageDays <
            configuration.MinimumHistoryCoverageDays)
        {
            return "history coverage is below the configured minimum";
        }

        if (security.Suspended)
        {
            return "security is suspended";
        }

        if (security.Delisted)
        {
            return "security is delisted";
        }

        if (security.Abnormal)
        {
            return "security is marked abnormal";
        }

        if (!security.StrategyEligible)
        {
            return "strategy-specific placeholder filter rejected the security";
        }

        return null;
    }
}
