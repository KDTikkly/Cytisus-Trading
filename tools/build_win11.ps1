[CmdletBinding()]
param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $projectRoot "Windows\CytisusTrading.Windows.csproj"
$nugetConfig = Join-Path $projectRoot "NuGet.Config"
$version = "1.0.0"
$runtime = "win-$Architecture"
$buildRoot = Join-Path $projectRoot "build\win11-$Architecture"
$publishDirectory = Join-Path $buildRoot "publish"
$distDirectory = Join-Path $projectRoot "dist"
$artifactName = "Cytisus-Trading-$version-win11-$Architecture.exe"
$artifactPath = Join-Path $distDirectory $artifactName
$env:DOTNET_CLI_HOME = Join-Path $projectRoot "build\.dotnet-home"
$env:NUGET_PACKAGES = Join-Path $projectRoot "build\.nuget-packages"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "The .NET 8 SDK is required to build the Windows 11 edition."
}

& (Join-Path $PSScriptRoot "check_ascii.ps1")

if (Test-Path -LiteralPath $buildRoot) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null

& dotnet restore $projectFile --runtime $runtime --configfile $nugetConfig
if ($LASTEXITCODE -ne 0) {
    throw "Windows 11 restore failed with exit code $LASTEXITCODE."
}

$publishArguments = @(
    "publish",
    $projectFile,
    "--configuration", "Release",
    "--runtime", $runtime,
    "--self-contained", "true",
    "--no-restore",
    "--output", $publishDirectory,
    "-p:Version=$version",
    "-p:PublishSingleFile=true",
    "-p:IncludeNativeLibrariesForSelfExtract=true",
    "-p:DebugType=None",
    "-p:DebugSymbols=false"
)

& dotnet @publishArguments
if ($LASTEXITCODE -ne 0) {
    throw "Windows 11 publish failed with exit code $LASTEXITCODE."
}

$publishedExecutable = Join-Path $publishDirectory "CytisusTrading.exe"
if (-not (Test-Path -LiteralPath $publishedExecutable)) {
    throw "The published executable was not found at $publishedExecutable."
}

Copy-Item -LiteralPath $publishedExecutable -Destination $artifactPath -Force

$hash = Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256
Write-Output "Windows 11 artifact: $artifactPath"
Write-Output "SHA256: $($hash.Hash)"
