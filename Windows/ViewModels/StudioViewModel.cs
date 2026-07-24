using System.Collections.ObjectModel;
using System.Globalization;

namespace CytisusTrading.Windows;

public sealed class StudioViewModel : ObservableObject
{
    private static readonly CultureInfo EnglishCulture = CultureInfo.GetCultureInfo("en-US");
    private readonly AppServices _services;
    private int _reviewCount;
    private string _lastReviewLabel = "No review run yet";
    private double _riskBudget;
    private double _coverageGate;
    private double _maxFactorWeight;

    public StudioViewModel()
        : this(AppServices.CreateOfflineFixture())
    {
    }

    public StudioViewModel(AppServices services)
    {
        _services = services;
        var settings = services.SettingsStore.LoadSettings();
        _riskBudget = settings.RiskBudget;
        _coverageGate = settings.CoverageGate;
        _maxFactorWeight = settings.MaxFactorWeight;
        ReplaceFactors(services.FactorRepository.LoadFactors());

        AppendLog(
            ApplicationLogLevel.Info,
            "Application",
            "Started in offline fixture mode");
    }

    public ObservableCollection<FactorItem> Factors { get; } = new();

    public bool FixtureMode => true;
    public StrategyMode CurrentStrategyMode => StrategyMode.PaperOnly;
    public bool LiveExecutionAvailable => false;

    public string ActiveFactorCount => Factors
        .Count(factor => factor.State == FactorState.Active)
        .ToString(EnglishCulture);

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
        private set => Set(ref _lastReviewLabel, value);
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
            PersistSettings();
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
            PersistSettings();
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
            PersistSettings();
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
        var result = _services.GovernanceService.RunReview(
            Factors.ToArray(),
            _reviewCount,
            MaxFactorWeight);

        ReplaceFactors(result.Factors);
        _services.FactorRepository.SaveFactors(result.Factors);
        AppendAudit(
            "FixtureFactorReview",
            new Dictionary<string, string>
            {
                ["changed_factor_ids"] = string.Join(",", result.ChangedFactorIds),
                ["review_count"] = _reviewCount.ToString(EnglishCulture)
            });
    }

    public void ResetDemo()
    {
        _reviewCount = 0;
        LastReviewLabel = "No review run yet";
        ReplaceFactors(_services.FactorRepository.ResetToFixtures());
        AppendAudit(
            "FixtureStateReset",
            new Dictionary<string, string> { ["fixture_mode"] = "true" });
    }

    private void ReplaceFactors(IEnumerable<FactorItem> factors)
    {
        Factors.Clear();
        foreach (var factor in factors)
        {
            Factors.Add(factor);
        }
        RaiseSummary();
    }

    private void PersistSettings()
    {
        try
        {
            _services.SettingsStore.SaveSettings(new AppSettings(
                true,
                StrategyMode.PaperOnly,
                HealthState.Degraded,
                RiskBudget,
                CoverageGate,
                MaxFactorWeight));
        }
        catch
        {
            AppendLog(
                ApplicationLogLevel.Error,
                "Persistence",
                "Failed to save non-sensitive settings");
        }
    }

    private void AppendLog(ApplicationLogLevel level, string module, string message)
    {
        _services.LogStore.AppendLog(new ApplicationLogEntry(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            level,
            module,
            message,
            null,
            new Dictionary<string, string> { ["fixture_mode"] = "true" }));
    }

    private void AppendAudit(string action, IReadOnlyDictionary<string, string> context)
    {
        _services.AuditStore.AppendAuditEvent(new AuditEvent(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            AuditEventCategory.FactorLifecycle,
            action,
            AuditResult.Completed,
            "local-user",
            Guid.NewGuid().ToString("D"),
            context));
    }

    private void RaiseSummary()
    {
        Raise(nameof(ActiveFactorCount));
        Raise(nameof(ShadowQueueCount));
        Raise(nameof(WeightedCoverage));
    }
}
