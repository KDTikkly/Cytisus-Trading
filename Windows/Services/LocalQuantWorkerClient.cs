using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace CytisusTrading.Windows;

public interface ILocalQuantWorkerClient
{
    Task<JsonDocument> SendAsync(
        string pythonExecutablePath,
        string workerScriptPath,
        string rootDirectory,
        object request,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

public sealed class LocalQuantWorkerClient : ILocalQuantWorkerClient
{
    private const int MaximumResponseCharacters = 1_048_576;

    public async Task<JsonDocument> SendAsync(
        string pythonExecutablePath,
        string workerScriptPath,
        string rootDirectory,
        object request,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        ValidateExecutable(pythonExecutablePath);
        ValidateWorkerScript(workerScriptPath);
        Directory.CreateDirectory(rootDirectory);

        var startInfo = new ProcessStartInfo
        {
            FileName = Path.GetFullPath(pythonExecutablePath),
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetFullPath(rootDirectory)
        };
        startInfo.ArgumentList.Add(Path.GetFullPath(workerScriptPath));
        startInfo.ArgumentList.Add("--root");
        startInfo.ArgumentList.Add(Path.GetFullPath(rootDirectory));
        startInfo.ArgumentList.Add("--stdio");

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Unable to start the local Quant Worker.");
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        linked.CancelAfter(timeout);

        var line = JsonSerializer.Serialize(
            request,
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
            });
        await process.StandardInput.WriteLineAsync(line.AsMemory(), linked.Token);
        await process.StandardInput.FlushAsync(linked.Token);
        var response = await process.StandardOutput.ReadLineAsync(linked.Token)
            ?? throw new InvalidDataException("The local Quant Worker returned no response.");
        if (response.Length > MaximumResponseCharacters)
        {
            throw new InvalidDataException("The local Quant Worker response exceeded the limit.");
        }

        try
        {
            await process.StandardInput.WriteLineAsync(
                "{\"id\":\"stop\",\"method\":\"Stop\",\"params\":{}}"
                    .AsMemory(),
                linked.Token);
            await process.StandardInput.FlushAsync(linked.Token);
            await process.WaitForExitAsync(linked.Token);
        }
        catch (OperationCanceledException)
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException("The local Quant Worker request timed out.");
        }

        return JsonDocument.Parse(response);
    }

    public static void ValidateExecutable(string path)
    {
        if (string.IsNullOrWhiteSpace(path) ||
            !Path.IsPathFullyQualified(path) ||
            !File.Exists(path))
        {
            throw new InvalidOperationException(
                "Select and approve a full path to a Python interpreter.");
        }
    }

    public static void ValidateWorkerScript(string path)
    {
        if (string.IsNullOrWhiteSpace(path) ||
            !Path.IsPathFullyQualified(path) ||
            !File.Exists(path) ||
            !string.Equals(Path.GetFileName(path), "quant_worker.py", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("The Quant Worker script path is invalid.");
        }
    }
}
