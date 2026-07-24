# Cytisus-Trading

<p align="center">
  <img src="Resources/ProductIcon-iOS27.png" width="220" alt="Cytisus-Trading product icon">
</p>

Cytisus-Trading is a fully offline desktop demonstration for quantitative research and factor-governance reviews. It presents a clear visual workflow for moving a factor from candidate evaluation through shadow review and activation, followed by probation, retirement, or quarantine when the evidence changes.

The app uses a dark glass visual system and contains only built-in sanitized sample data. It never connects to a broker, reads an account, requests live market data, or submits an order. It is suitable for product demonstrations, rule discussions, and interface reviews.

## Desktop editions

Two native desktop editions are maintained:

- macOS 14 or later: Universal 2 app distributed as `Cytisus-Trading-1.0.0-universal.dmg`.
- Windows 11: 64-bit, self-contained WPF app distributed as `Cytisus-Trading-1.0.0-win11-x64.exe`.

Both editions use the same English-only sample content and implement the same four work areas:

- Overview
- Factor Lifecycle
- Strategy Lab
- Privacy and Sanitization

## Features

- Review active factors, weighted coverage, the shadow queue, and a sample strategy path.
- Inspect IC, IR, coverage, weight, OOS evidence windows, and governance status.
- Simulate factor promotion, probation, and retirement.
- Adjust risk budget, minimum coverage, and factor-weight limits.
- Review explicit privacy, sanitization, and release boundaries.
- Reset all in-memory changes by restarting the app or selecting Reset.

This project does not provide live trading capability, investment advice, or any promise of returns.

## Install on macOS

1. Download `Cytisus-Trading-1.0.0-universal.dmg`.
2. Open the DMG.
3. Drag `Cytisus-Trading.app` into Applications.
4. Open Cytisus-Trading from Applications.

The public DMG uses ad hoc signing unless release signing variables are supplied. If macOS blocks the first launch, open System Settings, select Privacy & Security, verify the source, and choose Open Anyway. Only run a build from a source you trust.

## Install on Windows 11

1. Download `Cytisus-Trading-1.0.0-win11-x64.exe`.
2. Run the executable directly.

The Windows release is self-contained and does not require a separate .NET installation. Unsigned public builds can trigger Microsoft Defender SmartScreen. Verify the release source and checksum before choosing Run anyway.

## Build the macOS DMG

Install Xcode Command Line Tools, then run:

```bash
chmod +x tools/build_dmg.sh
tools/build_dmg.sh
```

Output:

```text
dist/Cytisus-Trading-1.0.0-universal.dmg
```

For Developer ID signing and Apple notarization:

```bash
DEVELOPER_ID_APPLICATION_IDENTITY="Developer ID Application: Organization (TEAMID)" \
NOTARY_PROFILE="cytisus-notary" \
tools/build_dmg.sh
```

Install a valid `Developer ID Application` certificate in the login keychain and save a `notarytool` profile before using these variables. Never commit passwords, tokens, certificates, or private keys.

## Build the Windows 11 executable

Install the .NET 8 SDK on Windows 11, then run:

```powershell
pwsh -File tools/build_win11.ps1
```

Output:

```text
dist/Cytisus-Trading-1.0.0-win11-x64.exe
```

The build is published as a self-contained, single-file WPF executable for `win-x64`.

## English-only validation

Run the repository text check before release:

```powershell
pwsh -File tools/check_ascii.ps1
```

The check fails if a tracked project text file contains a character outside printable ASCII, tabs, or standard line endings.

## Privacy and security

- No network requests
- No identity data
- No account, position, order, or profit-and-loss data
- No tokens, certificates, or environment variables
- No persisted demo state by default
- No trade-execution capability

See [PRIVACY.md](PRIVACY.md) and [SANITIZATION.json](SANITIZATION.json) for the complete release boundary.
