using System.Text.Json;
using System.Text.RegularExpressions;

namespace CytisusTrading.Windows;

public interface ILongbridgeAuthenticationService
{
    event Action<LongbridgeAuthenticationProgress>? AuthenticationProgressChanged;

    bool HasAuthorizationCodeInMemory { get; }

    Task<LongbridgeConnectionState> CheckAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken);

    Task<LongbridgeConnectionState> SignInAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken);

    Task<LongbridgeConnectionState> SignInWithAuthorizationCodeAsync(
        string configuredPath,
        string authorizationCode,
        TimeSpan timeout,
        CancellationToken cancellationToken);

    Task<LongbridgeConnectionState> SignOutAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken);

    Task<LongbridgeConnectionState> UpdateAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

public static class LongbridgeMaintenanceCommandFactory
{
    public static LongbridgeMaintenanceCommand Build(
        string executablePath,
        LongbridgeMaintenanceOperation operation,
        string? authorizationCode = null)
    {
        var (category, arguments) = operation switch
        {
            LongbridgeMaintenanceOperation.Version =>
                (CliCallCategory.Maintenance, new[] { "--version" }),
            LongbridgeMaintenanceOperation.RootHelp =>
                (CliCallCategory.Maintenance, new[] { "--help" }),
            LongbridgeMaintenanceOperation.AuthHelp =>
                (CliCallCategory.Authentication, new[] { "auth", "--help" }),
            LongbridgeMaintenanceOperation.DeviceLogin =>
                (CliCallCategory.Authentication, new[] { "auth", "login" }),
            LongbridgeMaintenanceOperation.AuthorizationCodeLogin =>
                (CliCallCategory.Authentication, new[]
                {
                    "auth", "login", "--auth-code",
                    ValidateAuthorizationCode(authorizationCode)
                }),
            LongbridgeMaintenanceOperation.AuthStatus =>
                (CliCallCategory.Authentication, new[]
                {
                    "auth", "status", "--format", "json"
                }),
            LongbridgeMaintenanceOperation.Logout =>
                (CliCallCategory.Authentication, new[] { "auth", "logout" }),
            LongbridgeMaintenanceOperation.ConnectivityCheck =>
                (CliCallCategory.ReadOnlyData, new[]
                {
                    "check", "--format", "json"
                }),
            LongbridgeMaintenanceOperation.Update =>
                (CliCallCategory.Maintenance, new[] { "update" }),
            _ => throw new NotSupportedException(
                "The requested Longbridge maintenance operation is not allowlisted.")
        };
        return new LongbridgeMaintenanceCommand(
            executablePath,
            arguments,
            category,
            operation);
    }

    private static string ValidateAuthorizationCode(string? value)
    {
        var code = value?.Trim() ?? string.Empty;
        if (code.Length is < 4 or > 256 ||
            code.Any(character => char.IsControl(character) || char.IsWhiteSpace(character)))
        {
            throw new ArgumentException("The authorization code format is invalid.");
        }
        return code;
    }
}

public sealed partial class LongbridgeAuthenticationService :
    ILongbridgeAuthenticationService
{
    private const int OutputLimit = 256 * 1024;
    private static readonly Version MinimumPaperChannelVersion = new(0, 20, 0);
    private readonly ILongbridgeCliAdapter _adapter;
    private readonly IReadOnlyProcessRunner _runner;
    private readonly ILongbridgeConnectionStore _store;
    private readonly IAuditEventStore _auditStore;
    private char[]? _authorizationCode;
    private LongbridgeStatusState _lastStatus = LongbridgeStatusState.Missing;

    public event Action<LongbridgeAuthenticationProgress>?
        AuthenticationProgressChanged;

    public LongbridgeAuthenticationService(
        ILongbridgeCliAdapter adapter,
        IReadOnlyProcessRunner runner,
        ILongbridgeConnectionStore store,
        IAuditEventStore auditStore)
    {
        _adapter = adapter;
        _runner = runner;
        _store = store;
        _auditStore = auditStore;
    }

    public bool HasAuthorizationCodeInMemory => _authorizationCode is not null;

    public async Task<LongbridgeConnectionState> CheckAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var inspection = await _adapter.InspectAsync(
            configuredPath,
            timeout,
            cancellationToken).ConfigureAwait(false);
        if (inspection.State == LongbridgeStatusState.Missing ||
            inspection.Capabilities is null)
        {
            return FromInspection(inspection);
        }

        if (!TryParseVersion(inspection.CliVersion, out var version) ||
            version < MinimumPaperChannelVersion)
        {
            return Complete(
                inspection,
                LongbridgeStatusState.UpdateRequired,
                false,
                "Unknown",
                "Unknown",
                Array.Empty<string>(),
                "Version",
                "Longbridge CLI 0.20.0 or later is required to classify Paper accounts.");
        }

        var statusCommand = CapabilityAwareCommandFactory.Build(
            inspection.ExecutablePath,
            inspection.Capabilities,
            LongbridgeOperation.Status);
        var statusResult = await _adapter.ExecuteReadOnlyAsync(
            statusCommand,
            timeout,
            cancellationToken).ConfigureAwait(false);
        if (!statusResult.Succeeded)
        {
            var safeOutput = SensitiveDataRedactor.Redact(
                statusResult.StandardOutput + statusResult.StandardError);
            var unauthenticated = LooksUnauthenticated(safeOutput);
            return Complete(
                inspection,
                unauthenticated
                    ? LongbridgeStatusState.Unauthenticated
                    : LongbridgeStatusState.Degraded,
                false,
                "Unknown",
                "Unknown",
                Array.Empty<string>(),
                unauthenticated ? "Authentication" : "StatusCheck",
                unauthenticated
                    ? "Sign in through Longbridge Terminal."
                    : "Longbridge authentication status could not be checked.");
        }

        var facts = LongbridgeAuthStatusParser.Parse(statusResult.StandardOutput);
        if (facts.RefreshPending)
        {
            return Complete(
                inspection,
                LongbridgeStatusState.RefreshPending,
                false,
                facts.Environment,
                facts.Channel,
                facts.Permissions,
                "Authentication",
                "Longbridge authentication refresh is pending.");
        }
        if (facts.Expired)
        {
            return Complete(
                inspection,
                LongbridgeStatusState.Expired,
                false,
                facts.Environment,
                facts.Channel,
                facts.Permissions,
                "Authentication",
                "Longbridge authentication has expired. Sign in again.");
        }
        if (!facts.Authenticated)
        {
            return Complete(
                inspection,
                LongbridgeStatusState.Unauthenticated,
                false,
                facts.Environment,
                facts.Channel,
                facts.Permissions,
                "Authentication",
                "Sign in through Longbridge Terminal.");
        }

        var checkCommand = CapabilityAwareCommandFactory.Build(
            inspection.ExecutablePath,
            inspection.Capabilities,
            LongbridgeOperation.Connectivity);
        var checkResult = await _adapter.ExecuteReadOnlyAsync(
            checkCommand,
            timeout,
            cancellationToken).ConfigureAwait(false);
        if (!checkResult.Succeeded)
        {
            return Complete(
                inspection,
                LongbridgeStatusState.Degraded,
                false,
                facts.Environment,
                facts.Channel,
                facts.Permissions,
                "Connectivity",
                "Longbridge authentication is valid, but connectivity is degraded.");
        }

        var state = ClassifyChannel(facts.Channel);
        return Complete(
            inspection,
            state,
            true,
            facts.Environment,
            facts.Channel,
            facts.Permissions,
            string.Empty,
            state == LongbridgeStatusState.ReadyPaper
                ? "Longbridge Paper is ready. Local Paper remains independent."
                : state == LongbridgeStatusState.ReadyLive
                    ? "A Longbridge Live account is connected. Live submission remains unavailable."
                    : "The Longbridge account channel is not recognized. Longbridge Paper is blocked.");
    }

    public Task<LongbridgeConnectionState> SignInAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken) =>
        RunLoginAsync(
            configuredPath,
            LongbridgeMaintenanceOperation.DeviceLogin,
            null,
            timeout,
            cancellationToken);

    public Task<LongbridgeConnectionState> SignInWithAuthorizationCodeAsync(
        string configuredPath,
        string authorizationCode,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        _authorizationCode = authorizationCode.ToCharArray();
        return RunAuthorizationCodeLoginAsync(
            configuredPath,
            timeout,
            cancellationToken);
    }

    public async Task<LongbridgeConnectionState> SignOutAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var state = await RunMaintenanceAsync(
            configuredPath,
            LongbridgeMaintenanceOperation.Logout,
            timeout,
            cancellationToken).ConfigureAwait(false);
        return state.Status == LongbridgeStatusState.Degraded
            ? state
            : await CheckAsync(configuredPath, timeout, cancellationToken)
                .ConfigureAwait(false);
    }

    public async Task<LongbridgeConnectionState> UpdateAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var state = await RunMaintenanceAsync(
            configuredPath,
            LongbridgeMaintenanceOperation.Update,
            timeout,
            cancellationToken).ConfigureAwait(false);
        return state.Status == LongbridgeStatusState.Degraded
            ? state
            : await CheckAsync(configuredPath, timeout, cancellationToken)
                .ConfigureAwait(false);
    }

    private async Task<LongbridgeConnectionState> RunAuthorizationCodeLoginAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        try
        {
            var code = _authorizationCode is null
                ? string.Empty
                : new string(_authorizationCode);
            return await RunLoginAsync(
                configuredPath,
                LongbridgeMaintenanceOperation.AuthorizationCodeLogin,
                code,
                timeout,
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            if (_authorizationCode is not null)
            {
                Array.Clear(_authorizationCode);
                _authorizationCode = null;
            }
        }
    }

    private async Task<LongbridgeConnectionState> RunLoginAsync(
        string configuredPath,
        LongbridgeMaintenanceOperation operation,
        string? authorizationCode,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var executable = _adapter.ResolveExecutable(configuredPath);
        if (executable is null)
        {
            return Missing();
        }
        var authHelpCommand = LongbridgeMaintenanceCommandFactory.Build(
            executable,
            LongbridgeMaintenanceOperation.AuthHelp);
        var authHelp = await _runner.RunAsync(
            executable,
            authHelpCommand.Arguments,
            timeout,
            OutputLimit,
            cancellationToken).ConfigureAwait(false);
        if (!authHelp.Succeeded ||
            !authHelp.StandardOutput.Contains(
                "login",
                StringComparison.OrdinalIgnoreCase))
        {
            return Failed(
                executable,
                "Capability",
                "The installed Longbridge CLI does not advertise the required login capability.");
        }
        var command = LongbridgeMaintenanceCommandFactory.Build(
            executable,
            operation,
            authorizationCode);
        var result = _runner is IStreamingProcessRunner streamingRunner
            ? await streamingRunner.RunStreamingAsync(
                command.ExecutablePath,
                command.Arguments,
                timeout,
                OutputLimit,
                HandleAuthenticationOutput,
                cancellationToken).ConfigureAwait(false)
            : await _runner.RunAsync(
                command.ExecutablePath,
                command.Arguments,
                timeout,
                OutputLimit,
                cancellationToken).ConfigureAwait(false);
        AppendAudit(
            operation.ToString(),
            result.Succeeded ? AuditResult.Completed : AuditResult.Failed,
            result);
        if (!result.Succeeded)
        {
            return Failed(
                executable,
                result.Cancelled ? "Cancelled" :
                    result.TimedOut ? "Timeout" : "Authentication",
                result.Cancelled
                    ? "Longbridge sign-in was cancelled."
                    : result.TimedOut
                        ? "Longbridge sign-in timed out."
                        : "Longbridge sign-in failed safely.");
        }

        var progress = ParseLoginProgress(
            result.StandardOutput + Environment.NewLine + result.StandardError);
        var checkedState = await CheckAsync(
            configuredPath,
            timeout,
            cancellationToken).ConfigureAwait(false);
        return checkedState with
        {
            AuthorizationUrl = progress.AuthorizationUrl,
            ShortCode = progress.ShortCode
        };
    }

    private async Task<LongbridgeConnectionState> RunMaintenanceAsync(
        string configuredPath,
        LongbridgeMaintenanceOperation operation,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var executable = _adapter.ResolveExecutable(configuredPath);
        if (executable is null)
        {
            return Missing();
        }
        var command = LongbridgeMaintenanceCommandFactory.Build(executable, operation);
        var result = await _runner.RunAsync(
            command.ExecutablePath,
            command.Arguments,
            timeout,
            OutputLimit,
            cancellationToken).ConfigureAwait(false);
        AppendAudit(
            operation.ToString(),
            result.Succeeded ? AuditResult.Completed : AuditResult.Failed,
            result);
        return result.Succeeded
            ? new LongbridgeConnectionState(
                LongbridgeStatusState.Installed,
                executable,
                "Checking",
                false,
                "Unknown",
                "Unknown",
                Array.Empty<string>(),
                DateTimeOffset.UtcNow,
                string.Empty,
                "Longbridge maintenance operation completed.",
                string.Empty,
                string.Empty)
            : Failed(
                executable,
                result.TimedOut ? "Timeout" : "Maintenance",
                "Longbridge maintenance operation failed safely.");
    }

    private LongbridgeConnectionState Complete(
        LongbridgeInspection inspection,
        LongbridgeStatusState status,
        bool connectivityReady,
        string environment,
        string channel,
        IReadOnlyList<string> permissions,
        string failureCategory,
        string message)
    {
        var metadata = new LongbridgeConnectionMetadata(
            NormalizeDisplay(environment),
            NormalizeDisplay(channel),
            DateTimeOffset.UtcNow,
            inspection.CliVersion,
            permissions
                .Select(NormalizeDisplay)
                .Where(value => value != "Unknown")
                .Distinct(StringComparer.Ordinal)
                .Take(32)
                .ToArray());
        _store.SaveLongbridgeConnection(metadata);
        var previousStatus = _lastStatus;
        _lastStatus = status;
        AppendAudit(
            "ConnectionStateChecked",
            status is LongbridgeStatusState.ReadyPaper or
                LongbridgeStatusState.ReadyLive or
                LongbridgeStatusState.ReadyUnknownChannel
                ? AuditResult.Completed
                : AuditResult.Rejected,
            status,
            previousStatus,
            metadata);
        return new LongbridgeConnectionState(
            status,
            inspection.ExecutablePath,
            inspection.CliVersion,
            connectivityReady,
            metadata.AccountEnvironment,
            metadata.AccountChannel,
            metadata.PermissionsSummary,
            metadata.StatusCheckedAt,
            failureCategory,
            message,
            string.Empty,
            string.Empty);
    }

    private static LongbridgeStatusState ClassifyChannel(string channel)
    {
        var normalized = channel.Trim().ToLowerInvariant();
        if (normalized == "lb_papertrading")
        {
            return LongbridgeStatusState.ReadyPaper;
        }
        if (normalized is "lb_live" or "live" or "production" or "real")
        {
            return LongbridgeStatusState.ReadyLive;
        }
        return LongbridgeStatusState.ReadyUnknownChannel;
    }

    private static LongbridgeConnectionState FromInspection(
        LongbridgeInspection inspection) =>
        new(
            inspection.State,
            inspection.ExecutablePath,
            inspection.CliVersion,
            false,
            "Unknown",
            "Unknown",
            inspection.DataPermissions,
            inspection.CheckedAt,
            inspection.State == LongbridgeStatusState.Missing
                ? "Discovery"
                : "Capability",
            inspection.Message,
            string.Empty,
            string.Empty);

    private static LongbridgeConnectionState Missing() =>
        new(
            LongbridgeStatusState.Missing,
            string.Empty,
            "Unavailable",
            false,
            "Unknown",
            "Unknown",
            Array.Empty<string>(),
            DateTimeOffset.UtcNow,
            "Discovery",
            "Longbridge CLI was not found. Local Paper remains available.",
            string.Empty,
            string.Empty);

    private static LongbridgeConnectionState Failed(
        string executable,
        string failureCategory,
        string message) =>
        new(
            LongbridgeStatusState.Degraded,
            executable,
            "Unknown",
            false,
            "Unknown",
            "Unknown",
            Array.Empty<string>(),
            DateTimeOffset.UtcNow,
            failureCategory,
            message,
            string.Empty,
            string.Empty);

    private void AppendAudit(
        string action,
        AuditResult auditResult,
        CliProcessResult result)
    {
        _auditStore.AppendAuditEvent(new AuditEvent(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            AuditEventCategory.AccountMapping,
            action,
            auditResult,
            "Operator",
            Guid.NewGuid().ToString("D"),
            new Dictionary<string, string>
            {
                ["timed_out"] = result.TimedOut.ToString().ToLowerInvariant(),
                ["cancelled"] = result.Cancelled.ToString().ToLowerInvariant(),
                ["output_logged"] = "false"
            }));
    }

    private void AppendAudit(
        string action,
        AuditResult result,
        LongbridgeStatusState status,
        LongbridgeStatusState previousStatus,
        LongbridgeConnectionMetadata metadata)
    {
        _auditStore.AppendAuditEvent(new AuditEvent(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            AuditEventCategory.AccountMapping,
            action,
            result,
            "Application",
            Guid.NewGuid().ToString("D"),
            new Dictionary<string, string>
            {
                ["previous_status"] = previousStatus.ToString(),
                ["status"] = status.ToString(),
                ["environment"] = metadata.AccountEnvironment,
                ["channel"] = metadata.AccountChannel,
                ["raw_output_stored"] = "false"
            }));
    }

    private static LongbridgeAuthenticationProgress ParseLoginProgress(string output)
    {
        var safe = SensitiveDataRedactor.Redact(output);
        var url = UrlPattern().Match(safe).Value;
        var codeMatch = ShortCodePattern().Match(safe);
        return new LongbridgeAuthenticationProgress(
            LongbridgeStatusState.Authorizing,
            url.Length <= 512 ? url : string.Empty,
            codeMatch.Success ? codeMatch.Groups[1].Value : string.Empty,
            "Complete authorization in the browser, then return to Cytisus.");
    }

    private void HandleAuthenticationOutput(string output)
    {
        var progress = ParseLoginProgress(output);
        if (!string.IsNullOrWhiteSpace(progress.AuthorizationUrl) ||
            !string.IsNullOrWhiteSpace(progress.ShortCode))
        {
            AuthenticationProgressChanged?.Invoke(progress);
        }
    }

    private static bool TryParseVersion(string value, out Version version)
    {
        var match = VersionPattern().Match(value);
        if (match.Success &&
            Version.TryParse(match.Groups[1].Value, out var parsed))
        {
            version = parsed;
            return true;
        }
        version = new Version(0, 0, 0);
        return false;
    }

    private static bool LooksUnauthenticated(string value) =>
        value.Contains("unauthenticated", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("not authorized", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("login required", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("sign in", StringComparison.OrdinalIgnoreCase);

    private static string NormalizeDisplay(string value)
    {
        var safe = SensitiveDataRedactor.Redact(value).Trim();
        if (safe.Length == 0)
        {
            return "Unknown";
        }
        return safe.Length <= 128 ? safe : safe[..128];
    }

    [GeneratedRegex(@"\b(\d+\.\d+\.\d+)\b", RegexOptions.CultureInvariant)]
    private static partial Regex VersionPattern();

    [GeneratedRegex(
        @"https://[^\s""'<>]+",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex UrlPattern();

    [GeneratedRegex(
        @"(?i)(?:code|verification)[^A-Z0-9]{0,12}([A-Z0-9-]{4,16})",
        RegexOptions.CultureInvariant)]
    private static partial Regex ShortCodePattern();
}

public sealed record LongbridgeAuthFacts(
    bool Authenticated,
    bool RefreshPending,
    bool Expired,
    string Environment,
    string Channel,
    IReadOnlyList<string> Permissions);

public static class LongbridgeAuthStatusParser
{
    public static LongbridgeAuthFacts Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var values = new Dictionary<string, List<JsonElement>>(
            StringComparer.OrdinalIgnoreCase);
        Visit(document.RootElement, values);
        var authenticated = FindBool(values, "authenticated") ??
            FindStatus(values) is "authenticated" or "ready" or "active";
        var refreshPending = FindBool(values, "refresh_pending") ??
            FindStatus(values) is "refreshpending" or "refresh_pending";
        var expired = FindBool(values, "expired") ??
            FindStatus(values) is "expired";
        return new LongbridgeAuthFacts(
            authenticated,
            refreshPending,
            expired,
            FindString(values, "account_environment", "environment"),
            FindString(values, "account_channel", "channel"),
            FindStrings(values, "permissions", "scopes"));
    }

    private static void Visit(
        JsonElement element,
        IDictionary<string, List<JsonElement>> values)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                var key = property.Name.Replace("-", "_", StringComparison.Ordinal);
                if (!values.TryGetValue(key, out var entries))
                {
                    entries = new List<JsonElement>();
                    values[key] = entries;
                }
                entries.Add(property.Value.Clone());
                Visit(property.Value, values);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                Visit(item, values);
            }
        }
    }

    private static bool? FindBool(
        IReadOnlyDictionary<string, List<JsonElement>> values,
        string key)
    {
        if (!values.TryGetValue(key, out var entries))
        {
            return null;
        }
        foreach (var entry in entries)
        {
            if (entry.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                return entry.GetBoolean();
            }
        }
        return null;
    }

    private static string FindStatus(
        IReadOnlyDictionary<string, List<JsonElement>> values) =>
        FindString(values, "auth_status", "status")
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .ToLowerInvariant();

    private static string FindString(
        IReadOnlyDictionary<string, List<JsonElement>> values,
        params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!values.TryGetValue(key, out var entries))
            {
                continue;
            }
            var value = entries.FirstOrDefault(entry =>
                entry.ValueKind == JsonValueKind.String);
            if (value.ValueKind == JsonValueKind.String)
            {
                return SensitiveDataRedactor.Redact(value.GetString() ?? string.Empty);
            }
        }
        return "Unknown";
    }

    private static IReadOnlyList<string> FindStrings(
        IReadOnlyDictionary<string, List<JsonElement>> values,
        params string[] keys)
    {
        var result = new List<string>();
        foreach (var key in keys)
        {
            if (!values.TryGetValue(key, out var entries))
            {
                continue;
            }
            foreach (var entry in entries)
            {
                if (entry.ValueKind == JsonValueKind.Array)
                {
                    result.AddRange(entry
                        .EnumerateArray()
                        .Where(item => item.ValueKind == JsonValueKind.String)
                        .Select(item => SensitiveDataRedactor.Redact(
                            item.GetString() ?? string.Empty)));
                }
            }
        }
        return result
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.Ordinal)
            .Take(32)
            .ToArray();
    }
}

public static class LongbridgeInstallGuidance
{
    public const string RepositoryUrl =
        "https://github.com/longbridge/longbridge-terminal";
    public const string WindowsPowerShell =
        "iwr https://open.longbridge.cn/longbridge/longbridge-terminal/install.ps1 | iex";
    public const string WindowsScoop =
        "scoop install https://open.longbridge.cn/longbridge/longbridge-terminal/longbridge.json";
    public const string MacHomebrew =
        "brew install --cask longbridge/tap/longbridge-terminal";
    public const string MacShell =
        "curl -sSL https://open.longbridge.cn/longbridge/longbridge-terminal/install | sh";
}
