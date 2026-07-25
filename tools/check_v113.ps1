param(
    [string]$ExecutablePath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "cytisus-v113-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not $ExecutablePath) {
        dotnet build (
            Join-Path $repoRoot "Windows\CytisusTrading.Windows.csproj") `
            -c Release `
            --no-restore
        if ($LASTEXITCODE -ne 0) {
            throw "Windows build failed."
        }
        $ExecutablePath = Join-Path $repoRoot (
            "Windows\bin\Release\net8.0-windows\CytisusTrading.exe")
    }
    if (-not [System.IO.Path]::IsPathRooted($ExecutablePath)) {
        $ExecutablePath = Join-Path $repoRoot $ExecutablePath
    }
    $resolvedExecutable = [System.IO.Path]::GetFullPath(
        [string]$ExecutablePath)
    if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
        throw "ExecutablePath must resolve to an existing file."
    }
    $process = Start-Process `
        -FilePath $resolvedExecutable `
        -ArgumentList @("--v113-smoke", $smokeRoot) `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Windows v1.1.3 smoke failed with exit code $($process.ExitCode)."
    }
    Write-Output "v1.1.3 targeted Longbridge smoke passed."
}
finally {
    if (Test-Path -LiteralPath $smokeRoot) {
        Remove-Item -LiteralPath $smokeRoot -Recurse -Force
    }
}
