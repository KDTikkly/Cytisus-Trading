using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public static class ProductVersion
{
    public const string Current = "1.1.0";
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum StrategyMode
{
    PaperOnly,
    Live
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum HealthState
{
    Healthy,
    Degraded,
    Unhealthy
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FactorState
{
    Candidate,
    Shadow,
    Active,
    Reduced,
    Probation,
    Retired,
    Quarantined
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ExecutionRecordType
{
    StrategyIntent,
    RiskDecision,
    InternalTransfer,
    BrokerOrder,
    BrokerFill,
    VirtualAllocation,
    AllocationShortfall
}

public sealed class FactorItem : INotifyPropertyChanged
{
    private FactorState _state;
    private double _ic;
    private double _weight;
    private int _evidenceWindows;
    private string _reason = string.Empty;

    [JsonPropertyName("factor_id")]
    public string FactorId { get; init; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("category")]
    public string Category { get; init; } = string.Empty;

    [JsonPropertyName("state")]
    public FactorState State
    {
        get => _state;
        set
        {
            if (_state == value)
            {
                return;
            }

            _state = value;
            Raise();
            Raise(nameof(StateLabel));
        }
    }

    [JsonPropertyName("ic")]
    public double Ic
    {
        get => _ic;
        set
        {
            if (Math.Abs(_ic - value) < 0.000001)
            {
                return;
            }

            _ic = value;
            Raise();
            Raise(nameof(IcDisplay));
        }
    }

    [JsonPropertyName("ir")]
    public double Ir { get; init; }

    [JsonPropertyName("coverage")]
    public double Coverage { get; init; }

    [JsonPropertyName("weight")]
    public double Weight
    {
        get => _weight;
        set
        {
            if (Math.Abs(_weight - value) < 0.000001)
            {
                return;
            }

            _weight = value;
            Raise();
            Raise(nameof(WeightDisplay));
        }
    }

    [JsonPropertyName("evidence_windows")]
    public int EvidenceWindows
    {
        get => _evidenceWindows;
        set
        {
            if (_evidenceWindows == value)
            {
                return;
            }

            _evidenceWindows = value;
            Raise();
        }
    }

    [JsonPropertyName("reason")]
    public string Reason
    {
        get => _reason;
        set
        {
            if (_reason == value)
            {
                return;
            }

            _reason = value;
            Raise();
        }
    }

    [JsonIgnore]
    public string StateLabel => State.ToString();

    [JsonIgnore]
    public string IcDisplay => Ic.ToString("0.000", CultureInfo.InvariantCulture);

    [JsonIgnore]
    public string IrDisplay => Ir.ToString("0.00", CultureInfo.InvariantCulture);

    [JsonIgnore]
    public string CoverageDisplay => Coverage.ToString("P0", CultureInfo.GetCultureInfo("en-US"));

    [JsonIgnore]
    public string WeightDisplay => Weight.ToString("P0", CultureInfo.GetCultureInfo("en-US"));

    public FactorItem Clone()
    {
        return new FactorItem
        {
            FactorId = FactorId,
            Name = Name,
            Category = Category,
            State = State,
            Ic = Ic,
            Ir = Ir,
            Coverage = Coverage,
            Weight = Weight,
            EvidenceWindows = EvidenceWindows,
            Reason = Reason
        };
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Raise([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed record AppSettings(
    bool FixtureMode,
    StrategyMode StrategyMode,
    HealthState Health,
    double RiskBudget,
    double CoverageGate,
    double MaxFactorWeight)
{
    public string CliExecutablePath { get; init; } = string.Empty;
    public string DefaultMarket { get; init; } = "US";
    public string CacheDirectory { get; init; } = string.Empty;
    public int ProcessTimeoutSeconds { get; init; } = 15;
    public int DataRetentionDays { get; init; } = 90;
    public int LogRetentionDays { get; init; } = 30;

    public static AppSettings Default { get; } = new(
        true,
        StrategyMode.PaperOnly,
        HealthState.Degraded,
        0.50,
        0.80,
        0.35);
}
