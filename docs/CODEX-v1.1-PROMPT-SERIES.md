# Cytisus v1.1 Codex Prompt Series

Status: Active implementation plan
Target version: 1.1.0

This document preserves the five-pass implementation sequence for Cytisus v1.1. Each pass must begin from the repository state produced by the prior pass. Later-pass capabilities must not be implemented early.

## Prompt 1: Foundation, Documentation, and Cross-platform Contracts

```text
You are working in KDTikkly/Cytisus-Trading.

This is the first of five implementation passes for Cytisus v1.1. Work only on the foundation described below. Do not prematurely implement Longbridge market collection, strategy execution, factor search, portfolio allocation, or broker order submission.

Required context

The repository currently contains:

- A native macOS SwiftUI application under Sources/.
- A native Windows 11 WPF application under Windows/.
- Separate in-memory demo models.
- macOS and Windows release build scripts.
- An ASCII-only repository text validator.
- A GitHub Actions workflow that builds both desktop artifacts.

Goals

- Add the supplied English ASCII-only PDM as docs/PDM-v1.1.md.
- Add this five-prompt series as docs/CODEX-v1.1-PROMPT-SERIES.md.
- Add concise architecture documents:
  - docs/STRATEGY-PROTOCOL.md
  - docs/FACTOR-DSL.md
  - docs/LONGBRIDGE-INTEGRATION.md
- Upgrade all product and artifact version references from 1.0.0 to 1.1.0.
- Preserve SwiftUI on macOS, WPF on Windows, Universal 2 DMG, Windows self-contained single-file executable, and English-only ASCII validation.
- Refactor both applications so views no longer own all business state.
- Introduce equivalent platform-specific domain and service boundaries.
- Add shared JSON schemas and deterministic fixture directories.
- Add persistence interfaces, migration/version models, application log models, and audit-event models.
- Keep the existing offline demo usable through repository or fixture-backed state.

Platform architecture

Do not replace either native UI framework. Do not introduce Electron, Flutter, React Native, Avalonia, a browser shell, Rust, Go, or a new shared runtime merely to share code.

Use shared behavior contracts through JSON schemas, fixture files, protocol documents, and matching domain identifiers and state values.

Recommended shared paths:

- docs/
- schemas/
- fixtures/

Recommended schemas:

- strategy-manifest.schema.json
- strategy-message.schema.json
- factor-definition.schema.json
- factor-trial.schema.json
- live-authorization.schema.json
- audit-event.schema.json

macOS refactor

Create a maintainable split such as Sources/App/, Sources/UI/, Sources/Domain/, Sources/Services/, Sources/Persistence/, and Sources/Logging/. The exact layout may differ if the current direct swiftc build makes another layout safer. Move demo factor state transitions and settings out of SwiftUI views.

Windows refactor

Split the current large WPF model and window responsibilities into Windows/Domain/, Windows/Services/, Windows/Persistence/, Windows/ViewModels/, and Windows/Views/. The exact layout may differ if needed, but do not leave all logic in one large ViewModel or code-behind file.

Persistence foundation

Implement lightweight persistent-store interfaces and schema-version handling. You may use SQLite without an ORM. If full database implementation would destabilize this first pass, create a durable implementation for settings, logs, and audit events and leave explicit interfaces for later stores. Do not store credentials.

Required state identifiers

- PaperOnly
- Live
- Healthy
- Degraded
- Unhealthy
- Candidate
- Shadow
- Active
- Reduced
- Probation
- Retired
- Quarantined
- StrategyIntent
- RiskDecision
- InternalTransfer
- BrokerOrder
- BrokerFill
- VirtualAllocation
- AllocationShortfall

UI scope for this pass

Keep the current UI functional. You may rename the existing sections toward the v1.1 product language, but do not build all final pages yet. The application must still start in offline fixture mode.

Testing and token discipline

Do not create a broad test suite. Perform only ASCII validation, JSON fixture/schema syntax validation, a targeted persistence or audit-event smoke check, and a build for the platform available in the current environment. Do not repeatedly attempt unavailable macOS or Windows builds. If the current environment cannot build one platform, state that honestly and rely on the final cross-platform workflow in Prompt 5. Do not add UI snapshot tests or coverage tooling.

Documentation accuracy

Update README.md, INSTALL.txt, PRIVACY.md, and SANITIZATION.json. At this stage, documentation must clearly say that v1.1 implementation is in progress and that Live execution is not yet available. Do not falsely describe later-stage functions as completed.

Completion requirements

Before finishing, run the focused checks once, inspect tracked files for tokens, account data, and absolute user paths, commit with a focused message similar to "refactor: establish v1.1 cross-platform foundations", push the current branch, and do not force-push.
```

## Prompt 2: Longbridge Data and Universe

Read `docs/PDM-v1.1.md`, `docs/LONGBRIDGE-INTEGRATION.md`, and the shared schemas before implementation.

Implement only:

- Safe Longbridge CLI discovery and capability inspection.
- Argument-array process invocation with timeouts, cancellation, output limits, and redaction.
- Read-only JSON market-data access.
- Point-in-time market cache fields.
- Deterministic Longbridge fixtures.
- Daily universe snapshots.
- Data and Universe and Settings application state.

Do not implement strategy processes, factor search, allocation, or broker execution. Live must remain unavailable. Run only focused fixture parsing, adapter safety, persistence, ASCII, and available-platform build checks.

## Prompt 3: Strategy Runtime and Governance

Read `docs/PDM-v1.1.md` and `docs/STRATEGY-PROTOCOL.md` before implementation.

Implement only:

- Strategy manifest registry.
- Restricted NDJSON strategy-process transport.
- Heartbeat, health, lifecycle, and message validation.
- Official Paper Only sample strategy.
- Dynamic parameter definitions and risk-tiered activation.
- Global Live lock and bounded Live authorization models.
- Strategies, Dashboard, and Logs application behavior.

Live broker submission must remain disabled. Strategy processes must never receive broker credentials or direct Longbridge access. Run focused protocol, parameter-governance, fixture, persistence, ASCII, and available-platform build checks.

## Prompt 4: Quant Research and Allocation

Read `docs/PDM-v1.1.md` and `docs/FACTOR-DSL.md` before implementation.

Implement only:

- Multi-task factor definitions.
- Restricted Factor DSL parsing and deterministic evaluation.
- Bounded deterministic candidate search and Trial Registry.
- Factor validation and lifecycle governance.
- Probabilistic market-regime estimates.
- Dynamic strategy capital allocation with explanation output.
- Factor Governance UI behavior.

Do not submit broker orders. Do not add arbitrary code execution, unbounded search, or deep-learning dependencies. Run focused temporal-safety, deterministic search, lifecycle, allocation, ASCII, and available-platform build checks.

## Prompt 5: Execution, Ledger, Parity, and Release

Read all v1.1 protocol documents and schemas before implementation.

Implement:

- The sole execution gateway.
- Paper broker behavior.
- Tightly gated Live broker adapter.
- Mode, authorization, data-freshness, health, and risk checks.
- Internal netting and deterministic partial-fill allocation.
- Virtual ledgers, positions, and reconciliation.
- Portfolio and read-only Execution UI behavior.
- Final semantic parity for macOS and Windows.
- Final documentation and 1.1.0 release workflow.

No manual order entry may exist. Run the final focused safety scenarios and one complete cross-platform release workflow. Publish both the Universal 2 DMG and Windows 11 self-contained executable only after all required gates pass.
