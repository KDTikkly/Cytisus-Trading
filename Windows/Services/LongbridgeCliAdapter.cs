using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace CytisusTrading.Windows;

public interface IReadOnlyProcessRunner
{
    Task<CliProcessResult> RunAsync(
        string executablePath,
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        int outputLimit,
        CancellationToken cancellationToken);
}

public sealed class LongbridgeProcessRunner : IReadOnlyProcessRunner
{
    public async Task<CliProcessResult> RunAsync(
        string executablePath,
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        int outputLimit,
        CancellationToken cancellationToken)
    {
        if (timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = executablePath,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = startInfo };
        var standardOutput = new BoundedOutput(outputLimit);
        var standardError = new BoundedOutput(outputLimit);
        process.OutputDataReceived += (_, eventArgs) =>
            standardOutput.AppendLine(eventArgs.Data);
        process.ErrorDataReceived += (_, eventArgs) =>
            standardError.AppendLine(eventArgs.Data);

        var startedAt = Stopwatch.GetTimestamp();
        if (!process.Start())
        {
            throw new InvalidOperationException("The CLI process did not start.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linkedSource = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutSource.Token);

        var timedOut = false;
        var cancelled = false;
        try
        {
            await process.WaitForExitAsync(linkedSource.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            cancelled = cancellationToken.IsCancellationRequested;
            timedOut = !cancelled && timeoutSource.IsCancellationRequested;
            TryKill(process);
            await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
        }

        process.WaitForExit();
        return new CliProcessResult(
            process.ExitCode,
            standardOutput.Value,
            standardError.Value,
            timedOut,
            cancelled,
            standardOutput.Truncated || standardError.Truncated,
            Stopwatch.GetElapsedTime(startedAt));
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
        }
    }

    private sealed class BoundedOutput
    {
        private readonly int _limit;
        private readonly StringBuilder _builder = new();
        private readonly object _gate = new();

        public BoundedOutput(int limit)
        {
            _limit = Math.Max(0, limit);
        }

        public bool Truncated { get; private set; }

        public string Value
        {
            get
            {
                lock (_gate)
                {
                    return _builder.ToString();
                }
            }
        }

        public void AppendLine(string? value)
        {
            if (value is null)
            {
                return;
            }

            lock (_gate)
            {
                var remaining = _limit - _builder.Length;
                if (remaining <= 0)
                {
                    Truncated = true;
                    return;
                }

                var line = value + Environment.NewLine;
                if (line.Length > remaining)
                {
                    _builder.Append(line.AsSpan(0, remaining));
                    Truncated = true;
                    return;
                }

                _builder.Append(line);
            }
        }
    }
}

public static partial class SensitiveDataRedactor
{
    private const string Redacted = "[REDACTED]";

    public static string Redact(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return value;
        }

        var json = TryRedactJson(value);
        var redacted = json ?? value;
        redacted = BearerPattern().Replace(redacted, "Bearer " + Redacted);
        redacted = NamedSecretPattern().Replace(
            redacted,
            match => $"{match.Groups[1].Value}{Redacted}");
        return redacted;
    }

    private static string? TryRedactJson(string value)
    {
        try
        {
            var node = JsonNode.Parse(value);
            if (node is null)
            {
                return null;
            }

            RedactNode(node);
            return node.ToJsonString(new JsonSerializerOptions
            {
                WriteIndented = false
            });
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static void RedactNode(JsonNode node)
    {
        if (node is JsonObject jsonObject)
        {
            foreach (var property in jsonObject.ToArray())
            {
                if (IsSensitiveKey(property.Key))
                {
                    jsonObject[property.Key] = Redacted;
                }
                else if (property.Value is not null)
                {
                    RedactNode(property.Value);
                }
            }
        }
        else if (node is JsonArray jsonArray)
        {
            foreach (var child in jsonArray)
            {
                if (child is not null)
                {
                    RedactNode(child);
                }
            }
        }
    }

    private static bool IsSensitiveKey(string key)
    {
        var normalized = key
            .Replace("-", "_", StringComparison.Ordinal)
            .ToLowerInvariant();
        return normalized.Contains("token", StringComparison.Ordinal) ||
            normalized.Contains("secret", StringComparison.Ordinal) ||
            normalized.Contains("password", StringComparison.Ordinal) ||
            normalized.Contains("credential", StringComparison.Ordinal) ||
            normalized is "authorization" or "authorization_code" or
                "oauth" or "account_id" or
                "account_number" or "full_account_number";
    }

    [GeneratedRegex(
        @"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+",
        RegexOptions.CultureInvariant)]
    private static partial Regex BearerPattern();

    [GeneratedRegex(
        @"(?i)\b(token|secret|password|authorization|authorization_code|account_number)\s*[:=]\s*[^\s,;]+",
        RegexOptions.CultureInvariant)]
    private static partial Regex NamedSecretPattern();
}

public static class CapabilityAwareCommandFactory
{
    public static CliCommand Build(
        string executablePath,
        LongbridgeCapabilities capabilities,
        LongbridgeOperation operation,
        IReadOnlyDictionary<string, string>? values = null)
    {
        var template = capabilities.Commands.SingleOrDefault(
            command => command.Operation == operation)
            ?? throw new NotSupportedException(
                $"The installed CLI does not advertise {operation}.");
        var arguments = template.Arguments
            .Select(argument => ReplacePlaceholders(argument, values))
            .ToArray();
        if (arguments.Any(argument =>
                argument.Contains('{', StringComparison.Ordinal) ||
                argument.Contains('}', StringComparison.Ordinal)))
        {
            throw new ArgumentException(
                $"Missing a required argument value for {operation}.");
        }

        return new CliCommand(
            executablePath,
            arguments,
            CliCallCategory.ReadOnlyData,
            operation);
    }

    private static string ReplacePlaceholders(
        string argument,
        IReadOnlyDictionary<string, string>? values)
    {
        if (values is null)
        {
            return argument;
        }

        var result = argument;
        foreach (var pair in values)
        {
            ValidateValue(pair.Value);
            result = result.Replace(
                $"{{{pair.Key}}}",
                pair.Value,
                StringComparison.Ordinal);
        }
        return result;
    }

    private static void ValidateValue(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Length > 256 ||
            value.StartsWith("-", StringComparison.Ordinal) ||
            value.Any(character => char.IsControl(character)))
        {
            throw new ArgumentException("CLI argument values must be bounded text.");
        }
    }
}

public interface ILongbridgeCliAdapter
{
    string? ResolveExecutable(string configuredPath);
    Task<LongbridgeInspection> InspectAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken);
    Task<CliProcessResult> ExecuteReadOnlyAsync(
        CliCommand command,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

public sealed class LongbridgeCliAdapter : ILongbridgeCliAdapter
{
    private const int OutputLimit = 1024 * 1024;
    private readonly IReadOnlyProcessRunner _runner;

    public LongbridgeCliAdapter(IReadOnlyProcessRunner runner)
    {
        _runner = runner;
    }

    public string? ResolveExecutable(string configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            var resolved = Path.GetFullPath(configuredPath.Trim());
            return File.Exists(resolved) ? resolved : null;
        }

        var searchPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in searchPath.Split(
                     Path.PathSeparator,
                     StringSplitOptions.RemoveEmptyEntries |
                     StringSplitOptions.TrimEntries))
        {
            foreach (var fileName in new[] { "longbridge.exe", "longbridge" })
            {
                var candidate = Path.Combine(directory, fileName);
                if (File.Exists(candidate))
                {
                    return Path.GetFullPath(candidate);
                }
            }
        }

        return null;
    }

    public async Task<LongbridgeInspection> InspectAsync(
        string configuredPath,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var executablePath = ResolveExecutable(configuredPath);
        if (executablePath is null)
        {
            return new LongbridgeInspection(
                LongbridgeStatusState.Missing,
                string.Empty,
                "Unavailable",
                DateTimeOffset.UtcNow,
                Array.Empty<string>(),
                "Longbridge CLI was not found. Fixture mode remains available.",
                null);
        }

        var versionResult = await _runner.RunAsync(
            executablePath,
            new[] { "--version" },
            timeout,
            OutputLimit,
            cancellationToken).ConfigureAwait(false);
        if (!versionResult.Succeeded)
        {
            return FailedInspection(
                executablePath,
                "Unavailable",
                versionResult,
                "CLI version inspection failed.");
        }

        var version = FirstBoundedLine(versionResult.StandardOutput);
        var rootHelp = await _runner.RunAsync(
            executablePath,
            new[] { "--help" },
            timeout,
            OutputLimit,
            cancellationToken).ConfigureAwait(false);
        if (!rootHelp.Succeeded)
        {
            return FailedInspection(
                executablePath,
                version,
                rootHelp,
                "CLI help inspection failed.");
        }

        var templates = await DiscoverTemplatesAsync(
            executablePath,
            rootHelp.StandardOutput,
            timeout,
            cancellationToken).ConfigureAwait(false);
        var permissions = DataPermissions(templates);
        var capabilities = new LongbridgeCapabilities(
            1,
            false,
            version,
            $"{version}|cytisus-adapter-1.1.0",
            LongbridgeStatusState.Degraded,
            HasJsonOutput(rootHelp.StandardOutput),
            templates,
            permissions,
            DateTimeOffset.UtcNow,
            false,
            "Capabilities were derived from local CLI help.");

        var statusTemplate = templates.SingleOrDefault(
            template => template.Operation == LongbridgeOperation.Status);
        var connectivityTemplate = templates.SingleOrDefault(
            template => template.Operation == LongbridgeOperation.Connectivity);
        if (statusTemplate is null || connectivityTemplate is null)
        {
            return new LongbridgeInspection(
                LongbridgeStatusState.Degraded,
                executablePath,
                version,
                DateTimeOffset.UtcNow,
                permissions,
                "Required read-only status or connectivity capability is unavailable.",
                capabilities);
        }

        var statusResult = await ExecuteReadOnlyAsync(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.Status),
            timeout,
            cancellationToken).ConfigureAwait(false);
        if (!statusResult.Succeeded)
        {
            var output = SensitiveDataRedactor.Redact(
                statusResult.StandardOutput + statusResult.StandardError);
            var state = LooksUnauthenticated(output)
                ? LongbridgeStatusState.Unauthenticated
                : LongbridgeStatusState.Degraded;
            return new LongbridgeInspection(
                state,
                executablePath,
                version,
                DateTimeOffset.UtcNow,
                permissions,
                state == LongbridgeStatusState.Unauthenticated
                    ? "Complete authorization through Longbridge CLI."
                    : "The local CLI status check failed.",
                capabilities with { StatusState = state });
        }

        if (StatusSaysUnauthenticated(statusResult.StandardOutput))
        {
            return new LongbridgeInspection(
                LongbridgeStatusState.Unauthenticated,
                executablePath,
                version,
                DateTimeOffset.UtcNow,
                permissions,
                "Complete authorization through Longbridge CLI.",
                capabilities with
                {
                    StatusState = LongbridgeStatusState.Unauthenticated
                });
        }

        var connectionResult = await ExecuteReadOnlyAsync(
            CapabilityAwareCommandFactory.Build(
                executablePath,
                capabilities,
                LongbridgeOperation.Connectivity),
            timeout,
            cancellationToken).ConfigureAwait(false);
        var ready = connectionResult.Succeeded;
        var stateResult = ready
            ? LongbridgeStatusState.Ready
            : LongbridgeStatusState.Degraded;
        return new LongbridgeInspection(
            stateResult,
            executablePath,
            version,
            DateTimeOffset.UtcNow,
            permissions,
            ready
                ? "The local CLI is ready for advertised read-only data calls."
                : "The local CLI connectivity check failed.",
            capabilities with { StatusState = stateResult });
    }

    public Task<CliProcessResult> ExecuteReadOnlyAsync(
        CliCommand command,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (command.Category != CliCallCategory.ReadOnlyData)
        {
            throw new InvalidOperationException(
                "This adapter accepts read-only data calls only.");
        }

        return _runner.RunAsync(
            command.ExecutablePath,
            command.Arguments,
            timeout,
            OutputLimit,
            cancellationToken);
    }

    private async Task<IReadOnlyList<CliCommandTemplate>> DiscoverTemplatesAsync(
        string executablePath,
        string rootHelp,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var templates = new List<CliCommandTemplate>();
        var jsonArguments = JsonArguments(rootHelp);
        if (ContainsWord(rootHelp, "status") && jsonArguments.Count > 0)
        {
            templates.Add(new CliCommandTemplate(
                LongbridgeOperation.Status,
                new[] { "status" }.Concat(jsonArguments).ToArray()));
        }

        var connectivityCommand = ContainsWord(rootHelp, "doctor")
            ? "doctor"
            : ContainsWord(rootHelp, "check")
                ? "check"
                : null;
        if (connectivityCommand is not null && jsonArguments.Count > 0)
        {
            templates.Add(new CliCommandTemplate(
                LongbridgeOperation.Connectivity,
                new[] { connectivityCommand }.Concat(jsonArguments).ToArray()));
        }

        if (!ContainsWord(rootHelp, "market"))
        {
            return templates;
        }

        var marketHelpResult = await _runner.RunAsync(
            executablePath,
            new[] { "market", "--help" },
            timeout,
            OutputLimit,
            cancellationToken).ConfigureAwait(false);
        if (!marketHelpResult.Succeeded)
        {
            return templates;
        }

        var marketHelp = marketHelpResult.StandardOutput;
        var marketJsonArguments = JsonArguments(marketHelp);
        AddMarketTemplate(
            templates,
            marketHelp,
            marketJsonArguments,
            "bars",
            LongbridgeOperation.HistoricalBars,
            "--symbol", "{symbol}",
            "--interval", "{interval}",
            "--start", "{start}",
            "--end", "{end}");
        AddMarketTemplate(
            templates,
            marketHelp,
            marketJsonArguments,
            "snapshot",
            LongbridgeOperation.CurrentSnapshot,
            "--symbol", "{symbol}");
        AddMarketTemplate(
            templates,
            marketHelp,
            marketJsonArguments,
            "status",
            LongbridgeOperation.MarketStatus,
            "--market", "{market}");
        AddMarketTemplate(
            templates,
            marketHelp,
            marketJsonArguments,
            "securities",
            LongbridgeOperation.SecurityList,
            "--market", "{market}");

        if (ContainsWord(rootHelp, "account"))
        {
            var accountHelpResult = await _runner.RunAsync(
                executablePath,
                new[] { "account", "--help" },
                timeout,
                OutputLimit,
                cancellationToken).ConfigureAwait(false);
            if (accountHelpResult.Succeeded &&
                ContainsWord(accountHelpResult.StandardOutput, "positions"))
            {
                var accountJsonArguments =
                    JsonArguments(accountHelpResult.StandardOutput);
                if (accountJsonArguments.Count > 0)
                {
                    templates.Add(new CliCommandTemplate(
                        LongbridgeOperation.BrokerPositions,
                        new[] { "account", "positions" }
                            .Concat(accountJsonArguments)
                            .ToArray()));
                }
            }
        }
        return templates;
    }

    private static void AddMarketTemplate(
        ICollection<CliCommandTemplate> templates,
        string help,
        IReadOnlyList<string> jsonArguments,
        string commandName,
        LongbridgeOperation operation,
        params string[] operationArguments)
    {
        var flags = operationArguments
            .Where(argument => argument.StartsWith("--", StringComparison.Ordinal))
            .ToArray();
        if (!ContainsWord(help, commandName) ||
            jsonArguments.Count == 0 ||
            flags.Any(flag => !help.Contains(flag, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        templates.Add(new CliCommandTemplate(
            operation,
            new[] { "market", commandName }
                .Concat(operationArguments)
                .Concat(jsonArguments)
                .ToArray()));
    }

    private static IReadOnlyList<string> JsonArguments(string help)
    {
        if (help.Contains("--output", StringComparison.OrdinalIgnoreCase) &&
            help.Contains("json", StringComparison.OrdinalIgnoreCase))
        {
            return new[] { "--output", "json" };
        }

        if (help.Contains("--json", StringComparison.OrdinalIgnoreCase))
        {
            return new[] { "--json" };
        }

        return Array.Empty<string>();
    }

    private static bool HasJsonOutput(string help)
    {
        return JsonArguments(help).Count > 0;
    }

    private static bool ContainsWord(string value, string word)
    {
        return Regex.IsMatch(
            value,
            $@"(?i)(^|\s){Regex.Escape(word)}(\s|$)");
    }

    private static IReadOnlyList<string> DataPermissions(
        IReadOnlyCollection<CliCommandTemplate> templates)
    {
        var permissions = new List<string>();
        if (templates.Any(template =>
                template.Operation == LongbridgeOperation.HistoricalBars))
        {
            permissions.Add("historical_bars");
        }
        if (templates.Any(template =>
                template.Operation == LongbridgeOperation.CurrentSnapshot))
        {
            permissions.Add("current_snapshot");
        }
        if (templates.Any(template =>
                template.Operation == LongbridgeOperation.MarketStatus))
        {
            permissions.Add("market_status");
        }
        if (templates.Any(template =>
                template.Operation == LongbridgeOperation.SecurityList))
        {
            permissions.Add("security_list");
        }
        if (templates.Any(template =>
                template.Operation == LongbridgeOperation.BrokerPositions))
        {
            permissions.Add("position_snapshot");
        }
        return permissions;
    }

    private static LongbridgeInspection FailedInspection(
        string executablePath,
        string version,
        CliProcessResult result,
        string message)
    {
        var state = result.TimedOut || result.Cancelled
            ? LongbridgeStatusState.Degraded
            : LongbridgeStatusState.Degraded;
        return new LongbridgeInspection(
            state,
            executablePath,
            version,
            DateTimeOffset.UtcNow,
            Array.Empty<string>(),
            result.TimedOut ? $"{message} The process timed out." : message,
            null);
    }

    private static string FirstBoundedLine(string value)
    {
        var line = value
            .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault() ?? "Unknown";
        var redacted = SensitiveDataRedactor.Redact(line.Trim());
        return redacted.Length <= 128 ? redacted : redacted[..128];
    }

    private static bool LooksUnauthenticated(string value)
    {
        return value.Contains("unauthenticated", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("not authorized", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("login required", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("authorize", StringComparison.OrdinalIgnoreCase);
    }

    private static bool StatusSaysUnauthenticated(string value)
    {
        try
        {
            using var document = JsonDocument.Parse(value);
            return FindFalseAuthenticated(document.RootElement);
        }
        catch (JsonException)
        {
            return LooksUnauthenticated(
                SensitiveDataRedactor.Redact(value));
        }
    }

    private static bool FindFalseAuthenticated(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                if (property.Name.Equals(
                        "authenticated",
                        StringComparison.OrdinalIgnoreCase) &&
                    property.Value.ValueKind == JsonValueKind.False)
                {
                    return true;
                }
                if (FindFalseAuthenticated(property.Value))
                {
                    return true;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            return element.EnumerateArray().Any(FindFalseAuthenticated);
        }

        return false;
    }
}
