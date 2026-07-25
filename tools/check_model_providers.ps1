param(
    [string]$ExecutablePath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $projectRoot "Windows\bin\Release\net8.0-windows\CytisusTrading.exe"
}

if (-not (Test-Path -LiteralPath $ExecutablePath)) {
    throw "Model-provider smoke executable not found: $ExecutablePath"
}

$smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "cytisus-model-provider-smoke-" + [Guid]::NewGuid().ToString("N")
)

try {
    & $ExecutablePath --model-provider-smoke $smokeRoot
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Model-provider smoke failed with exit code $LASTEXITCODE."
    }
}
finally {
    if (Test-Path -LiteralPath $smokeRoot) {
        Remove-Item -LiteralPath $smokeRoot -Recurse -Force
    }
}
