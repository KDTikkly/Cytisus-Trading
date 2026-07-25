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
$version = "1.1.0"
$runtime = "win-$Architecture"
$buildRoot = Join-Path $projectRoot "build\win11-$Architecture"
$publishDirectory = Join-Path $buildRoot "publish"
$distDirectory = Join-Path $projectRoot "dist"
$artifactName = "Cytisus-Trading-$version-win11-$Architecture.exe"
$artifactPath = Join-Path $distDirectory $artifactName
$installerScript = Join-Path $projectRoot "Windows\Installer\Cytisus-Trading.iss"
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

$signingCertificate = [Environment]::GetEnvironmentVariable(
    "WINDOWS_SIGNING_CERTIFICATE_BASE64"
)
$certificate = $null
$timestampUrl = $null
if (-not [string]::IsNullOrWhiteSpace($signingCertificate)) {
    $signingPassword = [Environment]::GetEnvironmentVariable(
        "WINDOWS_SIGNING_CERTIFICATE_PASSWORD"
    )
    $timestampUrl = [Environment]::GetEnvironmentVariable(
        "WINDOWS_SIGNING_TIMESTAMP_URL"
    )
    if ([string]::IsNullOrWhiteSpace($timestampUrl)) {
        $timestampUrl = "http://timestamp.digicert.com"
    }
    $certificateBytes = [Convert]::FromBase64String($signingCertificate)
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $certificateBytes,
        $signingPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
    )
}

function Set-CytisusSignature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory = $true)]
        [string]$TimestampUrl
    )

    $signature = Set-AuthenticodeSignature `
        -FilePath $Path `
        -Certificate $Certificate `
        -HashAlgorithm SHA256 `
        -TimestampServer $TimestampUrl
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Authenticode signing failed with status $($signature.Status)."
    }
}

if ($null -ne $certificate) {
    Set-CytisusSignature `
        -Path $publishedExecutable `
        -Certificate $certificate `
        -TimestampUrl $timestampUrl
}

$isccCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
)
$iscc = $isccCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if ($null -ne $iscc) {
    & $iscc `
        "/DSourceExecutable=$publishedExecutable" `
        "/DOutputDirectory=$distDirectory" `
        "/DArtifactBaseName=$([System.IO.Path]::GetFileNameWithoutExtension($artifactName))" `
        $installerScript
    if ($LASTEXITCODE -ne 0) {
        throw "Windows installer build failed with exit code $LASTEXITCODE."
    }
} else {
    Write-Warning (
        "Inno Setup 6 was not found. Creating a development single-file " +
        "artifact without the release install wizard."
    )
    Copy-Item -LiteralPath $publishedExecutable -Destination $artifactPath -Force
}

if ($null -ne $certificate) {
    Set-CytisusSignature `
        -Path $artifactPath `
        -Certificate $certificate `
        -TimestampUrl $timestampUrl
    Write-Output "Authenticode signatures: application and installer valid"
} else {
    Write-Warning "No Authenticode signing certificate was configured."
}

$hash = Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256
Write-Output "Windows 11 artifact: $artifactPath"
Write-Output "SHA256: $($hash.Hash)"
