[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$jsonFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($directory in @("schemas", "fixtures")) {
    $path = Join-Path $projectRoot $directory
    Get-ChildItem -LiteralPath $path -Recurse -File -Filter "*.json" |
        ForEach-Object { $jsonFiles.Add($_) }
}

$jsonFiles.Add((Get-Item -LiteralPath (Join-Path $projectRoot "SANITIZATION.json")))

foreach ($file in $jsonFiles) {
    try {
        [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json | Out-Null
    } catch {
        throw "Invalid JSON syntax in $($file.FullName): $($_.Exception.Message)"
    }
}

Write-Output ("JSON syntax validation passed for {0} files." -f $jsonFiles.Count)
