# Cytisus-Trading

<p align="center">
  <img src="Resources/ProductIcon-iOS27.png" width="220" alt="Cytisus-Trading product icon">
</p>

Cytisus-Trading is a local desktop front end for automated quantitative operations. It is not a manual trading terminal.

## v1.1 implementation status

Version 1.1.0 is in progress. Prompt 1 establishes cross-platform contracts, native application boundaries, deterministic fixtures, and local persistence foundations.

Currently available:

- Native macOS SwiftUI and Windows 11 WPF applications.
- Offline fixture mode with deterministic factor data.
- Fixture-backed factor-governance demonstrations.
- Matching platform domain identifiers.
- Local non-sensitive settings persistence.
- Local application-log and audit-event persistence.
- Schema-version and migration foundations.
- Shared JSON schemas, fixtures, and protocol documents.
- English-only ASCII repository validation.

Not yet available:

- Longbridge CLI integration or market collection.
- Local strategy-process execution.
- Factor DSL execution or factor search.
- Portfolio allocation.
- Paper or Live broker execution.
- Broker order submission.
- Manual order entry.

`Live` is defined as a contract identifier only. Live execution is unavailable and no UI path can submit an order.

## Native desktop editions

- macOS 14 or later: SwiftUI Universal 2 app distributed as `Cytisus-Trading-1.1.0-universal.dmg`.
- Windows 11 x64: self-contained WPF app distributed as `Cytisus-Trading-1.1.0-win11-x64.exe`.

Both applications start without Longbridge CLI, a network connection, an account, or credentials.

## Architecture

Shared behavior contracts:

```text
docs/
schemas/
fixtures/
```

macOS boundaries:

```text
Sources/App/
Sources/UI/
Sources/Domain/
Sources/Services/
Sources/Persistence/
Sources/Logging/
```

Windows boundaries:

```text
Windows/Domain/
Windows/Services/
Windows/Persistence/
Windows/Logging/
Windows/ViewModels/
Windows/Views/
```

The platforms do not share a compiled runtime. They share schema definitions, fixture inputs, protocol documents, stable identifiers, and equivalent native implementations.

## Shared contracts

- [v1.1 PDM](docs/PDM-v1.1.md)
- [Implementation prompt series](docs/CODEX-v1.1-PROMPT-SERIES.md)
- [Strategy protocol](docs/STRATEGY-PROTOCOL.md)
- [Factor DSL](docs/FACTOR-DSL.md)
- [Longbridge integration boundary](docs/LONGBRIDGE-INTEGRATION.md)

## Install on macOS

1. Download `Cytisus-Trading-1.1.0-universal.dmg`.
2. Open the DMG.
3. Drag `Cytisus-Trading.app` into Applications.
4. Open Cytisus-Trading from Applications.

The public DMG uses ad hoc signing unless release signing variables are supplied. If macOS blocks the first launch, open System Settings, select Privacy & Security, verify the source, and choose Open Anyway. Only run a build from a source you trust.

## Install on Windows 11

1. Download `Cytisus-Trading-1.1.0-win11-x64.exe`.
2. Run the executable directly.

The Windows executable is self-contained and does not require a separate .NET installation. Unsigned builds can trigger Microsoft Defender SmartScreen. Verify the release source and checksum before running the file.

## Build the macOS DMG

Install Xcode Command Line Tools, then run:

```bash
chmod +x tools/build_dmg.sh
tools/build_dmg.sh
```

Output:

```text
dist/Cytisus-Trading-1.1.0-universal.dmg
```

For Developer ID signing and Apple notarization:

```bash
DEVELOPER_ID_APPLICATION_IDENTITY="Developer ID Application: Organization (TEAMID)" \
NOTARY_PROFILE="cytisus-notary" \
tools/build_dmg.sh
```

## Build the Windows 11 executable

Install the .NET 8 SDK on Windows 11, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_win11.ps1
```

Output:

```text
dist/Cytisus-Trading-1.1.0-win11-x64.exe
```

## Focused foundation checks

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_ascii.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_json.ps1
```

The Windows application supports a targeted persistence and audit-event smoke mode through `--foundation-smoke`.

## Privacy and security

- No network requests in Prompt 1.
- No Longbridge process invocation in Prompt 1.
- No identity, account, position, order, or profit-and-loss data.
- No tokens, credentials, certificates, or authorization output.
- No Live execution.
- Non-sensitive settings, operational logs, and audit events are stored locally.
- Factor demo state resets deterministically from repository fixtures.

See [PRIVACY.md](PRIVACY.md) and [SANITIZATION.json](SANITIZATION.json).
