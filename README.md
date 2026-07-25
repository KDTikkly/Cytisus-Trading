# Cytisus-Trading

<p align="center">
  <img src="Resources/ProductIcon-iOS27.png" width="220" alt="Cytisus-Trading product icon">
</p>

Cytisus-Trading is a local desktop front end for automated quantitative operations. It is not a manual trading terminal.

## v1.1.5 implementation status

Version 1.1.5 fixes contrast for native Windows controls and retains the v1.1.4 startup repair. Local Paper remains independent, and Live broker submission remains intentionally unavailable.

Currently available:

- Native macOS SwiftUI and Windows 11 WPF applications.
- Offline fixture mode with deterministic factor data.
- Fixture-backed factor-governance demonstrations.
- Matching platform domain identifiers.
- Local non-sensitive settings persistence.
- Local application-log and audit-event persistence.
- Schema-version and migration foundations.
- Shared JSON schemas, fixtures, and protocol documents.
- Capability-aware Longbridge CLI discovery and read-only process controls.
- Missing, Installed, Authorizing, Unauthenticated, RefreshPending, Expired, ReadyPaper, ReadyLive, ReadyUnknownChannel, Degraded, and UpdateRequired CLI states.
- Device authorization, one-time authorization-code login, explicit logout and update controls, and exact `lb_papertrading` classification.
- Canonical typed mappings for `auth status`, `check`, `quote`, `kline history`, `security-list`, and `positions` with `--format json`.
- Deterministic historical bars, current quote, market status, security list, and position fixtures.
- Point-in-time market metadata and idempotent local JSON caching.
- Daily universe inclusion, exclusion, and Reduce Only decisions.
- Native Data and Universe, Settings, and structured Logs screens.
- Official and third-party strategy registries with manifest and parameter-schema validation.
- Bounded no-shell strategy processes with NDJSON messaging, heartbeats, graceful shutdown, and structured observability.
- The official Cross-Sectional Multi-Factor fixture strategy in Local Paper mode.
- Schema-generated parameter editing with Low, Medium, and High risk governance, versioning, audit history, and safe-boundary activation.
- A Global Live Lock that is OFF by default and bounded Live-authorization validation.
- A process-free rejecting Live adapter; v1.1.3 does not enable Live submission.
- Native Dashboard and Strategies screens with health, cycle, signal, target, intent, and runtime state.
- Typed deterministic Factor DSL implementations on both native platforms.
- Multi-task Alpha, Risk, Regime, Liquidity, and Execution factor contracts.
- A bounded deterministic beam search with nine economic seed families and neighboring-horizon validation.
- An append-only local Trial Registry that retains rejected candidates.
- Global quarantine, strategy-specific lifecycle state, risk contraction, retirement, and recovery guards.
- Deterministic Trend, Range, High Volatility, and Crisis probabilities with uncertainty.
- Dynamic strategy capital budgets with capped alpha tilt, correlation, drawdown, capacity, liquidity, and turnover controls.
- Native factor research, regime, and allocator explanations.
- A sole execution gateway with ordered risk gates, duplicate-intent rejection, and audit records.
- A deterministic Local Paper Broker with accepted, rejected, full-fill, partial-fill, expiry, slippage, and fee behavior.
- Internal netting with separate Internal Transfer records and residual broker demand.
- Deterministic partial-fill allocation, minimum-fill handling, full-or-zero behavior, and Allocation Shortfall records.
- Per-strategy virtual ledgers with ownership, cost basis, realized and unrealized profit and loss, capital usage, and risk contribution.
- Fixture-based reconciliation, persistent critical risk events, symbol risk blocks, and non-trading diagnostics.
- Native read-only Portfolio and Execution screens on macOS and Windows.
- Native Model Providers settings on macOS and Windows.
- Multiple OpenAI-compatible, Anthropic-compatible, and Gemini-compatible provider profiles with custom Base URLs.
- macOS Keychain and Windows CurrentUser DPAPI secret storage with no plaintext API-key database column.
- Provider discovery where supported, manual model entry, user-triggered connectivity tests, and sanitized result categories.
- One Ready primary model and ordered Ready fallback models with disabled-provider skipping.
- A fixture-only read-only Quote, MarketStatus, and SymbolLookup model-tool boundary that rejects trading tools.
- A separate local Quant Worker with typed JSON messages, job lifecycle, cancellation, logs, artifacts, checkpoints, and crash isolation.
- An explicitly selected Python-interpreter boundary; Cytisus never silently chooses or installs a Python runtime.
- Truthful CPU, Metal, CUDA, ROCm, OpenVINO, and NPU discovery with deterministic CPU fallback.
- A narrow C++ CPU core with a stable C ABI for common quantitative primitives.
- Versioned algorithm projects and allowlisted, cost-bounded Agent patch proposals.
- Deterministic backtest, walk-forward, parameter-search, training, checkpoint, ONNX, and execution-simulation job contracts.
- Synthetic Longbridge authentication, account-channel, and mapping fixtures.
- SuggestOnly, ConfirmEveryOrder, and BoundedAutonomy Agent-order authorization contracts.
- A native Algorithm Studio surface on macOS and Windows.
- English-only ASCII repository validation.

Not yet available:

- Real broker execution.
- Broker order submission.
- Real Longbridge Paper or Live broker order submission.
- Manual order entry.
- Chat, assistants, knowledge bases, prompt libraries, and model benchmarking.
- Provider import, export, billing, key rotation, or automatic cost routing.
- Guaranteed compatibility with future, unverified Longbridge Terminal response shapes.
- Verified optional accelerator execution in environments where its runtime provider is not installed.
- A general-purpose code editor, shell, arbitrary filesystem Agent access, or autonomous broker access.

`Live` can be selected only when the Global Live Lock and a bounded authorization both pass validation. The Live Longbridge adapter still rejects every submission without starting a process, and no UI path can create a manual order. Local Paper does not require Longbridge CLI, authentication, connectivity, or an account.

## Native desktop editions and packaging

The source version is 1.1.5. The release workflow builds and publishes both native desktop artifacts:

- macOS 14 or later: SwiftUI Universal 2 app distributed as `Cytisus-Trading-1.1.5-universal.dmg`.
- Windows 11 x64: self-contained WPF app with an English install wizard distributed as `Cytisus-Trading-1.1.5-win11-x64.exe`.

Both applications start without Longbridge CLI, a network connection, an account, or credentials.
Fixture mode is the default. When fixture mode is disabled, Cytisus may invoke only a separately installed, user-authorized Longbridge CLI through its restricted read-only adapter.

## Optional Longbridge Terminal setup

Cytisus does not bundle or download Longbridge Terminal. Install it separately using an official command, then use Check Again or select the executable path in Settings.

macOS:

```text
brew install --cask longbridge/tap/longbridge-terminal
curl -sSL https://open.longbridge.cn/longbridge/longbridge-terminal/install | sh
```

Windows:

```text
iwr https://open.longbridge.cn/longbridge/longbridge-terminal/install.ps1 | iex
scoop install https://open.longbridge.cn/longbridge/longbridge-terminal/longbridge.json
```

Repository: [longbridge-terminal](https://github.com/longbridge/longbridge-terminal)

Longbridge Paper is ready only when CLI 0.20.0 or later reports the exact `lb_papertrading` channel and connectivity succeeds. Local Paper remains available in every CLI state.

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
- [v1.1.1 PDM](docs/PDM-v1.1.1.md)
- [v1.1.1 implementation prompt](docs/CODEX-v1.1.1-PROMPT.md)
- [Model-provider configuration and security](docs/MODEL-PROVIDERS.md)
- [v1.1.2 PDM](docs/PDM-v1.1.2.md)
- [v1.1.2 implementation prompt](docs/CODEX-v1.1.2-PROMPT.md)
- [Local Quant Runtime](docs/LOCAL-QUANT-RUNTIME.md)
- [Compute backends](docs/COMPUTE-BACKENDS.md)
- [Algorithm projects](docs/ALGORITHM-PROJECTS.md)
- [ONNX models](docs/ONNX-MODELS.md)
- [Agent development](docs/AGENT-DEVELOPMENT.md)
- [Agent order authorization](docs/AGENT-ORDER-AUTHORIZATION.md)
- [v1.1.3 PDM](docs/PDM-v1.1.3.md)
- [v1.1.3 implementation prompt](docs/CODEX-v1.1.3-PROMPT.md)
- [Longbridge authentication troubleshooting](docs/LONGBRIDGE-AUTH-TROUBLESHOOTING.md)

## Install on macOS

1. Download `Cytisus-Trading-1.1.5-universal.dmg`.
2. Open the DMG.
3. Drag `Cytisus-Trading.app` into Applications.
4. Open Cytisus-Trading from Applications.

The public DMG uses ad hoc signing unless release signing variables are supplied. If macOS blocks the first launch, open System Settings, select Privacy & Security, verify the source, and choose Open Anyway. Only run a build from a source you trust.

## Install on Windows 11

1. Download `Cytisus-Trading-1.1.5-win11-x64.exe`.
2. Run the installer and choose the destination.
3. Launch Cytisus-Trading from the Start menu.

The installed Windows application is self-contained and does not require a separate .NET installation. The release workflow supports Authenticode signing when repository signing secrets are configured. Unsigned builds can trigger Microsoft Defender SmartScreen; a clean source tree alone cannot establish Microsoft reputation.

## Prepared macOS packaging

Install Xcode Command Line Tools, then run:

```bash
chmod +x tools/build_dmg.sh
tools/build_dmg.sh
```

The release workflow runs this script on macOS. Its output name is:

```text
dist/Cytisus-Trading-1.1.5-universal.dmg
```

For Developer ID signing and Apple notarization:

```bash
DEVELOPER_ID_APPLICATION_IDENTITY="Developer ID Application: Organization (TEAMID)" \
NOTARY_PROFILE="cytisus-notary" \
tools/build_dmg.sh
```

## Prepared Windows 11 packaging

Install the .NET 8 SDK and Inno Setup 6 on Windows 11, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_win11.ps1
```

The release workflow runs this script on Windows. Its output name is:

```text
dist/Cytisus-Trading-1.1.5-win11-x64.exe
```

With Inno Setup present, this artifact is a standard English install wizard containing the self-contained single-file application. Without Inno Setup, the local script emits a development single-file fallback. Release CI installs Inno Setup and always builds the wizard.

Authenticode is optional and requires repository-controlled certificate secrets. Configure `WINDOWS_SIGNING_CERTIFICATE_BASE64`, `WINDOWS_SIGNING_CERTIFICATE_PASSWORD`, and optionally `WINDOWS_SIGNING_TIMESTAMP_URL` to sign both the installed application and installer. Signing is required for publisher identity, but Microsoft SmartScreen reputation is established externally over time and cannot be guaranteed by source code.

## Focused checks

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_ascii.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_json.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_prompt2.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_prompt3.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_prompt4.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_prompt5.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_model_providers.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_v112.ps1 -PythonExecutablePath C:\Path\To\Approved\python.exe
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_v113.ps1
```

The Prompt 5 smoke is deliberately small: one complete strategy-intent-to-Local-Paper-fill cycle, one internal-netting case, one partial-fill allocation case, one reconciliation case, one assertion that unavailable Longbridge CLI does not block Local Paper, and one assertion that the Live adapter remains rejecting.

## Privacy and security

- Fixture mode makes no network request and invokes no CLI.
- Local CLI mode never reads or stores Longbridge token files. It persists only sanitized environment, channel, check time, CLI version, and permission summaries.
- Optional broker-position snapshots are used only for Reduce Only universe behavior and are not cached.
- No tokens, credentials, certificates, or authorization output.
- Local Paper never invokes Longbridge CLI or a Live adapter.
- Live broker submission remains unavailable and process-free.
- Registered strategy manifests and state, Local Paper execution records, virtual ledgers, parameter history, bounded Live authorizations, factor definitions and trials, non-sensitive settings, market cache records, universe snapshots, operational logs, and audit events are stored locally.
- Factor demo state resets deterministically from repository fixtures.
- Model API keys remain in operating-system secure storage and never enter the application database, logs, Longbridge CLI arguments, or Longbridge environment.
- Model-provider authorization is separate from Longbridge OAuth. Users supply and pay their selected provider directly.
- The Quant Worker receives project jobs and artifacts only. It receives no broker secret or account-token path and cannot submit orders.
- Synthetic account fixtures and Agent authorizations contain no real account identifier or credential.

See [PRIVACY.md](PRIVACY.md) and [SANITIZATION.json](SANITIZATION.json).
