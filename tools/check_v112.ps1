param(
    [Parameter(Mandatory = $true)]
    [string]$PythonExecutablePath,
    [string]$ExecutablePath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$smokeBase = Join-Path $repoRoot "build\v112-smoke"
[System.IO.Directory]::CreateDirectory($smokeBase) | Out-Null
$workerRoot = Join-Path $smokeBase (
    "cytisus-worker-" + [Guid]::NewGuid().ToString("N"))
$studioRoot = ""

try {
    if (-not [System.IO.Path]::IsPathRooted($PythonExecutablePath) -or
        -not (Test-Path -LiteralPath $PythonExecutablePath -PathType Leaf)) {
        throw "PythonExecutablePath must be an existing absolute file path."
    }

    & $PythonExecutablePath (Join-Path $repoRoot "Worker\quant_worker.py") `
        --root $workerRoot `
        --self-test
    if ($LASTEXITCODE -ne 0) {
        throw "Quant Worker self-test failed."
    }

    if ($ExecutablePath) {
        $studioRoot = Join-Path $smokeBase (
            "cytisus-v112-" + [Guid]::NewGuid().ToString("N"))
        & $ExecutablePath --v112-smoke $studioRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Windows v1.1.2 smoke failed."
        }
    }
}
finally {
    if (Test-Path -LiteralPath $workerRoot) {
        Remove-Item -LiteralPath $workerRoot -Recurse -Force
    }
    if ($studioRoot -and (Test-Path -LiteralPath $studioRoot)) {
        Remove-Item -LiteralPath $studioRoot -Recurse -Force
    }
}
