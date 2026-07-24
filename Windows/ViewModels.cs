using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Media;

namespace CytisusTrading.Windows;

public enum FactorState
{
    Candidate,
    Shadow,
    Active,
    Probation,
    Retired,
    Quarantined
}

public sealed class FactorItem : INotifyPropertyChanged
{
    private FactorState _state;
    private double _ic;
    private double _weight;
    private int _evidenceWindows;
    private string _reason;

    public FactorItem(
        string name,
        string category,
        FactorState state,
        double ic,
        double ir,
        double coverage,
        double weight,
        int evidenceWindows,
        string reason)
    {
        Name = name;
        Category = category;
        _state = state;
        _ic = ic;
        Ir = ir;
        Coverage = coverage;
        _weight = weight;
        _evidenceWindows = evidenceWindows;
        _reason = reason;
    }

    public string Name { get; }
    public string Category { get; }
    public double Ir { get; }
    public double Coverage { get; }

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
            Raise(nameof(StateBrush));
            Raise(nameof(StateBackground));
        }
    }

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

    public string StateLabel => State.ToString();
    public string IcDisplay => Ic.ToString("0.000", CultureInfo.InvariantCulture);
    public string IrDisplay => Ir.ToString("0.00", CultureInfo.InvariantCulture);
    public string CoverageDisplay => Coverage.ToString("P0", CultureInfo.GetCultureInfo("en-US"));
    public string WeightDisplay => Weight.ToString("P0", CultureInfo.GetCultureInfo("en-US"));

    public Brush StateBrush => State switch
    {
        FactorState.Candidate => BrushFrom("#FF55D7F1"),
        FactorState.Shadow => BrushFrom("#FFA68BFA"),
        FactorState.Active => BrushFrom("#FF54D38A"),
        FactorState.Probation => BrushFrom("#FFF7B955"),
        FactorState.Retired => BrushFrom("#FF9AA8BC"),
        FactorState.Quarantined => BrushFrom("#FFFF6E80"),
        _ => Brushes.White
    };

    public Brush StateBackground => State switch
    {
        FactorState.Candidate => BrushFrom("#2255D7F1"),
        FactorState.Shadow => BrushFrom("#22A68BFA"),
        FactorState.Active => BrushFrom("#2254D38A"),
        FactorState.Probation => BrushFrom("#22F7B955"),
        FactorState.Retired => BrushFrom("#229AA8BC"),
        FactorState.Quarantined => BrushFrom("#22FF6E80"),
        _ => Brushes.Transparent
    };

    public event PropertyChangedEventHandler? PropertyChanged;

    private static Brush BrushFrom(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private void Raise([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed class StudioViewModel : INotifyPropertyChanged
{
    private static readonly CultureInfo EnglishCulture = CultureInfo.GetCultureInfo("en-US");

    private int _reviewCount;
    private string _lastReviewLabel = "No review run yet";
    private double _riskBudget = 0.50;
    private double _coverageGate = 0.80;
    private double _maxFactorWeight = 0.35;

    public StudioViewModel()
    {
        ResetFactors();
    }

    public ObservableCollection<FactorItem> Factors { get; } = new();

    public string ActiveFactorCount => Factors.Count(factor => factor.State == FactorState.Active).ToString(EnglishCulture);

    public string ShadowQueueCount => Factors
        .Count(factor => factor.State is FactorState.Shadow or FactorState.Candidate)
        .ToString(EnglishCulture);

    public string WeightedCoverage
    {
        get
        {
            var active = Factors
                .Where(factor => factor.State is FactorState.Active or FactorState.Probation)
                .ToArray();
            var totalWeight = active.Sum(factor => factor.Weight);
            if (totalWeight <= 0)
            {
                return "0%";
            }

            var value = active.Sum(factor => factor.Coverage * factor.Weight) / totalWeight;
            return value.ToString("P0", EnglishCulture);
        }
    }

    public string LastReviewLabel
    {
        get => _lastReviewLabel;
        private set
        {
            _lastReviewLabel = value;
            Raise();
        }
    }

    public double RiskBudget
    {
        get => _riskBudget;
        set
        {
            if (!Set(ref _riskBudget, value))
            {
                return;
            }

            Raise(nameof(RiskBudgetDisplay));
            Raise(nameof(CurrentProposal));
        }
    }

    public double CoverageGate
    {
        get => _coverageGate;
        set
        {
            if (!Set(ref _coverageGate, value))
            {
                return;
            }

            Raise(nameof(CoverageGateDisplay));
            Raise(nameof(CurrentProposal));
        }
    }

    public double MaxFactorWeight
    {
        get => _maxFactorWeight;
        set
        {
            if (!Set(ref _maxFactorWeight, value))
            {
                return;
            }

            Raise(nameof(MaxFactorWeightDisplay));
            Raise(nameof(CurrentProposal));
        }
    }

    public string RiskBudgetDisplay => $"{RiskBudget:0.00}%";
    public string CoverageGateDisplay => CoverageGate.ToString("P0", EnglishCulture);
    public string MaxFactorWeightDisplay => MaxFactorWeight.ToString("P0", EnglishCulture);

    public string CurrentProposal =>
        $"Coverage at least {CoverageGateDisplay} | Weight cap {MaxFactorWeightDisplay} | Risk budget {RiskBudgetDisplay}";

    public void RunReview()
    {
        _reviewCount += 1;
        LastReviewLabel = $"Last review {DateTime.Now.ToString("t", EnglishCulture)}";

        foreach (var factor in Factors)
        {
            switch (factor.Name)
            {
                case "Volatility Term Structure":
                    factor.EvidenceWindows += 1;
                    if (factor.EvidenceWindows >= 6 && _reviewCount >= 2)
                    {
                        factor.State = FactorState.Active;
                        factor.Weight = Math.Min(0.05, MaxFactorWeight);
                        factor.Reason = "Passed twice; enable with a 5% cap";
                    }
                    else
                    {
                        factor.Reason = "First pass complete; awaiting confirmation";
                    }

                    break;

                case "Volume Impact":
                    factor.Ic -= 0.003;
                    if (_reviewCount >= 2)
                    {
                        factor.State = FactorState.Retired;
                        factor.Weight = 0;
                        factor.Reason = "Failed three reviews; 126-day cooldown";
                    }
                    else
                    {
                        factor.Reason = "Second failure; probation continues";
                    }

                    break;

                case "Short-Term Reversal":
                    factor.EvidenceWindows += 1;
                    factor.State = FactorState.Shadow;
                    factor.Reason = "Candidate data gate passed; moved to shadow review";
                    break;
            }
        }

        RaiseSummary();
    }

    public void ResetDemo()
    {
        _reviewCount = 0;
        LastReviewLabel = "No review run yet";
        ResetFactors();
        RaiseSummary();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void ResetFactors()
    {
        Factors.Clear();
        Factors.Add(new FactorItem(
            "Medium-Term Momentum",
            "Directional",
            FactorState.Active,
            0.041,
            0.61,
            0.96,
            0.22,
            8,
            "Cleared every out-of-sample gate"));
        Factors.Add(new FactorItem(
            "Low-Volatility Quality",
            "Defensive",
            FactorState.Active,
            0.036,
            0.54,
            0.92,
            0.18,
            7,
            "Stable contribution after costs"));
        Factors.Add(new FactorItem(
            "Volatility Term Structure",
            "Derivatives",
            FactorState.Shadow,
            0.029,
            0.41,
            0.84,
            0,
            5,
            "Waiting for the sixth out-of-sample window"));
        Factors.Add(new FactorItem(
            "Volume Impact",
            "Market Microstructure",
            FactorState.Probation,
            0.014,
            0.21,
            0.76,
            0.08,
            9,
            "One review below the IC threshold"));
        Factors.Add(new FactorItem(
            "Short-Term Reversal",
            "Directional",
            FactorState.Candidate,
            0.024,
            0.35,
            0.82,
            0,
            2,
            "Continue collecting frozen OOS evidence"));
        Factors.Add(new FactorItem(
            "Legacy Sentiment Proxy",
            "Alternative Data",
            FactorState.Retired,
            -0.008,
            -0.12,
            0.67,
            0,
            11,
            "Failed three reviews and entered cooldown"));
    }

    private void RaiseSummary()
    {
        Raise(nameof(ActiveFactorCount));
        Raise(nameof(ShadowQueueCount));
        Raise(nameof(WeightedCoverage));
    }

    private bool Set(ref double field, double value, [CallerMemberName] string? propertyName = null)
    {
        if (Math.Abs(field - value) < 0.000001)
        {
            return false;
        }

        field = value;
        Raise(propertyName);
        return true;
    }

    private void Raise([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
