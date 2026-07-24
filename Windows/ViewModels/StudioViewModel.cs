using System.Collections.ObjectModel;
using System.Globalization;

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

        ReplaceFactors(services.FactorRepository.LoadFactors());
        foreach (var entry in services.LogStore.LoadLogs(50))
        {
            ApplicationLogs.Add(entry);
        }

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

    public StrategyMode CurrentStrategyMode => StrategyMode.PaperOnly;
    public bool LiveExecutionAvailable => false;

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
            var inspection = await _services.CliAdapter.InspectAsync(
                CliExecutablePath,
                timeout,
                cancellationToken);
            CliStatusState = inspection.State;
            CliVersion = inspection.CliVersion;
            CliPathDisplay = string.IsNullOrWhiteSpace(inspection.ExecutablePath)
                ? "System PATH lookup did not resolve an executable"
                : inspection.ExecutablePath;
            LastCheckDisplay = inspection.CheckedAt
                .ToLocalTime()
                .ToString("g", EnglishCulture);
            DataPermissionsSummary = inspection.DataPermissions.Count == 0
                ? "No advertised market-data permissions"
                : string.Join(", ", inspection.DataPermissions);
            CliStatusMessage = inspection.Message;

            AppendLog(
                inspection.State == LongbridgeStatusState.Ready
                    ? ApplicationLogLevel.Info
                    : ApplicationLogLevel.Warning,
                "LongbridgeCLI",
                $"Read-only capability check completed with state {inspection.State}.",
                new Dictionary<string, string>
                {
                    ["call_category"] = CliCallCategory.ReadOnlyData.ToString(),
                    ["state"] = inspection.State.ToString(),
                    ["exit_output_logged"] = "false"
                });

            if (inspection.State != LongbridgeStatusState.Ready ||
                inspection.Capabilities is null)
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
            LongbridgeOperation.HistoricalBars,
            LongbridgeOperation.MarketStatus
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
        var marketStatus =
            await _services.MarketDataClient.FetchMarketStatusAsync(
                inspection.ExecutablePath,
                capabilities,
                DefaultMarket,
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
        MarketSession = marketStatus.Session;
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
                LogRetentionDays = (int)LogRetentionDays
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
        IReadOnlyDictionary<string, string> context)
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
