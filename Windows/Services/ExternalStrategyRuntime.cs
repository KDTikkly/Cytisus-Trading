using System.Diagnostics;
using System.Text;

namespace CytisusTrading.Windows;

public sealed class ExternalStrategyRuntime : IAsyncDisposable
{
    private const int MaximumErrorLineCharacters = 4096;
    private readonly StrategyManifest _manifest;
    private readonly StrategyMessageCodec _codec;
    private readonly TimeSpan _heartbeatTimeout;
    private readonly TimeSpan _shutdownTimeout;
    private readonly Action<StrategyMessageEnvelope> _messageHandler;
    private readonly Action<ApplicationLogEntry> _logHandler;
    private readonly HashSet<string> _eventIds =
        new(StringComparer.Ordinal);
    private readonly CancellationTokenSource _lifetime = new();
    private Process? _process;
    private Task? _standardOutputTask;
    private Task? _standardErrorTask;

    public ExternalStrategyRuntime(
        StrategyManifest manifest,
        StrategyMessageCodec codec,
        TimeSpan heartbeatTimeout,
        TimeSpan shutdownTimeout,
        Action<StrategyMessageEnvelope> messageHandler,
        Action<ApplicationLogEntry> logHandler)
    {
        _manifest = manifest;
        _codec = codec;
        _heartbeatTimeout = heartbeatTimeout;
        _shutdownTimeout = shutdownTimeout;
        _messageHandler = messageHandler;
        _logHandler = logHandler;
    }

    public StrategyRuntimeState State { get; private set; } =
        StrategyRuntimeState.Stopped;
    public DateTimeOffset? LastHeartbeat { get; private set; }
    public int? ExitCode { get; private set; }

    public async Task StartAsync(
        StrategyMessageEnvelope initialize,
        CancellationToken cancellationToken)
    {
        if (_manifest.Source != StrategySource.ThirdParty)
        {
            throw new InvalidOperationException(
                "External runtime accepts ThirdParty strategies only.");
        }
        if (State != StrategyRuntimeState.Stopped)
        {
            throw new InvalidOperationException(
                "Strategy runtime has already started.");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = _manifest.Entrypoint,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        _process = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true
        };
        _process.Exited += (_, _) =>
        {
            ExitCode = _process?.ExitCode;
            if (State is not StrategyRuntimeState.Rejected)
            {
                State = StrategyRuntimeState.Exited;
            }
        };

        State = StrategyRuntimeState.Starting;
        if (!_process.Start())
        {
            State = StrategyRuntimeState.Rejected;
            throw new InvalidOperationException(
                "Strategy process did not start.");
        }
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            _lifetime.Token);
        _standardOutputTask = PumpStandardOutputAsync(linked.Token);
        _standardErrorTask = PumpStandardErrorAsync(linked.Token);
        await SendAsync(initialize, linked.Token).ConfigureAwait(false);
    }

    public async Task SendAsync(
        StrategyMessageEnvelope message,
        CancellationToken cancellationToken)
    {
        var process = _process
            ?? throw new InvalidOperationException(
                "Strategy process is not running.");
        if (process.HasExited)
        {
            State = StrategyRuntimeState.Exited;
            throw new InvalidOperationException(
                "Strategy process has exited.");
        }
        var line = _codec.Encode(
            message,
            StrategyMessageDirection.CoreToStrategy);
        await process.StandardInput.WriteAsync(
            line.AsMemory(),
            cancellationToken).ConfigureAwait(false);
        await process.StandardInput.FlushAsync(
            cancellationToken).ConfigureAwait(false);
    }

    public bool EvaluateHeartbeat(DateTimeOffset now)
    {
        var timedOut = new StrategyHeartbeatMonitor(
            _heartbeatTimeout).IsTimedOut(LastHeartbeat, now);
        if (timedOut)
        {
            State = StrategyRuntimeState.Unhealthy;
        }
        return timedOut;
    }

    public async Task ShutdownAsync(
        StrategyMessageEnvelope shutdown,
        CancellationToken cancellationToken)
    {
        var process = _process;
        if (process is null || process.HasExited)
        {
            return;
        }

        try
        {
            await SendAsync(shutdown, cancellationToken).ConfigureAwait(false);
            process.StandardInput.Close();
            using var timeout = new CancellationTokenSource(_shutdownTimeout);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken,
                timeout.Token);
            await process.WaitForExitAsync(linked.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync(
                    CancellationToken.None).ConfigureAwait(false);
            }
        }
        finally
        {
            _lifetime.Cancel();
            State = StrategyRuntimeState.Exited;
        }
    }

    public async ValueTask DisposeAsync()
    {
        _lifetime.Cancel();
        if (_process is { HasExited: false } process)
        {
            process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(
                CancellationToken.None).ConfigureAwait(false);
        }
        if (_standardOutputTask is not null)
        {
            await IgnoreCancellation(_standardOutputTask).ConfigureAwait(false);
        }
        if (_standardErrorTask is not null)
        {
            await IgnoreCancellation(_standardErrorTask).ConfigureAwait(false);
        }
        _process?.Dispose();
        _lifetime.Dispose();
    }

    private async Task PumpStandardOutputAsync(CancellationToken cancellationToken)
    {
        var process = _process
            ?? throw new InvalidOperationException(
                "Strategy process is unavailable.");
        try
        {
            while (await process.StandardOutput.ReadLineAsync(
                       cancellationToken).ConfigureAwait(false) is { } line)
            {
                StrategyMessageEnvelope message;
                try
                {
                    message = _codec.Decode(
                        line,
                        StrategyMessageDirection.StrategyToCore,
                        _manifest.StrategyId,
                        _manifest.Version);
                    if (!_eventIds.Add(message.EventId))
                    {
                        throw new StrategyProtocolException(
                            "Duplicate strategy event ID.");
                    }
                }
                catch (StrategyProtocolException exception)
                {
                    State = StrategyRuntimeState.Rejected;
                    Log(
                        ApplicationLogLevel.Error,
                        "Malformed strategy output rejected.",
                        null,
                        null,
                        new Dictionary<string, string>
                        {
                            ["reason"] = SensitiveDataRedactor.Redact(
                                exception.Message)
                        });
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                    return;
                }

                if (message.MessageType == "heartbeat")
                {
                    LastHeartbeat = message.Timestamp;
                }
                if (message.MessageType == "ready")
                {
                    State = StrategyRuntimeState.Ready;
                }
                else if (message.MessageType == "cycle_complete")
                {
                    State = StrategyRuntimeState.Running;
                }
                _messageHandler(message);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private async Task PumpStandardErrorAsync(CancellationToken cancellationToken)
    {
        var process = _process
            ?? throw new InvalidOperationException(
                "Strategy process is unavailable.");
        try
        {
            while (await process.StandardError.ReadLineAsync(
                       cancellationToken).ConfigureAwait(false) is { } line)
            {
                var bounded = line.Length <= MaximumErrorLineCharacters
                    ? line
                    : line[..MaximumErrorLineCharacters];
                Log(
                    ApplicationLogLevel.Warning,
                    SensitiveDataRedactor.Redact(bounded),
                    null,
                    null,
                    new Dictionary<string, string>
                    {
                        ["stream"] = "stderr",
                        ["truncated"] =
                            (line.Length > MaximumErrorLineCharacters)
                            .ToString()
                            .ToLowerInvariant()
                    });
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private void Log(
        ApplicationLogLevel level,
        string message,
        string? correlationId,
        string? cycleId,
        IReadOnlyDictionary<string, string> context)
    {
        _logHandler(new ApplicationLogEntry(
            Guid.NewGuid().ToString("D"),
            DateTimeOffset.UtcNow,
            level,
            "StrategyRuntime",
            message,
            correlationId,
            context)
        {
            StrategyId = _manifest.StrategyId,
            CycleId = cycleId
        });
    }

    private static async Task IgnoreCancellation(Task task)
    {
        try
        {
            await task.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
    }
}
