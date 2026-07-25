using System.Globalization;

namespace CytisusTrading.Windows;

public interface IParameterGovernanceService
{
    ParameterChangeDecision RequestChange(
        string strategyId,
        StrategyParameterDefinition definition,
        string oldValue,
        string newValue,
        int currentVersion,
        string requestedBy,
        bool confirmed,
        DateTimeOffset requestedAt);
    StrategyParameterChange ApplyBoundary(
        StrategyParameterChange change,
        DateTimeOffset effectiveAt);
}

public sealed class ParameterGovernanceService :
    IParameterGovernanceService
{
    public ParameterChangeDecision RequestChange(
        string strategyId,
        StrategyParameterDefinition definition,
        string oldValue,
        string newValue,
        int currentVersion,
        string requestedBy,
        bool confirmed,
        DateTimeOffset requestedAt)
    {
        if (!IsValueValid(definition, newValue, out var validationMessage))
        {
            return Decision(
                strategyId,
                definition,
                oldValue,
                newValue,
                currentVersion,
                requestedBy,
                requestedAt,
                ParameterChangeResult.Rejected,
                false,
                validationMessage);
        }

        var safety = definition.SafetyOverride;
        if (safety.RiskTier == RiskTier.High && !confirmed)
        {
            return Decision(
                strategyId,
                definition,
                oldValue,
                newValue,
                currentVersion,
                requestedBy,
                requestedAt,
                ParameterChangeResult.PendingConfirmation,
                true,
                $"High-risk preview: {definition.Label} changes from {oldValue} to {newValue}. New risk remains blocked until explicit confirmation and a safe boundary.");
        }

        var result = safety.ActivationMode switch
        {
            ParameterActivationMode.Immediate =>
                ParameterChangeResult.Applied,
            ParameterActivationMode.NextCycle =>
                ParameterChangeResult.PendingCycle,
            ParameterActivationMode.SafeBoundary =>
                ParameterChangeResult.PendingSafeBoundary,
            _ => ParameterChangeResult.Rejected
        };
        var decision = Decision(
            strategyId,
            definition,
            oldValue,
            newValue,
            currentVersion,
            requestedBy,
            requestedAt,
            result,
            safety.RiskTier == RiskTier.High &&
                result != ParameterChangeResult.Applied,
            result == ParameterChangeResult.Applied
                ? "Change applied immediately."
                : $"Change queued for {safety.ActivationMode}.");
        if (result == ParameterChangeResult.Applied)
        {
            return decision with
            {
                Change = decision.Change with
                {
                    EffectiveAt = requestedAt
                }
            };
        }
        return decision;
    }

    public StrategyParameterChange ApplyBoundary(
        StrategyParameterChange change,
        DateTimeOffset effectiveAt)
    {
        if (change.Result is not (
                ParameterChangeResult.PendingCycle or
                ParameterChangeResult.PendingSafeBoundary))
        {
            return change;
        }
        return change with
        {
            EffectiveAt = effectiveAt,
            Result = ParameterChangeResult.Applied
        };
    }

    public static bool IsValueValid(
        StrategyParameterDefinition definition,
        string value,
        out string message)
    {
        var validType = definition.Type switch
        {
            ParameterType.Number => double.TryParse(
                value,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out _),
            ParameterType.Integer => int.TryParse(
                value,
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out _),
            ParameterType.Boolean => bool.TryParse(value, out _),
            ParameterType.String => value.Length <= 512,
            _ => false
        };
        if (!validType)
        {
            message = "The parameter value has the wrong type.";
            return false;
        }

        if (definition.Type is ParameterType.Number or ParameterType.Integer)
        {
            var numeric = double.Parse(value, CultureInfo.InvariantCulture);
            var safety = definition.SafetyOverride;
            if (safety.HardMin is not null &&
                numeric < double.Parse(
                    safety.HardMin,
                    CultureInfo.InvariantCulture))
            {
                message = "The parameter value is below the Cytisus hard minimum.";
                return false;
            }
            if (safety.HardMax is not null &&
                numeric > double.Parse(
                    safety.HardMax,
                    CultureInfo.InvariantCulture))
            {
                message = "The parameter value is above the Cytisus hard maximum.";
                return false;
            }
        }

        message = "The parameter value is valid.";
        return true;
    }

    private static ParameterChangeDecision Decision(
        string strategyId,
        StrategyParameterDefinition definition,
        string oldValue,
        string newValue,
        int currentVersion,
        string requestedBy,
        DateTimeOffset requestedAt,
        ParameterChangeResult result,
        bool blocksNewRisk,
        string preview)
    {
        var change = new StrategyParameterChange(
            Guid.NewGuid().ToString("D"),
            strategyId,
            definition.Key,
            oldValue,
            newValue,
            requestedAt,
            null,
            requestedBy,
            definition.SafetyOverride.RiskTier,
            result == ParameterChangeResult.PendingConfirmation
                ? currentVersion
                : currentVersion + 1,
            definition.SafetyOverride.ActivationMode,
            result,
            currentVersion);
        return new ParameterChangeDecision(change, blocksNewRisk, preview);
    }
}
