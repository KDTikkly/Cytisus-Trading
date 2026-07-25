using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CytisusTrading.Windows;

public sealed class StudioViewModel : ObservableObject
{
    private static readonly CultureInfo EnglishCulture =
        CultureInfo.GetCultureInfo("en-US");
    private readonly AppServices _services;
    private int _reviewCount;
    private string _lastReviewLabel = "No review run yet";
    private double _riskBudget;
    private double _coverageGate;
    private double _maxFactorWeight;
    private bool _fixtureMode;
    private string _cliExecutablePath = string.Empty;
    private string _defaultMarket = "US";
    private string _cacheDirectory = string.Empty;
    private double _processTimeoutSeconds = 15;
    private double _dataRetentionDays = 90;
    private double _logRetentionDays = 30;
    private string _cliVersion = "Unavailable";
    private LongbridgeStatusState _cliStatusState = LongbridgeStatusState.Missing;
    private string _lastCheckDisplay = "Not checked";
    private string _dataFreshnessDisplay = "No market snapshot";
    private string _dataPermissionsSummary = "No data permissions discovered";
    private string _marketSession = "Unavailable";
    private string _cacheSizeDisplay = "0 KB";
    private string _cliStatusMessage =
        "Enable fixture mode or select an installed Longbridge CLI.";
    private string _cliPathDisplay = "Fixture mode (no executable)";
    private string _longbridgeEnvironment = "Unknown";
    private string _longbridgeChannel = "Unknown";
    private string _longbridgeConnectivity = "Not checked";
    private string _longbridgeFailureCategory = "None";
    private string _longbridgeAuthorizationUrl = string.Empty;
    private string _longbridgeShortCode = string.Empty;
    private LongbridgePaperMode _selectedPaperMode =
        LongbridgePaperMode.LocalPaper;
    private CancellationTokenSource? _longbridgeSignInCancellation;
    private bool _globalLiveLock;
    private StrategyItemViewModel? _selectedStrategy;
    private string _strategyManifestPath = string.Empty;
    private string _strategyStatusMessage =
        "Official fixture strategy is ready in Local Paper.";
    private string _latestStrategyAlert =
        "Local Paper is available without Longbridge CLI. Live remains rejecting.";
    private string _logSearchText = string.Empty;
    private string _selectedLogSeverity = "All";
    private LiveToPaperTransition _selectedTransition =
        LiveToPaperTransition.StopOpeningRisk;
    private readonly Dictionary<string, ExternalStrategyRuntime>
        _externalRuntimes = new(StringComparer.Ordinal);
    private NormalizedResearchDataset? _researchDataset;
    private RegimeSnapshot? _regimeSnapshot;
    private CapitalAllocationResult? _capitalAllocation;
    private ExecutionStateSnapshot _executionState =
        ExecutionStateSnapshot.Empty;
    private string _candidateSearchStatus =
        "Tiny deterministic search has not run.";
    private string _pythonExecutablePath = string.Empty;
    private string _quantWorkerRootDirectory = string.Empty;
    private ComputeSchedulingMode _computeSchedulingMode =
        ComputeSchedulingMode.Auto;
    private int _agentCallLimit = 3;
    private int _agentInputTokenLimit = 12000;
    private int _agentOutputTokenLimit = 4000;
    private decimal _agentDailySpendingLimit = 5m;
    private decimal _agentMonthlySpendingLimit = 50m;

    public StudioViewModel()
        : this(AppServices.CreateOfflineFixture())
    {
    }

    public StudioViewModel(AppServices services)
    {
        _services = services;
        _services.LongbridgeAuthentication.AuthenticationProgressChanged +=
            progress =>
            {
                var dispatcher = System.Windows.Application.Current?.Dispatcher;
                if (dispatcher is null)
                {
                    ApplyAuthenticationProgress(progress);
                }
                else
                {
                    dispatcher.BeginInvoke(
                        () => ApplyAuthenticationProgress(progress));
                }
            };
        ModelProviders = new ModelProvidersViewModel(
            services.ModelProviderManager);
        LocalStudio = services.LocalStudioService.LoadOrCreateFixtureState();
        ComputeDevices = LocalStudioService.DiscoverDevices();
        var settings = services.SettingsStore.LoadSettings();
        _riskBudget = settings.RiskBudget;
        _coverageGate = settings.CoverageGate;
        _maxFactorWeight = settings.MaxFactorWeight;
        _fixtureMode = settings.FixtureMode;
        _cliExecutablePath = settings.CliExecutablePath;
        _defaultMarket = string.IsNullOrWhiteSpace(settings.DefaultMarket)
            ? "US"
            : settings.DefaultMarket;
        _cacheDirectory = string.IsNullOrWhiteSpace(settings.CacheDirectory)
            ? JsonMarketDataCache.DefaultDirectory()
            : settings.CacheDirectory;
        _processTimeoutSeconds = settings.ProcessTimeoutSeconds > 0
            ? settings.ProcessTimeoutSeconds
            : 15;
        _dataRetentionDays = settings.DataRetentionDays > 0
            ? settings.DataRetentionDays
            : 90;
        _logRetentionDays = settings.LogRetentionDays > 0
            ? settings.LogRetentionDays
            : 30;
        _globalLiveLock = settings.GlobalLiveLock;
        _pythonExecutablePath = settings.PythonExecutablePath;
        _quantWorkerRootDirectory = settings.QuantWorkerRootDirectory;
        _computeSchedulingMode = settings.ComputeSchedulingMode;
        _agentCallLimit = settings.AgentCallLimit;
        _agentInputTokenLimit = settings.AgentInputTokenLimit;
        _agentOutputTokenLimit = settings.AgentOutputTokenLimit;
        _agentDailySpendingLimit = settings.AgentDailySpendingLimit;
        _agentMonthlySpendingLimit = settings.AgentMonthlySpendingLimit;

        ReplaceFactors(services.FactorRepository.LoadFactors());
        foreach (var entry in services.LogStore.LoadLogs(50))
        {
            ApplicationLogs.Add(entry);
        }
        InitializeStrategies();
        InitializeResearch();
        InitializeExecution();

        AppendLog(
            ApplicationLogLevel.Info,
            "Application",
            _fixtureMode
                ? "Started in offline fixture mode"
                : "Started with local CLI mode selected",
            new Dictionary<string, string>
            {
                ["fixture_mode"] = _fixtureMode ? "true" : "false"
            });

        if (_fixtureMode)
        {
            RefreshFixtureData();
        }
    }

    public ObservableCollection<FactorItem> Factors { get; } = new();
    public ObservableCollection<UniverseEntry> UniverseEntries { get; } = new();
    public ObservableCollection<ApplicationLogEntry> ApplicationLogs { get; } = new();
    public ObservableCollection<StrategyItemViewModel> Strategies { get; } = new();
    public ObservableCollection<FactorResearchSummary> ResearchFactors { get; } =
        new();
    public ObservableCollection<FactorTrial> RecentFactorTrials { get; } =
        new();
    public ObservableCollection<string> LogSeverityOptions { get; } =
        new(new[] { "All", "Debug", "Info", "Warning", "Error", "Critical" });
    public ModelProvidersViewModel ModelProviders { get; }
    public LocalStudioState LocalStudio { get; }
    public IReadOnlyList<ComputeDevice> ComputeDevices { get; }
    public IReadOnlyList<ComputeSchedulingMode> ComputeSchedulingModes { get; } =
        Enum.GetValues<ComputeSchedulingMode>();
    public string QuantWorkerStatus =>
        string.IsNullOrWhiteSpace(PythonExecutablePath)
            ? "Stopped until an approved Python interpreter is selected."
            : "Stopped. The selected interpreter will be validated before a Worker starts.";
    public string AgentSafetyStatus =>
        "Project-only patches, bounded cost, no shell, no secrets, and no arbitrary files.";
    public string ExecutionModuleStatus =>
        "Synthetic child proposals only; every proposal must enter the Execution Gateway.";
    public string LongbridgeAccountStatus =>
        CliStatusState == LongbridgeStatusState.ReadyPaper
            ? "Longbridge Paper is ready through the Execution Gateway."
            : "Local Paper is ready. Longbridge Paper requires a verified Paper channel.";

    public string PythonExecutablePath
    {
        get => _pythonExecutablePath;
        set
        {
            if (Set(ref _pythonExecutablePath, value))
            {
                PersistSettings();
                Raise(nameof(QuantWorkerStatus));
            }
        }
    }

    public string QuantWorkerRootDirectory
    {
        get => _quantWorkerRootDirectory;
        set
        {
            if (Set(ref _quantWorkerRootDirectory, value))
            {
                PersistSettings();
            }
        }
    }

    public ComputeSchedulingMode ComputeSchedulingMode
    {
        get => _computeSchedulingMode;
        set
        {
            if (Set(ref _computeSchedulingMode, value))
            {
                PersistSettings();
            }
        }
    }

    public string AgentCostLimitStatus =>
        $"{_agentCallLimit} calls | {_agentInputTokenLimit} input tokens | {_agentOutputTokenLimit} output tokens | {_agentDailySpendingLimit:C} daily | {_agentMonthlySpendingLimit:C} monthly";

    public IReadOnlyList<TradeIntent> ExecutionIntents =>
        _executionState.Intents;
    public IReadOnlyList<RiskDecision> ExecutionRiskDecisions =>
        _executionState.RiskDecisions;
    public IReadOnlyList<InternalTransfer> ExecutionTransfers =>
        _executionState.InternalTransfers;
    public IReadOnlyList<BrokerOrder> ExecutionOrders =>
        _executionState.BrokerOrders;
    public IReadOnlyList<BrokerFill> ExecutionFills =>
        _executionState.BrokerFills;
    public IReadOnlyList<VirtualAllocation> ExecutionAllocations =>
        _executionState.VirtualAllocations;
    public IReadOnlyList<AllocationShortfall> ExecutionShortfalls =>
        _executionState.AllocationShortfalls;
    public IReadOnlyList<VirtualLedgerPosition> VirtualLedgerPositions =>
        _executionState.LedgerPositions;
    public IReadOnlyList<ReconciliationEvent> ReconciliationEvents =>
        _executionState.Reconciliations;
    public IReadOnlyList<CriticalRiskEvent> CriticalRiskEvents =>
        _executionState.RiskEvents;
    public IReadOnlyList<BrokerNetPositionView> BrokerNetPositions =>
        _executionState.LedgerPositions
            .GroupBy(position => position.Symbol, StringComparer.Ordinal)
            .Select(group =>
            {
                var latest = _executionState.Reconciliations
                    .LastOrDefault(item => item.Symbol == group.Key);
                return new BrokerNetPositionView(
                    group.Key,
                    latest?.BrokerQuantity ??
                        group.Sum(position =>
                            position.VirtualQuantity),
                    latest?.Status ??
                        ReconciliationStatus.Reconciled);
            })
            .OrderBy(item => item.Symbol, StringComparer.Ordinal)
            .ToArray();
    public string ExecutionSafetyStatus =>
        "Local Paper is independent from Longbridge CLI. Live submission is intentionally rejecting.";
    public string PersistentExecutionAlert =>
        _executionState.BlockedSymbols.Count == 0
            ? "No unresolved reconciliation risk event."
            : _executionState.RiskEvents.LastOrDefault(item =>
                _executionState.BlockedSymbols.Contains(
                    item.Symbol,
                    StringComparer.Ordinal))?.Message ??
              "An unresolved reconciliation risk event blocks new risk.";

    public string CandidateSearchStatus
    {
        get => _candidateSearchStatus;
        private set => Set(ref _candidateSearchStatus, value);
    }

    public string TrendProbability =>
        (_regimeSnapshot?.Trend ?? 0).ToString("P1", EnglishCulture);
    public string RangeProbability =>
        (_regimeSnapshot?.Range ?? 0).ToString("P1", EnglishCulture);
    public string HighVolatilityProbability =>
        (_regimeSnapshot?.HighVolatility ?? 0)
        .ToString("P1", EnglishCulture);
    public string CrisisProbability =>
        (_regimeSnapshot?.Crisis ?? 0).ToString("P1", EnglishCulture);
    public string RegimeUncertainty =>
        (_regimeSnapshot?.Uncertainty ?? 0)
        .ToString("P1", EnglishCulture);
    public string PortfolioRiskDisplay =>
        (_regimeSnapshot?.RiskMultiplier ?? 0)
        .ToString("P0", EnglishCulture);
    public string CapitalUsageDisplay =>
        (_capitalAllocation?.TotalRiskBudget ?? 0)
        .ToString("C0", EnglishCulture);
    public string AllocatorSummary => _capitalAllocation is null
        ? "Allocator has not run."
        : $"Risk budget {CapitalUsageDisplay} | Regime multiplier {PortfolioRiskDisplay} | Alpha tilt capped at {DynamicCapitalAllocator.MaximumAlphaTilt:P0}.";

    public StrategyMode CurrentStrategyMode =>
        SelectedStrategy?.Mode ?? StrategyMode.PaperOnly;
    public LongbridgePaperMode SelectedPaperMode
    {
        get => _selectedPaperMode;
        private set => Set(ref _selectedPaperMode, value);
    }
    public bool LiveExecutionAvailable => false;

    public bool GlobalLiveLock
    {
        get => _globalLiveLock;
        set
        {
            if (!Set(ref _globalLiveLock, value))
            {
                return;
            }
            if (!value)
            {
                foreach (var strategy in Strategies.Where(item =>
                             item.Mode == StrategyMode.Live))
                {
                    strategy.Mode = StrategyMode.PaperOnly;
                    strategy.LiveToPaperTransition =
                        LiveToPaperTransition.StopOpeningRisk;
                    strategy.BlocksNewRisk = true;
                    SaveStrategy(strategy);
                }
                LatestStrategyAlert =
                    "Global Live Lock is OFF. All strategies use Local Paper.";
            }
            PersistSettings();
            Raise(nameof(GlobalLiveLockStatus));
            Raise(nameof(GlobalLiveLockLabel));
            RaiseDashboard();
            AppendAudit(
                "GlobalLiveLockChanged",
                new Dictionary<string, string>
                {
                    ["enabled"] = value ? "true" : "false"
                },
                AuditEventCategory.Settings);
        }
    }

    public string GlobalLiveLockStatus => GlobalLiveLock
        ? "ON: authorized strategies may select Live mode"
        : "OFF: every strategy remains in Local Paper";
    public string GlobalLiveLockLabel => GlobalLiveLock ? "ON" : "OFF";

    public StrategyItemViewModel? SelectedStrategy
    {
        get => _selectedStrategy;
        set
        {
            if (Set(ref _selectedStrategy, value))
            {
                Raise(nameof(CurrentStrategyMode));
                Raise(nameof(LiveAuthorizationSummary));
            }
        }
    }

    public string StrategyManifestPath
    {
        get => _strategyManifestPath;
        set => Set(ref _strategyManifestPath, value);
    }

    public string StrategyStatusMessage
    {
        get => _strategyStatusMessage;
        private set => Set(ref _strategyStatusMessage, value);
    }

    public string LatestStrategyAlert
    {
        get => _latestStrategyAlert;
        private set => Set(ref _latestStrategyAlert, value);
    }

    public LiveToPaperTransition SelectedTransition
    {
        get => _selectedTransition;
        set => Set(ref _selectedTransition, value);
    }

    public string LogSearchText
    {
        get => _logSearchText;
        set
        {
            if (Set(ref _logSearchText, value))
            {
                Raise(nameof(FilteredApplicationLogs));
            }
        }
    }

    public string SelectedLogSeverity
    {
        get => _selectedLogSeverity;
        set
        {
            if (Set(ref _selectedLogSeverity, value))
            {
                Raise(nameof(FilteredApplicationLogs));
            }
        }
    }

    public IEnumerable<ApplicationLogEntry> FilteredApplicationLogs =>
        ApplicationLogs.Where(entry =>
            (SelectedLogSeverity == "All" ||
             string.Equals(
                 entry.Severity.ToString(),
                 SelectedLogSeverity,
                 StringComparison.Ordinal)) &&
            (string.IsNullOrWhiteSpace(LogSearchText) ||
             entry.Message.Contains(
                 LogSearchText,
                 StringComparison.OrdinalIgnoreCase) ||
             entry.Module.Contains(
                 LogSearchText,
                 StringComparison.OrdinalIgnoreCase) ||
             (entry.StrategyId?.Contains(
                 LogSearchText,
                 StringComparison.OrdinalIgnoreCase) ?? false) ||
             (entry.CorrelationId?.Contains(
                 LogSearchText,
                 StringComparison.OrdinalIgnoreCase) ?? false) ||
             (entry.CycleId?.Contains(
                 LogSearchText,
                 StringComparison.OrdinalIgnoreCase) ?? false)))
        .Reverse();

    public string PaperStrategyCount => Strategies
        .Count(strategy => strategy.Mode == StrategyMode.PaperOnly)
        .ToString(EnglishCulture);

    public string LiveStrategyCount => Strategies
        .Count(strategy => strategy.Mode == StrategyMode.Live)
        .ToString(EnglishCulture);

    public string HealthyStrategyCount => Strategies
        .Count(strategy => strategy.Health == HealthState.Healthy)
        .ToString(EnglishCulture);

    public string LatestCycleDisplay => Strategies
        .SelectMany(strategy => strategy.Cycles)
        .OrderByDescending(cycle => cycle.CompletedAt)
        .FirstOrDefault() is { } cycle
        ? $"{cycle.CycleId} | {cycle.IntentCount} intent"
        : "No completed strategy cycle";

    public string LiveAuthorizationSummary
    {
        get
        {
            var strategy = SelectedStrategy;
            if (strategy is null)
            {
                return "No strategy selected.";
            }
            var authorization = _services.StrategyStore
                .LoadLiveAuthorizations()
                .FirstOrDefault(item => string.Equals(
                    item.StrategyId,
                    strategy.StrategyId,
                    StringComparison.Ordinal));
            return authorization is null
                ? "No Live authorization is stored."
                : $"Authorization expires {authorization.ExpiresAt:u} | Capital {authorization.MaximumCapital:0} | Allocation {authorization.MaximumStrategyAllocation:P0} | Orders {authorization.MaximumOrderFrequency}/period";
        }
    }

    public bool FixtureMode
    {
        get => _fixtureMode;
        set
        {
            if (!Set(ref _fixtureMode, value))
            {
                return;
            }

            Raise(nameof(FixtureModeStatus));
            PersistSettings();
        }
    }

    public string FixtureModeStatus => FixtureMode
        ? "Fixture mode is ON. No CLI, account, or network is used."
        : "Fixture mode is OFF. Only the selected local CLI may be inspected.";

    public string CliExecutablePath
    {
        get => _cliExecutablePath;
        set
        {
            if (Set(ref _cliExecutablePath, value))
            {
                PersistSettings();
            }
        }
    }

    public string DefaultMarket
    {
        get => _defaultMarket;
        set
        {
            if (Set(ref _defaultMarket, value))
            {
                PersistSettings();
            }
        }
    }

    public string CacheDirectory
    {
        get => _cacheDirectory;
        set
        {
            if (Set(ref _cacheDirectory, value))
            {
                PersistSettings();
            }
        }
    }

    public double ProcessTimeoutSeconds
    {
        get => _processTimeoutSeconds;
        set
        {
            if (!Set(ref _processTimeoutSeconds, Math.Round(value)))
            {
                return;
            }

            Raise(nameof(ProcessTimeoutDisplay));
            PersistSettings();
        }
    }

    public double DataRetentionDays
    {
        get => _dataRetentionDays;
        set
        {
            if (!Set(ref _dataRetentionDays, Math.Round(value)))
            {
                return;
            }

            Raise(nameof(DataRetentionDisplay));
            PersistSettings();
        }
    }

    public double LogRetentionDays
    {
        get => _logRetentionDays;
        set
        {
            if (!Set(ref _logRetentionDays, Math.Round(value)))
            {
                return;
            }

            Raise(nameof(LogRetentionDisplay));
            PersistSettings();
        }
    }

    public string CliVersion
    {
        get => _cliVersion;
        private set => Set(ref _cliVersion, value);
    }

    public LongbridgeStatusState CliStatusState
    {
        get => _cliStatusState;
        private set
        {
            if (Set(ref _cliStatusState, value))
            {
                Raise(nameof(CliStatus));
                Raise(nameof(LongbridgePaperReadiness));
                Raise(nameof(LongbridgePaperAvailable));
                Raise(nameof(LongbridgeAccountStatus));
                if (value != LongbridgeStatusState.ReadyPaper &&
                    SelectedPaperMode == LongbridgePaperMode.LongbridgePaper)
                {
                    SelectedPaperMode = LongbridgePaperMode.LocalPaper;
                    StrategyStatusMessage =
                        "Longbridge Paper became unavailable. Local Paper was restored.";
                }
            }
        }
    }

    public string CliStatus => CliStatusState.ToString();

    public string LastCheckDisplay
    {
        get => _lastCheckDisplay;
        private set => Set(ref _lastCheckDisplay, value);
    }

    public string DataFreshnessDisplay
    {
        get => _dataFreshnessDisplay;
        private set => Set(ref _dataFreshnessDisplay, value);
    }

    public string DataPermissionsSummary
    {
        get => _dataPermissionsSummary;
        private set => Set(ref _dataPermissionsSummary, value);
    }

    public string MarketSession
    {
        get => _marketSession;
        private set => Set(ref _marketSession, value);
    }

    public string CacheSizeDisplay
    {
        get => _cacheSizeDisplay;
        private set => Set(ref _cacheSizeDisplay, value);
    }

    public string CliStatusMessage
    {
        get => _cliStatusMessage;
        private set => Set(ref _cliStatusMessage, value);
    }

    public string CliPathDisplay
    {
        get => _cliPathDisplay;
        private set => Set(ref _cliPathDisplay, value);
    }

    public string LongbridgeEnvironment
    {
        get => _longbridgeEnvironment;
        private set => Set(ref _longbridgeEnvironment, value);
    }

    public string LongbridgeChannel
    {
        get => _longbridgeChannel;
        private set => Set(ref _longbridgeChannel, value);
    }

    public string LongbridgeConnectivity
    {
        get => _longbridgeConnectivity;
        private set => Set(ref _longbridgeConnectivity, value);
    }

    public string LongbridgeFailureCategory
    {
        get => _longbridgeFailureCategory;
        private set => Set(ref _longbridgeFailureCategory, value);
    }

    public string LongbridgeAuthorizationUrl
    {
        get => _longbridgeAuthorizationUrl;
        private set => Set(ref _longbridgeAuthorizationUrl, value);
    }

    public string LongbridgeShortCode
    {
        get => _longbridgeShortCode;
        private set => Set(ref _longbridgeShortCode, value);
    }

    public string LongbridgePaperReadiness =>
        CliStatusState == LongbridgeStatusState.ReadyPaper
            ? "Longbridge Paper ready"
            : "Longbridge Paper blocked";
    public bool LongbridgePaperAvailable =>
        CliStatusState == LongbridgeStatusState.ReadyPaper;

    public string LocalPaperReadiness => "Local Paper ready";

    public string ProcessTimeoutDisplay => $"{ProcessTimeoutSeconds:0} seconds";
    public string DataRetentionDisplay => $"{DataRetentionDays:0} days";
    public string LogRetentionDisplay => $"{LogRetentionDays:0} days";

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

            var value = active.Sum(factor => factor.Coverage * factor.Weight) /
                totalWeight;
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

    public void RegisterThirdPartyStrategy()
    {
        try
        {
            var registration = _services.StrategyRegistry.LoadThirdParty(
                StrategyManifestPath,
                Strategies.Select(strategy => strategy.StrategyId).ToArray());
            _services.StrategyStore.SaveStrategyManifest(
                registration.Manifest);
            var state = DefaultStrategyState(
                registration.Manifest,
                registration.Parameters);
            _services.StrategyStore.SaveStrategyState(state);
            var item = new StrategyItemViewModel(
                registration.Manifest,
                registration.Parameters,
                state);
            Strategies.Add(item);
            SelectedStrategy = item;
            StrategyStatusMessage =
                $"Registered third-party strategy {item.Name}.";
            AppendAudit(
                "ThirdPartyStrategyRegistered",
                new Dictionary<string, string>
                {
                    ["strategy_id"] = item.StrategyId,
                    ["source"] = item.SourceLabel
                },
                AuditEventCategory.StrategyLifecycle);
            RaiseDashboard();
        }
        catch (Exception exception)
        {
            StrategyStatusMessage =
                $"Strategy registration rejected: {SensitiveDataRedactor.Redact(exception.Message)}";
        }
    }

    public async Task StartSelectedStrategyAsync(
        CancellationToken cancellationToken = default)
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        if (strategy.Manifest.Source == StrategySource.Official)
        {
            strategy.RuntimeState = StrategyRuntimeState.Ready;
            StrategyStatusMessage =
                "Official strategy is ready. Run a deterministic Local Paper cycle.";
            SaveStrategy(strategy);
            return;
        }
        if (_externalRuntimes.ContainsKey(strategy.StrategyId))
        {
            StrategyStatusMessage = "The strategy process is already running.";
            return;
        }

        var runtime = new ExternalStrategyRuntime(
            strategy.Manifest,
            _services.StrategyMessageCodec,
            TimeSpan.FromSeconds(30),
            TimeSpan.FromSeconds(5),
            message => System.Windows.Application.Current.Dispatcher.Invoke(
                () => HandleExternalStrategyMessage(strategy, message)),
            entry => System.Windows.Application.Current.Dispatcher.Invoke(
                () => AppendExistingLog(entry)));
        _externalRuntimes[strategy.StrategyId] = runtime;
        var initialize = CreateCoreMessage(
            strategy,
            "runtime-start",
            "initialize",
            new Dictionary<string, string>
            {
                ["mode"] = strategy.Mode.ToString(),
                ["parameter_version"] =
                    strategy.ParameterVersion.ToString(EnglishCulture)
            });
        try
        {
            await runtime.StartAsync(
                initialize,
                cancellationToken);
            strategy.RuntimeState = StrategyRuntimeState.Starting;
            StrategyStatusMessage =
                "Third-party strategy process started with NDJSON transport.";
            SaveStrategy(strategy);
        }
        catch (Exception exception)
        {
            _externalRuntimes.Remove(strategy.StrategyId);
            strategy.RuntimeState = StrategyRuntimeState.Rejected;
            StrategyStatusMessage =
                $"Strategy process rejected: {SensitiveDataRedactor.Redact(exception.Message)}";
            SaveStrategy(strategy);
        }
    }

    public async Task PauseSelectedStrategyAsync(
        CancellationToken cancellationToken = default)
    {
        await SendRuntimeControlAsync(
            "pause",
            StrategyRuntimeState.Paused,
            cancellationToken);
    }

    public async Task ResumeSelectedStrategyAsync(
        CancellationToken cancellationToken = default)
    {
        await SendRuntimeControlAsync(
            "resume",
            StrategyRuntimeState.Running,
            cancellationToken);
    }

    public async Task StopSelectedStrategyAsync(
        CancellationToken cancellationToken = default)
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        if (_externalRuntimes.Remove(
                strategy.StrategyId,
                out var runtime))
        {
            var shutdown = CreateCoreMessage(
                strategy,
                "runtime-stop",
                "shutdown",
                new Dictionary<string, string>
                {
                    ["reason"] = "user_requested_strategy_shutdown"
                });
            await runtime.ShutdownAsync(
                shutdown,
                cancellationToken);
            await runtime.DisposeAsync();
        }
        strategy.RuntimeState = StrategyRuntimeState.Stopped;
        StrategyStatusMessage = "Strategy runtime stopped gracefully.";
        SaveStrategy(strategy);
    }

    public void RunSelectedPaperCycle()
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        if (strategy.Mode != StrategyMode.PaperOnly)
        {
            LatestStrategyAlert =
                "The Local Paper cycle cannot run while Live mode is selected.";
            return;
        }
        if (strategy.Manifest.Source != StrategySource.Official)
        {
            LatestStrategyAlert =
                "Use Start, Pause, Resume, and Stop for third-party processes.";
            return;
        }

        ApplyPendingParameterChanges(strategy);
        var parameterValues = strategy.Parameters.ToDictionary(
            parameter => parameter.Key,
            parameter => parameter.Value,
            StringComparer.Ordinal);
        try
        {
            var result = _services.OfficialStrategyRuntime.RunPaperCycle(
                strategy.Manifest,
                parameterValues);
            strategy.RuntimeState = StrategyRuntimeState.Running;
            strategy.Health = result.Health;
            strategy.LastHeartbeat = result.LastHeartbeat;
            ReplaceCollection(strategy.Signals, result.Signals);
            ReplaceCollection(strategy.Targets, result.Targets);
            ReplaceCollection(strategy.Intents, result.Intents);
            strategy.Cycles.Insert(0, result.Cycle);
            while (strategy.Cycles.Count > 20)
            {
                strategy.Cycles.RemoveAt(strategy.Cycles.Count - 1);
            }
            foreach (var message in result.Messages.Where(message =>
                         message.MessageType == "log"))
            {
                AppendStrategyLog(
                    ParseLogLevel(message.Payload),
                    message.Payload.GetValueOrDefault(
                        "module",
                        "OfficialStrategy"),
                    message.Payload.GetValueOrDefault(
                        "message",
                        "Strategy log event."),
                    strategy.StrategyId,
                    message.CorrelationId,
                    message.CycleId,
                    new Dictionary<string, string>
                    {
                        ["message_type"] = message.MessageType,
                        ["mode"] = StrategyMode.PaperOnly.ToString()
                    });
            }
            SaveStrategy(strategy);
            StrategyStatusMessage =
                "Deterministic Local Paper cycle completed through the NDJSON protocol and execution gateway.";
            LatestStrategyAlert =
                "Local Paper intents were risk-checked, filled, allocated, and reconciled without invoking Longbridge CLI.";
            ProcessOfficialLocalPaperIntents(strategy, result.Intents);
            AppendAudit(
                "PaperStrategyCycleCompleted",
                new Dictionary<string, string>
                {
                    ["strategy_id"] = strategy.StrategyId,
                    ["cycle_id"] = result.Cycle.CycleId,
                    ["intent_count"] =
                        result.Intents.Count.ToString(EnglishCulture),
                    ["live_submission_attempts"] =
                        _services.LiveBrokerAdapter.SubmissionAttempts
                            .ToString(EnglishCulture)
                },
                AuditEventCategory.StrategyLifecycle);
            RaiseDashboard();
        }
        catch (Exception exception)
        {
            strategy.RuntimeState = StrategyRuntimeState.Rejected;
            strategy.Health = HealthState.Unhealthy;
            strategy.BlocksNewRisk = true;
            LatestStrategyAlert =
                $"Local Paper cycle rejected: {SensitiveDataRedactor.Redact(exception.Message)}";
            SaveStrategy(strategy);
        }
    }

    public void RunReconciliationDiagnostic()
    {
        var brokerPositions = _executionState.LedgerPositions
            .GroupBy(position => position.Symbol, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Sum(position => position.VirtualQuantity),
                StringComparer.Ordinal);
        var result = _services.Reconciliation.Reconcile(
            _executionState.LedgerPositions,
            brokerPositions,
            "diagnostic-local-paper",
            DateTimeOffset.UtcNow);
        var mismatchCount = result.Events.Count(item =>
            item.Status == ReconciliationStatus.Mismatch);
        LatestStrategyAlert = mismatchCount == 0
            ? "Local Paper reconciliation diagnostic passed without trading."
            : $"Reconciliation diagnostic found {mismatchCount} mismatch(es).";
        AppendAudit(
            "LocalPaperReconciliationDiagnostic",
            new Dictionary<string, string>
            {
                ["mismatch_count"] =
                    mismatchCount.ToString(EnglishCulture),
                ["trading_action"] = "false"
            },
            AuditEventCategory.Reconciliation);
    }

    public void ApplyParameterChange(StrategyParameterViewModel parameter)
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        var decision = _services.ParameterGovernance.RequestChange(
            strategy.StrategyId,
            parameter.Definition,
            parameter.Value,
            parameter.DraftValue,
            strategy.ParameterVersion,
            "local-user",
            parameter.ConfirmationChecked,
            DateTimeOffset.UtcNow);
        _services.StrategyStore.AppendParameterChange(decision.Change);
        if (parameter.ConfirmationChecked)
        {
            foreach (var pendingPreview in strategy.ParameterChanges
                         .Where(change =>
                             change.ParameterKey == parameter.Key &&
                             change.Result ==
                                ParameterChangeResult.PendingConfirmation)
                         .ToArray())
            {
                strategy.ParameterChanges.Remove(pendingPreview);
            }
        }
        strategy.ParameterChanges.Insert(0, decision.Change);
        parameter.PreviewText = decision.ImpactPreview;
        parameter.Status = decision.Change.Result.ToString();
        strategy.BlocksNewRisk = decision.BlocksNewRisk;
        if (decision.Change.Result == ParameterChangeResult.Applied)
        {
            parameter.Value = decision.Change.NewValue;
            strategy.ParameterVersion = decision.Change.ParameterVersion;
        }
        else if (decision.Change.Result ==
                 ParameterChangeResult.PendingSafeBoundary)
        {
            strategy.RuntimeState = StrategyRuntimeState.Paused;
        }
        parameter.ConfirmationChecked = false;
        SaveStrategy(strategy);
        AppendAudit(
            "StrategyParameterChange",
            new Dictionary<string, string>
            {
                ["change_id"] = decision.Change.ChangeId,
                ["strategy_id"] = decision.Change.StrategyId,
                ["parameter_key"] = decision.Change.ParameterKey,
                ["old_value"] = decision.Change.OldValue,
                ["new_value"] = decision.Change.NewValue,
                ["requested_at"] = decision.Change.RequestedAt.ToString("O"),
                ["effective_at"] =
                    decision.Change.EffectiveAt?.ToString("O") ?? "",
                ["requested_by"] = decision.Change.RequestedBy,
                ["risk_tier"] = decision.Change.RiskTier.ToString(),
                ["parameter_version"] =
                    decision.Change.ParameterVersion.ToString(EnglishCulture),
                ["activation_mode"] =
                    decision.Change.ActivationMode.ToString(),
                ["result"] = decision.Change.Result.ToString(),
                ["rollback_version"] =
                    decision.Change.RollbackVersion.ToString(EnglishCulture)
            },
            AuditEventCategory.Settings);
    }

    public void RequestLiveMode()
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        var authorization = _services.StrategyStore
            .LoadLiveAuthorizations()
            .FirstOrDefault(item => string.Equals(
                item.StrategyId,
                strategy.StrategyId,
                StringComparison.Ordinal));
        var result = _services.StrategyModeService.SelectMode(
            StrategyMode.Live,
            GlobalLiveLock,
            strategy.Manifest,
            strategy.ParameterVersion,
            authorization,
            DefaultMarket,
            DateTimeOffset.UtcNow);
        strategy.Mode = result.Mode;
        StrategyStatusMessage = result.Message;
        LatestStrategyAlert = result.Accepted
            ? "Live selected, but the Longbridge adapter remains intentionally rejecting."
            : result.Message;
        SaveStrategy(strategy);
        AppendModeAudit(strategy, result);
        RaiseDashboard();
    }

    public void RequestPaperMode()
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        SelectedPaperMode = LongbridgePaperMode.LocalPaper;
        var wasLive = strategy.Mode == StrategyMode.Live;
        var result = _services.StrategyModeService.SelectMode(
            StrategyMode.PaperOnly,
            GlobalLiveLock,
            strategy.Manifest,
            strategy.ParameterVersion,
            null,
            DefaultMarket,
            DateTimeOffset.UtcNow);
        strategy.Mode = StrategyMode.PaperOnly;
        strategy.LiveToPaperTransition = SelectedTransition;
        strategy.BlocksNewRisk = true;
        if (SelectedTransition == LiveToPaperTransition.Freeze)
        {
            strategy.RuntimeState = StrategyRuntimeState.Paused;
        }
        StrategyStatusMessage = result.Message;
        LatestStrategyAlert = SelectedTransition switch
        {
            LiveToPaperTransition.StopOpeningRisk =>
                "Local Paper: new risk is blocked while existing virtual positions remain manageable.",
            LiveToPaperTransition.Freeze =>
                "Local Paper: the strategy is frozen and no order was generated.",
            LiveToPaperTransition.ControlledExit =>
                "Local Paper: controlled exit policy is ready.",
            _ => result.Message
        };
        if (wasLive &&
            SelectedTransition ==
                LiveToPaperTransition.ControlledExit)
        {
            RunControlledLocalPaperExit(strategy);
        }
        SaveStrategy(strategy);
        AppendModeAudit(strategy, result);
        RaiseDashboard();
    }

    public void RequestLongbridgePaperMode()
    {
        var strategy = SelectedStrategy;
        if (strategy is null)
        {
            return;
        }
        if (!LongbridgePaperPolicy.CanRun(
                LongbridgePaperMode.LongbridgePaper,
                CliStatusState))
        {
            StrategyStatusMessage =
                "Longbridge Paper requires an authenticated ReadyPaper account.";
            return;
        }

        SelectedPaperMode = LongbridgePaperMode.LongbridgePaper;
        strategy.Mode = StrategyMode.PaperOnly;
        StrategyStatusMessage = "Longbridge Paper selected.";
        LatestStrategyAlert =
            "Longbridge Paper is selected. Unverified broker submission remains blocked.";
        SaveStrategy(strategy);
        RaiseDashboard();
    }

    public async Task RefreshLongbridgeAsync(CancellationToken cancellationToken = default)
    {
        if (FixtureMode)
        {
            RefreshFixtureData();
            return;
        }

        UniverseEntries.Clear();
        DataFreshnessDisplay = "No market snapshot";
        var timeout = TimeSpan.FromSeconds(
            Math.Clamp(ProcessTimeoutSeconds, 2, 120));
        try
        {
            var connection = await _services.LongbridgeAuthentication.CheckAsync(
                CliExecutablePath,
                timeout,
                cancellationToken);
            ApplyConnectionState(connection);

            AppendLog(
                IsReadyState(connection.Status)
                    ? ApplicationLogLevel.Info
                    : ApplicationLogLevel.Warning,
                "LongbridgeCLI",
                $"Authentication and capability check completed with state {connection.Status}.",
                new Dictionary<string, string>
                {
                    ["call_category"] = CliCallCategory.ReadOnlyData.ToString(),
                    ["state"] = connection.Status.ToString(),
                    ["exit_output_logged"] = "false"
                });

            if (!IsReadyState(connection.Status))
            {
                return;
            }

            var inspection = await _services.CliAdapter.InspectAsync(
                CliExecutablePath,
                timeout,
                cancellationToken);
            if (inspection.Capabilities is null)
            {
                return;
            }
            await RefreshRealMarketDataAsync(
                inspection,
                timeout,
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            CliStatusState = LongbridgeStatusState.Degraded;
            CliStatusMessage = "The read-only CLI check was cancelled.";
            AppendLog(
                ApplicationLogLevel.Warning,
                "LongbridgeCLI",
                "Read-only capability check was cancelled.",
                SafeCliContext("Cancelled"));
        }
        catch
        {
            CliStatusState = LongbridgeStatusState.Degraded;
            CliStatusMessage =
                "The local CLI returned unsupported or invalid read-only data.";
            AppendLog(
                ApplicationLogLevel.Error,
                "LongbridgeCLI",
                "Read-only market refresh failed without logging raw CLI output.",
                SafeCliContext("Failed"));
        }
    }

    public async Task SignInLongbridgeAsync()
    {
        _longbridgeSignInCancellation?.Cancel();
        _longbridgeSignInCancellation?.Dispose();
        _longbridgeSignInCancellation = new CancellationTokenSource();
        CliStatusState = LongbridgeStatusState.Authorizing;
        CliStatusMessage =
            "Waiting for Longbridge device authorization. Local Paper remains available.";
        var state = await _services.LongbridgeAuthentication.SignInAsync(
            CliExecutablePath,
            TimeSpan.FromMinutes(5),
            _longbridgeSignInCancellation.Token);
        ApplyConnectionState(state);
    }

    public async Task SignInLongbridgeWithCodeAsync(string authorizationCode)
    {
        _longbridgeSignInCancellation?.Cancel();
        _longbridgeSignInCancellation?.Dispose();
        _longbridgeSignInCancellation = new CancellationTokenSource();
        CliStatusState = LongbridgeStatusState.Authorizing;
        CliStatusMessage =
            "Checking the one-time authorization code in memory.";
        var state = await _services.LongbridgeAuthentication
            .SignInWithAuthorizationCodeAsync(
                CliExecutablePath,
                authorizationCode,
                TimeSpan.FromMinutes(5),
                _longbridgeSignInCancellation.Token);
        ApplyConnectionState(state);
    }

    public void CancelLongbridgeSignIn()
    {
        _longbridgeSignInCancellation?.Cancel();
        CliStatusMessage =
            "Longbridge sign-in cancellation was requested. Local Paper remains available.";
    }

    public async Task SignOutLongbridgeAsync()
    {
        var state = await _services.LongbridgeAuthentication.SignOutAsync(
            CliExecutablePath,
            TimeSpan.FromSeconds(Math.Clamp(ProcessTimeoutSeconds, 2, 120)),
            CancellationToken.None);
        ApplyConnectionState(state);
    }

    public async Task UpdateLongbridgeAsync()
    {
        var state = await _services.LongbridgeAuthentication.UpdateAsync(
            CliExecutablePath,
            TimeSpan.FromMinutes(5),
            CancellationToken.None);
        ApplyConnectionState(state);
    }

    public void RunTinyFactorSearch()
    {
        if (_researchDataset is null)
        {
            CandidateSearchStatus =
                "Research data is unavailable; no candidate was evaluated.";
            return;
        }
        try
        {
            var definitions = _services.FactorResearchStore
                .LoadFactorDefinitions();
            var result = _services.FactorSearch.RunTinySearch(
                _researchDataset,
                definitions,
                FactorSearchConfiguration.Tiny);
            ReplaceResearchFactors(result.Summaries);
            RecentFactorTrials.Clear();
            foreach (var trial in result.Trials
                         .OrderByDescending(item => item.CreatedAt)
                         .Take(50))
            {
                RecentFactorTrials.Add(trial);
            }
            CandidateSearchStatus = result.Status;
            AppendAudit(
                "TinyFactorBeamSearchCompleted",
                new Dictionary<string, string>
                {
                    ["dataset_version"] =
                        _researchDataset.DatasetVersion,
                    ["universe_version"] =
                        _researchDataset.UniverseVersion,
                    ["evaluated_count"] =
                        result.EvaluatedCount.ToString(EnglishCulture),
                    ["candidate_count"] =
                        result.CandidateCount.ToString(EnglishCulture),
                    ["rejected_count"] =
                        result.RejectedCount.ToString(EnglishCulture),
                    ["quarantined_count"] =
                        result.QuarantinedCount.ToString(EnglishCulture),
                    ["search_algorithm"] =
                        "deterministic-constrained-beam-v1"
                },
                AuditEventCategory.FactorLifecycle);
        }
        catch (Exception exception)
        {
            CandidateSearchStatus =
                $"Tiny search failed closed: {SensitiveDataRedactor.Redact(exception.Message)}";
        }
    }

    public void RunReview()
    {
        _reviewCount += 1;
        LastReviewLabel =
            $"Last review {DateTime.Now.ToString("t", EnglishCulture)}";
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
        if (FixtureMode)
        {
            RefreshFixtureData();
        }
        AppendAudit(
            "FixtureStateReset",
            new Dictionary<string, string> { ["fixture_mode"] = "true" });
    }

    private void RefreshFixtureData()
    {
        try
        {
            var snapshot = _services.FixtureDataService.LoadFixtureSnapshot();
            CliStatusState = snapshot.Capabilities.StatusState;
            CliVersion = snapshot.Capabilities.CliVersion;
            CliPathDisplay = "Fixture mode (no executable)";
            LastCheckDisplay = snapshot.Authorization.CheckedAt
                .ToLocalTime()
                .ToString("g", EnglishCulture);
            DataFreshnessDisplay =
                $"Available {snapshot.CurrentSnapshot.AvailableTime.ToLocalTime():g}";
            DataPermissionsSummary = string.Join(
                ", ",
                snapshot.Authorization.Permissions);
            MarketSession = snapshot.MarketStatus.Session;
            CliStatusMessage = snapshot.Capabilities.Message;
            ReplaceUniverse(snapshot.Universe.Entries);
            UpdateCacheSize();
            AppendLog(
                ApplicationLogLevel.Info,
                "LongbridgeFixture",
                "Loaded deterministic read-only market and universe fixtures.",
                SafeCliContext("Ready"));
        }
        catch
        {
            CliStatusState = LongbridgeStatusState.Degraded;
            CliStatusMessage = "Fixture market data could not be loaded.";
            AppendLog(
                ApplicationLogLevel.Error,
                "LongbridgeFixture",
                "Fixture market-data refresh failed.",
                SafeCliContext("Failed"));
        }
    }

    private void ApplyConnectionState(LongbridgeConnectionState state)
    {
        CliStatusState = state.Status;
        CliVersion = state.CliVersion;
        CliPathDisplay = string.IsNullOrWhiteSpace(state.ExecutablePath)
            ? "System PATH lookup did not resolve an executable"
            : state.ExecutablePath;
        LastCheckDisplay = state.CheckedAt
            .ToLocalTime()
            .ToString("g", EnglishCulture);
        DataPermissionsSummary = state.PermissionsSummary.Count == 0
            ? "No advertised market-data permissions"
            : string.Join(", ", state.PermissionsSummary);
        LongbridgeEnvironment = state.AccountEnvironment;
        LongbridgeChannel = state.AccountChannel;
        LongbridgeConnectivity = state.ConnectivityReady
            ? "Ready"
            : "Unavailable";
        LongbridgeFailureCategory = string.IsNullOrWhiteSpace(state.FailureCategory)
            ? "None"
            : state.FailureCategory;
        LongbridgeAuthorizationUrl = state.AuthorizationUrl;
        LongbridgeShortCode = state.ShortCode;
        CliStatusMessage = state.Message;
    }

    private void ApplyAuthenticationProgress(
        LongbridgeAuthenticationProgress progress)
    {
        CliStatusState = progress.Status;
        LongbridgeAuthorizationUrl = progress.AuthorizationUrl;
        LongbridgeShortCode = progress.ShortCode;
        CliStatusMessage = progress.Message;
    }

    private static bool IsReadyState(LongbridgeStatusState state) =>
        state is LongbridgeStatusState.ReadyPaper or
            LongbridgeStatusState.ReadyLive or
            LongbridgeStatusState.ReadyUnknownChannel;

    private async Task RefreshRealMarketDataAsync(
        LongbridgeInspection inspection,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var capabilities = inspection.Capabilities
            ?? throw new InvalidOperationException("Capabilities are required.");
        var required = new[]
        {
            LongbridgeOperation.SecurityList,
            LongbridgeOperation.CurrentSnapshot,
            LongbridgeOperation.HistoricalBars
        };
        if (required.Any(operation => capabilities.Commands.All(
                command => command.Operation != operation)))
        {
            CliStatusState = LongbridgeStatusState.Degraded;
            CliStatusMessage =
                "The installed CLI does not advertise every required market-data command.";
            return;
        }

        var securities = await _services.MarketDataClient.FetchSecurityListAsync(
            inspection.ExecutablePath,
            capabilities,
            DefaultMarket,
            timeout,
            cancellationToken);
        var reference = securities.Securities.FirstOrDefault()
            ?? throw new InvalidOperationException(
                "The security list contains no symbols.");
        var end = DateTimeOffset.UtcNow;
        var start = end.AddDays(-30);
        var bars = await _services.MarketDataClient.FetchHistoricalBarsAsync(
            inspection.ExecutablePath,
            capabilities,
            reference.Symbol,
            "Daily",
            start,
            end,
            timeout,
            cancellationToken);
        var current =
            await _services.MarketDataClient.FetchCurrentSnapshotAsync(
                inspection.ExecutablePath,
                capabilities,
                reference.Symbol,
                timeout,
                cancellationToken);
        var positions = capabilities.Commands.Any(command =>
                command.Operation == LongbridgeOperation.BrokerPositions)
            ? await _services.MarketDataClient.FetchBrokerPositionsAsync(
                inspection.ExecutablePath,
                capabilities,
                timeout,
                cancellationToken)
            : new BrokerPositionSnapshot(
                1,
                DateTimeOffset.UtcNow,
                capabilities.SourceVersion,
                string.Empty,
                Array.Empty<BrokerPosition>());
        var configuration = new UniverseConfiguration(
            1,
            DefaultMarket,
            5,
            1000000,
            252,
            252,
            "universe-rules-1.1.0");
        var universe = _services.UniverseService.BuildDailySnapshot(
            DateTimeOffset.UtcNow,
            configuration,
            securities,
            positions);

        _services.MarketDataCache.StoreHistoricalBars(bars);
        _services.MarketDataCache.StoreCurrentSnapshot(current);
        _services.MarketDataCache.StoreUniverseSnapshot(universe);
        ReplaceUniverse(universe.Entries);
        DataFreshnessDisplay =
            $"Available {current.AvailableTime.ToLocalTime():g}";
        MarketSession = "Provided by quote availability";
        UpdateCacheSize();
        CliStatusMessage =
            "Read-only market data and the daily universe were refreshed.";
        AppendLog(
            ApplicationLogLevel.Info,
            "LongbridgeCLI",
            "Read-only market data and universe refresh completed.",
            SafeCliContext("Ready"));
    }

    private void ReplaceUniverse(IEnumerable<UniverseEntry> entries)
    {
        UniverseEntries.Clear();
        foreach (var entry in entries)
        {
            UniverseEntries.Add(entry);
        }
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

    private void UpdateCacheSize()
    {
        var bytes = _services.MarketDataCache.CacheSizeBytes();
        CacheSizeDisplay = bytes < 1024
            ? $"{bytes} bytes"
            : $"{bytes / 1024.0:0.0} KB";
    }

    private void PersistSettings()
    {
        try
        {
            _services.SettingsStore.SaveSettings(new AppSettings(
                FixtureMode,
                StrategyMode.PaperOnly,
                HealthState.Degraded,
                RiskBudget,
                CoverageGate,
                MaxFactorWeight)
            {
                CliExecutablePath = CliExecutablePath,
                DefaultMarket = DefaultMarket,
                CacheDirectory = CacheDirectory,
                ProcessTimeoutSeconds = (int)ProcessTimeoutSeconds,
                DataRetentionDays = (int)DataRetentionDays,
                LogRetentionDays = (int)LogRetentionDays,
                GlobalLiveLock = GlobalLiveLock,
                PythonExecutablePath = PythonExecutablePath,
                QuantWorkerRootDirectory = QuantWorkerRootDirectory,
                ComputeSchedulingMode = ComputeSchedulingMode,
                AgentCallLimit = _agentCallLimit,
                AgentInputTokenLimit = _agentInputTokenLimit,
                AgentOutputTokenLimit = _agentOutputTokenLimit,
                AgentDailySpendingLimit = _agentDailySpendingLimit,
                AgentMonthlySpendingLimit = _agentMonthlySpendingLimit
            });
        }
        catch
        {
            AppendLog(
                ApplicationLogLevel.Error,
                "Persistence",
                "Failed to save non-sensitive settings",
                new Dictionary<string, string>());
        }
    }

    private void AppendLog(
        ApplicationLogLevel level,
        string module,
        string message,
        IReadOnlyDictionary<string, string> context)
    {
        var safeMessage = SensitiveDataRedactor.Redact(message);
        var safeContext = context.ToDictionary(
            pair => pair.Key,
            pair => SensitiveDataRedactor.Redact(pair.Value),
            StringComparer.Ordinal);
        var entry = new ApplicationLogEntry(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            level,
            module,
            safeMessage,
            null,
            safeContext);
        try
        {
            _services.LogStore.AppendLog(entry);
        }
        catch
        {
        }

        ApplicationLogs.Add(entry);
        while (ApplicationLogs.Count > 100)
        {
            ApplicationLogs.RemoveAt(0);
        }
        Raise(nameof(FilteredApplicationLogs));
    }

    private void AppendStrategyLog(
        ApplicationLogLevel level,
        string module,
        string message,
        string strategyId,
        string? correlationId,
        string? cycleId,
        IReadOnlyDictionary<string, string> context)
    {
        var safeContext = context.ToDictionary(
            pair => pair.Key,
            pair => SensitiveDataRedactor.Redact(pair.Value),
            StringComparer.Ordinal);
        AppendExistingLog(new ApplicationLogEntry(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            level,
            module,
            SensitiveDataRedactor.Redact(message),
            correlationId,
            safeContext)
        {
            StrategyId = strategyId,
            CycleId = cycleId
        });
    }

    private void AppendExistingLog(ApplicationLogEntry entry)
    {
        try
        {
            _services.LogStore.AppendLog(entry);
        }
        catch
        {
        }
        ApplicationLogs.Add(entry);
        while (ApplicationLogs.Count > 100)
        {
            ApplicationLogs.RemoveAt(0);
        }
        Raise(nameof(FilteredApplicationLogs));
    }

    private static IReadOnlyDictionary<string, string> SafeCliContext(string state)
    {
        return new Dictionary<string, string>
        {
            ["call_category"] = CliCallCategory.ReadOnlyData.ToString(),
            ["state"] = state,
            ["raw_authentication_output_logged"] = "false"
        };
    }

    private void AppendAudit(
        string action,
        IReadOnlyDictionary<string, string> context,
        AuditEventCategory category = AuditEventCategory.FactorLifecycle)
    {
        _services.AuditStore.AppendAuditEvent(new AuditEvent(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            category,
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

    private void InitializeStrategies()
    {
        var manifests = _services.StrategyStore.LoadStrategyManifests()
            .ToDictionary(
                manifest => manifest.StrategyId,
                StringComparer.Ordinal);
        var states = _services.StrategyStore.LoadStrategyStates()
            .ToDictionary(
                state => state.StrategyId,
                StringComparer.Ordinal);
        var official = _services.StrategyRegistry.LoadOfficial();
        manifests[official.Manifest.StrategyId] = official.Manifest;
        if (!states.TryGetValue(
                official.Manifest.StrategyId,
                out var officialState))
        {
            officialState = DefaultStrategyState(
                official.Manifest,
                official.Parameters);
            _services.StrategyStore.SaveStrategyState(officialState);
        }
        _services.StrategyStore.SaveStrategyManifest(official.Manifest);
        if (_services.StrategyStore.LoadLiveAuthorizations().Count == 0)
        {
            _services.StrategyStore.SaveLiveAuthorization(
                _services.StrategyRegistry.LoadAuthorizationFixture(
                    "valid-live-authorization.json"));
        }
        var officialItem = new StrategyItemViewModel(
            official.Manifest,
            official.Parameters,
            officialState);
        LoadParameterHistory(officialItem);
        Strategies.Add(officialItem);

        foreach (var manifest in manifests.Values
                     .Where(manifest =>
                         manifest.Source == StrategySource.ThirdParty)
                     .OrderBy(manifest => manifest.Name, StringComparer.Ordinal))
        {
            try
            {
                if (!File.Exists(manifest.ParameterSchema))
                {
                    continue;
                }
                var parameters = JsonSerializer.Deserialize<StrategyParameterSchema>(
                    File.ReadAllText(manifest.ParameterSchema),
                    StrategyJsonOptions());
                if (parameters is null)
                {
                    continue;
                }
                var validation = _services.StrategyRegistry.Validate(
                    manifest,
                    parameters,
                    Strategies.Select(item => item.StrategyId).ToArray(),
                    Path.GetDirectoryName(manifest.ParameterSchema));
                if (!validation.IsValid)
                {
                    continue;
                }
                var state = states.TryGetValue(
                    manifest.StrategyId,
                    out var stored)
                    ? stored
                    : DefaultStrategyState(manifest, parameters);
                var item = new StrategyItemViewModel(
                    manifest,
                    parameters,
                    state);
                LoadParameterHistory(item);
                Strategies.Add(item);
            }
            catch
            {
            }
        }
        SelectedStrategy = Strategies.FirstOrDefault();
        RaiseDashboard();
    }

    private void InitializeExecution()
    {
        try
        {
            _executionState = _services.ExecutionStore.LoadExecutionState();
            if (_executionState.Intents.Count == 0 &&
                _executionState.LedgerPositions.Count == 0)
            {
                var fixture =
                    _services.ExecutionFixtures.LoadPaperGatewayFixture();
                var seeded = ExecutionStateSnapshot.Empty with
                {
                    LedgerPositions = fixture.StartingLedger
                        .Select(item => new VirtualLedgerPosition(
                            1,
                            item.StrategyId,
                            fixture.Symbol,
                            item.VirtualQuantity,
                            item.VirtualQuantity,
                            item.CostBasis,
                            0,
                            (fixture.ReferencePrice - item.CostBasis) *
                                item.VirtualQuantity,
                            item.VirtualQuantity * fixture.ReferencePrice,
                            0,
                            Array.Empty<string>(),
                            Array.Empty<string>(),
                            Array.Empty<string>(),
                            fixture.AsOf))
                        .ToArray()
                };
                _services.ExecutionStore.SaveExecutionState(seeded);
                var contexts = fixture.Intents
                    .Select(intent => intent.StrategyId)
                    .Distinct(StringComparer.Ordinal)
                    .ToDictionary(
                        strategyId => strategyId,
                        _ => LocalPaperContext(
                            fixture.Market,
                            fixture.AsOf,
                            1_000_000m,
                            1),
                        StringComparer.Ordinal);
                var result = _services.ExecutionGateway.Process(
                    fixture.Intents,
                    contexts,
                    fixture.ReferencePrice,
                    fixture.ReferencePriceSource,
                    new PaperBrokerConfiguration(
                        fixture.PaperFillRatio,
                        2,
                        0.005m,
                        0.25m,
                        false,
                        false),
                    RejectingLiveConfiguration(),
                    new Dictionary<string, decimal>(
                        StringComparer.Ordinal)
                    {
                        [fixture.Symbol] =
                            fixture.StartingBrokerQuantity
                    });
                _executionState = result.State;
            }
            RaiseExecution();
        }
        catch (Exception exception)
        {
            LatestStrategyAlert =
                "Local Paper fixture initialization failed safely: " +
                SensitiveDataRedactor.Redact(exception.Message);
        }
    }

    private void ProcessOfficialLocalPaperIntents(
        StrategyItemViewModel strategy,
        IReadOnlyList<StrategyIntentRecord> records)
    {
        if (records.Count == 0)
        {
            return;
        }
        var fixture = _services.ExecutionFixtures.LoadPaperGatewayFixture();
        var capitalBudget = Math.Max(
            (decimal)strategy.CapitalBudget,
            100_000m);
        var existingBySymbol = _executionState.LedgerPositions
            .Where(position =>
                position.StrategyId == strategy.StrategyId)
            .ToDictionary(
                position => position.Symbol,
                position => position.VirtualQuantity,
                StringComparer.Ordinal);
        var intents = records.Select(record =>
        {
            var desiredQuantity =
                capitalBudget *
                (decimal)record.TargetWeight /
                fixture.ReferencePrice;
            var requestedQuantity = desiredQuantity -
                existingBySymbol.GetValueOrDefault(record.Symbol);
            return new TradeIntent(
                1,
                record.IntentId,
                strategy.StrategyId,
                strategy.Manifest.Version,
                record.CycleId,
                $"{DefaultMarket}-{record.Timestamp:yyyy-MM-dd}",
                record.Symbol,
                Math.Round(requestedQuantity, 4),
                record.Priority,
                record.AllowPartial,
                0.0001m,
                60,
                record.ReasonCode,
                strategy.ParameterVersion,
                record.Timestamp);
        })
        .Where(intent => intent.AbsoluteQuantity > 0.0001m)
        .ToArray();
        if (intents.Length == 0)
        {
            return;
        }
        var now = DateTimeOffset.UtcNow;
        var contexts = new Dictionary<string, ExecutionGatewayContext>(
            StringComparer.Ordinal)
        {
            [strategy.StrategyId] = LocalPaperContext(
                DefaultMarket,
                now,
                capitalBudget,
                strategy.ParameterVersion,
                strategy.BlocksNewRisk,
                strategy.LiveToPaperTransition)
        };
        var brokerPositions = _executionState.LedgerPositions
            .GroupBy(position => position.Symbol, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Sum(position => position.VirtualQuantity),
                StringComparer.Ordinal);
        var gatewayResult = _services.ExecutionGateway.Process(
            intents,
            contexts,
            fixture.ReferencePrice,
            fixture.ReferencePriceSource,
            new PaperBrokerConfiguration(
                1,
                2,
                0.005m,
                0.25m,
                false,
                false),
            RejectingLiveConfiguration(),
            brokerPositions);
        _executionState = gatewayResult.State;
        RaiseExecution();
    }

    private static ExecutionGatewayContext LocalPaperContext(
        string market,
        DateTimeOffset now,
        decimal capitalBudget,
        int parameterVersion,
        bool transitionActive = false,
        LiveToPaperTransition transitionPolicy =
            LiveToPaperTransition.StopOpeningRisk)
    {
        return new ExecutionGatewayContext(
            StrategyMode.PaperOnly,
            false,
            null,
            true,
            true,
            HealthState.Healthy,
            capitalBudget,
            capitalBudget,
            false,
            false,
            true,
            parameterVersion,
            market,
            now,
            TransitionActive: transitionActive,
            TransitionPolicy: transitionPolicy);
    }

    private void RunControlledLocalPaperExit(
        StrategyItemViewModel strategy)
    {
        var positions = _executionState.LedgerPositions
            .Where(item =>
                item.StrategyId == strategy.StrategyId &&
                item.VirtualQuantity != 0)
            .ToArray();
        if (positions.Length == 0)
        {
            LatestStrategyAlert =
                "Local Paper controlled exit completed with no virtual position to close.";
            return;
        }
        var fixture = _services.ExecutionFixtures
            .LoadPaperGatewayFixture();
        var now = DateTimeOffset.UtcNow;
        var cycleId =
            $"local-paper-controlled-exit-{now.ToUnixTimeMilliseconds()}";
        var intents = positions.Select((position, index) =>
            new TradeIntent(
                1,
                $"{cycleId}-{index + 1}",
                strategy.StrategyId,
                strategy.Manifest.Version,
                cycleId,
                $"{DefaultMarket}-{now:yyyy-MM-dd}",
                position.Symbol,
                -position.VirtualQuantity,
                int.MaxValue - index,
                false,
                Math.Abs(position.VirtualQuantity),
                60,
                "live_to_local_paper_controlled_exit",
                strategy.ParameterVersion,
                now))
            .ToArray();
        var brokerPositions = _executionState.LedgerPositions
            .GroupBy(item => item.Symbol, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Sum(item => item.VirtualQuantity),
                StringComparer.Ordinal);
        var exposure = positions.Sum(item =>
            Math.Abs(item.VirtualQuantity) *
            fixture.ReferencePrice);
        var result = _services.ExecutionGateway.Process(
            intents,
            new Dictionary<string, ExecutionGatewayContext>(
                StringComparer.Ordinal)
            {
                [strategy.StrategyId] = LocalPaperContext(
                    DefaultMarket,
                    now,
                    Math.Max(exposure, 1m),
                    strategy.ParameterVersion,
                    true,
                    LiveToPaperTransition.ControlledExit)
            },
            fixture.ReferencePrice,
            fixture.ReferencePriceSource,
            new PaperBrokerConfiguration(
                1,
                2,
                0.005m,
                0.25m,
                false,
                false),
            RejectingLiveConfiguration(),
            brokerPositions);
        _executionState = result.State;
        LatestStrategyAlert =
            "Local Paper controlled exit generated policy intents, simulated fills, and reconciled the virtual ledger. No real order was sent.";
        RaiseExecution();
    }

    private LiveAdapterConfiguration RejectingLiveConfiguration()
    {
        return new LiveAdapterConfiguration(
            false,
            true,
            string.Empty,
            TimeSpan.FromSeconds(5),
            _services.ExecutionFixtures.LoadExecutionCapability());
    }

    private void InitializeResearch()
    {
        try
        {
            var source = _services.FixtureDataService
                .LoadFixtureSnapshot();
            _researchDataset = _services.ResearchFixtures
                .BuildDataset(source);
            var definitions = _services.FactorResearchStore
                .LoadFactorDefinitions();
            if (definitions.Count == 0)
            {
                definitions = _services.ResearchFixtures
                    .LoadFactorDefinitions();
                _services.FactorResearchStore
                    .SaveFactorDefinitions(definitions);
            }
            var trials = _services.FactorResearchStore
                .LoadFactorTrials(200);
            ReplaceResearchFactors(
                FactorSearchService.InitialSummaries(
                    definitions,
                    trials));
            RecentFactorTrials.Clear();
            foreach (var trial in trials
                         .OrderByDescending(item => item.CreatedAt)
                         .Take(50))
            {
                RecentFactorTrials.Add(trial);
            }

            var fixture = _services.ResearchFixtures
                .LoadRegimeAllocationFixture();
            _regimeSnapshot = _services.RegimeEngine.Evaluate(
                fixture.RegimeInput,
                _researchDataset.CreatedAt);
            _capitalAllocation = _services.CapitalAllocator.Allocate(
                fixture.TotalCapital,
                fixture.BaseRiskFraction,
                _regimeSnapshot,
                fixture.Strategies);
            ApplyCapitalAllocations(_capitalAllocation);
            CandidateSearchStatus = trials.Count == 0
                ? "Ready for a tiny deterministic beam search."
                : $"Loaded {trials.Count} retained factor trials.";
            RaiseResearchSummary();
        }
        catch (Exception exception)
        {
            CandidateSearchStatus =
                $"Research foundation is degraded: {SensitiveDataRedactor.Redact(exception.Message)}";
        }
    }

    private void ApplyCapitalAllocations(
        CapitalAllocationResult result)
    {
        foreach (var allocation in result.Allocations)
        {
            var strategy = Strategies.FirstOrDefault(item =>
                string.Equals(
                    item.StrategyId,
                    allocation.StrategyId,
                    StringComparison.Ordinal));
            if (strategy is null)
            {
                continue;
            }
            strategy.CapitalBudget = allocation.CapitalBudget;
            strategy.AllocationExplanation =
                allocation.ExplanationText;
        }
    }

    private void ReplaceResearchFactors(
        IEnumerable<FactorResearchSummary> summaries)
    {
        ResearchFactors.Clear();
        foreach (var summary in summaries)
        {
            ResearchFactors.Add(summary);
        }
    }

    private void RaiseResearchSummary()
    {
        Raise(nameof(TrendProbability));
        Raise(nameof(RangeProbability));
        Raise(nameof(HighVolatilityProbability));
        Raise(nameof(CrisisProbability));
        Raise(nameof(RegimeUncertainty));
        Raise(nameof(PortfolioRiskDisplay));
        Raise(nameof(CapitalUsageDisplay));
        Raise(nameof(AllocatorSummary));
    }

    private void LoadParameterHistory(StrategyItemViewModel strategy)
    {
        foreach (var change in _services.StrategyStore
                     .LoadParameterChanges(strategy.StrategyId, 50)
                     .OrderByDescending(change => change.RequestedAt))
        {
            strategy.ParameterChanges.Add(change);
        }
    }

    private static StrategyPersistentState DefaultStrategyState(
        StrategyManifest manifest,
        StrategyParameterSchema parameters)
    {
        return new StrategyPersistentState(
            manifest.StrategyId,
            StrategyMode.PaperOnly,
            StrategyRuntimeState.Stopped,
            HealthState.Degraded,
            null,
            1,
            parameters.Parameters.ToDictionary(
                parameter => parameter.Key,
                parameter => parameter.DefaultValue,
                StringComparer.Ordinal),
            false,
            LiveToPaperTransition.StopOpeningRisk);
    }

    private void SaveStrategy(StrategyItemViewModel strategy)
    {
        _services.StrategyStore.SaveStrategyState(strategy.PersistentState());
        Raise(nameof(CurrentStrategyMode));
        Raise(nameof(LiveAuthorizationSummary));
        RaiseDashboard();
    }

    private void ApplyPendingParameterChanges(StrategyItemViewModel strategy)
    {
        var pending = strategy.ParameterChanges
            .Where(change => change.Result is
                ParameterChangeResult.PendingCycle or
                ParameterChangeResult.PendingSafeBoundary)
            .OrderBy(change => change.RequestedAt)
            .ToArray();
        foreach (var change in pending)
        {
            var applied = _services.ParameterGovernance.ApplyBoundary(
                change,
                DateTimeOffset.UtcNow);
            _services.StrategyStore.AppendParameterChange(applied);
            var parameter = strategy.Parameters.First(item =>
                string.Equals(
                    item.Key,
                    applied.ParameterKey,
                    StringComparison.Ordinal));
            parameter.Value = applied.NewValue;
            parameter.DraftValue = applied.NewValue;
            parameter.Status = applied.Result.ToString();
            parameter.PreviewText = "Applied at the next safe cycle boundary.";
            strategy.ParameterVersion = Math.Max(
                strategy.ParameterVersion,
                applied.ParameterVersion);
            strategy.ParameterChanges.Remove(change);
            strategy.ParameterChanges.Insert(0, applied);
        }
        strategy.BlocksNewRisk = strategy.ParameterChanges.Any(change =>
            change.RiskTier == RiskTier.High &&
            change.Result is ParameterChangeResult.PendingConfirmation or
                ParameterChangeResult.PendingSafeBoundary);
    }

    private async Task SendRuntimeControlAsync(
        string messageType,
        StrategyRuntimeState resultingState,
        CancellationToken cancellationToken)
    {
        var strategy = SelectedStrategy;
        if (strategy is null ||
            !_externalRuntimes.TryGetValue(
                strategy.StrategyId,
                out var runtime))
        {
            StrategyStatusMessage =
                "No third-party strategy process is running.";
            return;
        }
        var message = CreateCoreMessage(
            strategy,
            $"runtime-{messageType}",
            messageType,
            new Dictionary<string, string>
            {
                ["reason"] = "local_runtime_control"
            });
        try
        {
            await runtime.SendAsync(message, cancellationToken);
            strategy.RuntimeState = resultingState;
            StrategyStatusMessage =
                $"Strategy runtime received {messageType}.";
            SaveStrategy(strategy);
        }
        catch (Exception exception)
        {
            strategy.RuntimeState = StrategyRuntimeState.Rejected;
            StrategyStatusMessage =
                $"Runtime control failed: {SensitiveDataRedactor.Redact(exception.Message)}";
            SaveStrategy(strategy);
        }
    }

    private static StrategyMessageEnvelope CreateCoreMessage(
        StrategyItemViewModel strategy,
        string cycleId,
        string messageType,
        IReadOnlyDictionary<string, string> payload)
    {
        return new StrategyMessageEnvelope(
            1,
            Guid.NewGuid().ToString("D"),
            Guid.NewGuid().ToString("D"),
            strategy.StrategyId,
            strategy.Version,
            cycleId,
            DateTimeOffset.UtcNow,
            messageType,
            payload);
    }

    private void HandleExternalStrategyMessage(
        StrategyItemViewModel strategy,
        StrategyMessageEnvelope message)
    {
        switch (message.MessageType)
        {
            case "ready":
                strategy.RuntimeState = StrategyRuntimeState.Ready;
                break;
            case "heartbeat":
                strategy.LastHeartbeat = message.Timestamp;
                strategy.Health = HealthState.Healthy;
                break;
            case "health":
                strategy.Health = Enum.TryParse<HealthState>(
                    message.Payload.GetValueOrDefault("state"),
                    true,
                    out var health)
                    ? health
                    : HealthState.Degraded;
                break;
            case "log":
                AppendStrategyLog(
                    ParseLogLevel(message.Payload),
                    message.Payload.GetValueOrDefault(
                        "module",
                        "ThirdPartyStrategy"),
                    message.Payload.GetValueOrDefault(
                        "message",
                        "Strategy log event."),
                    strategy.StrategyId,
                    message.CorrelationId,
                    message.CycleId,
                    new Dictionary<string, string>
                    {
                        ["message_type"] = message.MessageType
                    });
                break;
            case "signal":
                if (double.TryParse(
                        message.Payload.GetValueOrDefault("score"),
                        NumberStyles.Float,
                        CultureInfo.InvariantCulture,
                        out var score))
                {
                    strategy.Signals.Insert(0, new StrategySignal(
                        message.Payload.GetValueOrDefault("symbol") ?? "",
                        score,
                        message.Payload.GetValueOrDefault("reason") ?? "",
                        message.Timestamp));
                }
                break;
            case "target_position":
                if (double.TryParse(
                        message.Payload.GetValueOrDefault("target_weight"),
                        NumberStyles.Float,
                        CultureInfo.InvariantCulture,
                        out var weight))
                {
                    strategy.Targets.Insert(0, new StrategyTarget(
                        message.Payload.GetValueOrDefault("symbol") ?? "",
                        weight,
                        message.Payload.GetValueOrDefault("reason") ?? "",
                        message.Timestamp));
                }
                break;
            case "trade_intent":
                var intent = new StrategyIntentRecord(
                    message.Payload.GetValueOrDefault(
                        "intent_id",
                        message.EventId),
                    message.Payload.GetValueOrDefault("symbol") ?? "",
                    double.TryParse(
                        message.Payload.GetValueOrDefault("target_weight"),
                        NumberStyles.Float,
                        CultureInfo.InvariantCulture,
                        out var targetWeight)
                        ? targetWeight
                        : 0,
                    int.TryParse(
                        message.Payload.GetValueOrDefault("priority"),
                        NumberStyles.Integer,
                        CultureInfo.InvariantCulture,
                        out var priority)
                        ? priority
                        : 0,
                    bool.TryParse(
                        message.Payload.GetValueOrDefault("allow_partial"),
                        out var partial) && partial,
                    message.Payload.GetValueOrDefault("reason_code") ?? "",
                    message.CycleId,
                    message.Timestamp,
                    strategy.Mode);
                _services.StrategyIntentRouter.Route(
                    strategy.Mode,
                    intent,
                    _services.LiveBrokerAdapter);
                strategy.Intents.Insert(0, intent);
                break;
            case "cycle_complete":
                strategy.RuntimeState = StrategyRuntimeState.Running;
                strategy.Cycles.Insert(0, new StrategyCycleSummary(
                    message.CycleId,
                    message.Timestamp,
                    strategy.Signals.Count,
                    strategy.Targets.Count,
                    strategy.Intents.Count,
                    message.Payload.GetValueOrDefault(
                        "result",
                        "Completed")));
                break;
            case "error":
                strategy.RuntimeState = StrategyRuntimeState.Unhealthy;
                strategy.Health = HealthState.Unhealthy;
                strategy.BlocksNewRisk = true;
                LatestStrategyAlert =
                    SensitiveDataRedactor.Redact(
                        message.Payload.GetValueOrDefault(
                            "message",
                            "Strategy runtime error."));
                break;
        }
        SaveStrategy(strategy);
    }

    private static ApplicationLogLevel ParseLogLevel(
        IReadOnlyDictionary<string, string> payload)
    {
        return Enum.TryParse<ApplicationLogLevel>(
            payload.GetValueOrDefault("level"),
            true,
            out var level)
            ? level
            : ApplicationLogLevel.Info;
    }

    private void AppendModeAudit(
        StrategyItemViewModel strategy,
        ModeSelectionResult result)
    {
        AppendAudit(
            "StrategyModeSelection",
            new Dictionary<string, string>
            {
                ["strategy_id"] = strategy.StrategyId,
                ["accepted"] = result.Accepted ? "true" : "false",
                ["mode"] = result.Mode.ToString(),
                ["live_lock"] = GlobalLiveLock ? "true" : "false",
                ["live_submission_available"] = "false",
                ["transition"] =
                    strategy.LiveToPaperTransition.ToString()
            },
            result.Accepted
                ? AuditEventCategory.StrategyLifecycle
                : AuditEventCategory.RiskRejection);
    }

    private void RaiseDashboard()
    {
        Raise(nameof(PaperStrategyCount));
        Raise(nameof(LiveStrategyCount));
        Raise(nameof(HealthyStrategyCount));
        Raise(nameof(LatestCycleDisplay));
        Raise(nameof(CurrentStrategyMode));
    }

    private void RaiseExecution()
    {
        Raise(nameof(ExecutionIntents));
        Raise(nameof(ExecutionRiskDecisions));
        Raise(nameof(ExecutionTransfers));
        Raise(nameof(ExecutionOrders));
        Raise(nameof(ExecutionFills));
        Raise(nameof(ExecutionAllocations));
        Raise(nameof(ExecutionShortfalls));
        Raise(nameof(VirtualLedgerPositions));
        Raise(nameof(BrokerNetPositions));
        Raise(nameof(ReconciliationEvents));
        Raise(nameof(CriticalRiskEvents));
        Raise(nameof(PersistentExecutionAlert));
    }

    private static void ReplaceCollection<T>(
        ObservableCollection<T> collection,
        IEnumerable<T> values)
    {
        collection.Clear();
        foreach (var value in values)
        {
            collection.Add(value);
        }
    }

    private static JsonSerializerOptions StrategyJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}

public sealed record BrokerNetPositionView(
    string Symbol,
    decimal Quantity,
    ReconciliationStatus Status);
