[CmdletBinding()]
param(
    [string]$ExecutablePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $projectRoot "dist\Cytisus-Trading-1.1.3-win11-x64.exe"
}

$resolvedExecutable = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
    throw "Prompt 4 smoke executable was not found: $resolvedExecutable"
}

$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$smokeRoot = Join-Path $systemTemp ("cytisus-prompt4-" + [System.Guid]::NewGuid().ToString("N"))
$resolvedSmokeRoot = [System.IO.Path]::GetFullPath($smokeRoot)
if (-not $resolvedSmokeRoot.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Prompt 4 smoke path is outside the system temporary directory."
}

try {
    New-Item -ItemType Directory -Path $resolvedSmokeRoot | Out-Null
    $process = Start-Process `
        -FilePath $resolvedExecutable `
        -ArgumentList @("--prompt4-smoke", $resolvedSmokeRoot) `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Prompt 4 smoke failed with exit code $($process.ExitCode)."
    }
    Write-Output "Prompt 4 targeted research smoke passed."
} finally {
    if (Test-Path -LiteralPath $resolvedSmokeRoot) {
        Remove-Item -LiteralPath $resolvedSmokeRoot -Recurse -Force
    }
}
