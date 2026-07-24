[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$textExtensions = @(
    ".cs",
    ".csproj",
    ".config",
    ".gitattributes",
    ".gitignore",
    ".json",
    ".md",
    ".plist",
    ".ps1",
    ".sh",
    ".swift",
    ".txt",
    ".xaml",
    ".xml",
    ".yaml",
    ".yml"
)
$excludedPattern = '(^|[\\/])(\.git|\.swiftpm|\.vs|build|dist|bin|obj|DerivedData)([\\/]|$)'
$invalidPattern = '[^\x09\x0A\x0D\x20-\x7E]'
$failures = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $projectRoot -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($projectRoot.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ($relativePath -match $excludedPattern) {
        return
    }

    $extension = if ($_.Name -in @(".gitattributes", ".gitignore")) {
        $_.Name.ToLowerInvariant()
    } else {
        $_.Extension.ToLowerInvariant()
    }
    if ($textExtensions -notcontains $extension) {
        return
    }

    $content = [System.IO.File]::ReadAllText($_.FullName)
    $match = [System.Text.RegularExpressions.Regex]::Match($content, $invalidPattern)
    if (-not $match.Success) {
        return
    }

    $lineNumber = 1 + [System.Text.RegularExpressions.Regex]::Matches(
        $content.Substring(0, $match.Index),
        "`n"
    ).Count
    $codePoint = [int][char]$match.Value[0]
    $failures.Add(("{0}:{1} contains non-ASCII character U+{2:X4}" -f $relativePath, $lineNumber, $codePoint))
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "English-only validation failed."
}

Write-Output "English-only validation passed."
