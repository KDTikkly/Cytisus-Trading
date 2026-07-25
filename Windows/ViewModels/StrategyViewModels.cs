using System.Collections.ObjectModel;

namespace CytisusTrading.Windows;

public sealed class StrategyParameterViewModel : ObservableObject
{
    private string _value;
    private string _draftValue;
    private bool _confirmationChecked;
    private string _previewText = "No pending change.";
    private string _status = "Current";

    public StrategyParameterViewModel(
        StrategyParameterDefinition definition,
        string value)
    {
        Definition = definition;
        _value = value;
        _draftValue = value;
    }

    public StrategyParameterDefinition Definition { get; }
    public string Key => Definition.Key;
    public string Label => Definition.Label;
    public string Description => Definition.Description;
    public string TypeLabel => Definition.Type.ToString();
    public string RiskTierLabel => Definition.SafetyOverride.RiskTier.ToString();
    public string ActivationLabel =>
        Definition.SafetyOverride.ActivationMode.ToString();
    public bool IsHighRisk =>
        Definition.SafetyOverride.RiskTier == RiskTier.High;
    public string RangeLabel =>
        Definition.SafetyOverride.HardMin is null &&
        Definition.SafetyOverride.HardMax is null
            ? "Cytisus bounded text"
            : $"Hard range {Definition.SafetyOverride.HardMin ?? "-"} to {Definition.SafetyOverride.HardMax ?? "-"}";

    public string Value
    {
        get => _value;
        set => Set(ref _value, value);
    }

    public string DraftValue
    {
        get => _draftValue;
        set => Set(ref _draftValue, value);
    }

    public bool ConfirmationChecked
    {
        get => _confirmationChecked;
        set => Set(ref _confirmationChecked, value);
    }

    public string PreviewText
    {
        get => _previewText;
        set => Set(ref _previewText, value);
    }

    public string Status
    {
        get => _status;
        set => Set(ref _status, value);
    }
}

public sealed class StrategyItemViewModel : ObservableObject
{
    private StrategyMode _mode;
    private StrategyRuntimeState _runtimeState;
    private HealthState _health;
    private DateTimeOffset? _lastHeartbeat;
    private int _parameterVersion;
    private bool _blocksNewRisk;
    private LiveToPaperTransition _transition;
    private double _capitalBudget;
    private string _allocationExplanation =
        "Allocation has not been calculated.";

    public StrategyItemViewModel(
        StrategyManifest manifest,
        StrategyParameterSchema parameterSchema,
        StrategyPersistentState state)
    {
        Manifest = manifest;
        ParameterSchema = parameterSchema;
        _mode = state.Mode;
        _runtimeState = state.RuntimeState;
        _health = state.Health;
        _lastHeartbeat = state.LastHeartbeat;
        _parameterVersion = state.ParameterVersion;
        _blocksNewRisk = state.BlocksNewRisk;
        _transition = state.LiveToPaperTransition;
        foreach (var definition in parameterSchema.Parameters)
        {
            var value = state.ParameterValues.TryGetValue(
                definition.Key,
                out var stored)
                ? stored
                : definition.DefaultValue;
            Parameters.Add(new StrategyParameterViewModel(
                definition,
                value));
        }
    }

    public StrategyManifest Manifest { get; }
    public StrategyParameterSchema ParameterSchema { get; }
    public string StrategyId => Manifest.StrategyId;
    public string Name => Manifest.Name;
    public string Version => Manifest.Version;
    public string SourceLabel => Manifest.Source.ToString();

    public StrategyMode Mode
    {
        get => _mode;
        set => Set(ref _mode, value);
    }

    public StrategyRuntimeState RuntimeState
    {
        get => _runtimeState;
        set => Set(ref _runtimeState, value);
    }

    public HealthState Health
    {
        get => _health;
        set => Set(ref _health, value);
    }

    public DateTimeOffset? LastHeartbeat
    {
        get => _lastHeartbeat;
        set
        {
            if (Set(ref _lastHeartbeat, value))
            {
                Raise(nameof(LastHeartbeatDisplay));
            }
        }
    }

    public string LastHeartbeatDisplay => LastHeartbeat.HasValue
        ? LastHeartbeat.Value.ToLocalTime().ToString("g")
        : "No heartbeat";

    public int ParameterVersion
    {
        get => _parameterVersion;
        set => Set(ref _parameterVersion, value);
    }

    public bool BlocksNewRisk
    {
        get => _blocksNewRisk;
        set => Set(ref _blocksNewRisk, value);
    }

    public LiveToPaperTransition LiveToPaperTransition
    {
        get => _transition;
        set => Set(ref _transition, value);
    }

    public ObservableCollection<StrategyParameterViewModel> Parameters { get; } =
        new();
    public ObservableCollection<StrategyParameterChange> ParameterChanges { get; } =
        new();
    public ObservableCollection<StrategySignal> Signals { get; } = new();
    public ObservableCollection<StrategyTarget> Targets { get; } = new();
    public ObservableCollection<StrategyIntentRecord> Intents { get; } = new();
    public ObservableCollection<StrategyCycleSummary> Cycles { get; } = new();

    public double CapitalBudget
    {
        get => _capitalBudget;
        set
        {
            if (Set(ref _capitalBudget, value))
            {
                Raise(nameof(CapitalBudgetDisplay));
            }
        }
    }

    public string CapitalBudgetDisplay =>
        CapitalBudget.ToString(
            "C0",
            System.Globalization.CultureInfo.GetCultureInfo("en-US"));

    public string AllocationExplanation
    {
        get => _allocationExplanation;
        set => Set(ref _allocationExplanation, value);
    }

    public StrategyPersistentState PersistentState()
    {
        return new StrategyPersistentState(
            StrategyId,
            Mode,
            RuntimeState,
            Health,
            LastHeartbeat,
            ParameterVersion,
            Parameters.ToDictionary(
                parameter => parameter.Key,
                parameter => parameter.Value,
                StringComparer.Ordinal),
            BlocksNewRisk,
            LiveToPaperTransition);
    }
}
