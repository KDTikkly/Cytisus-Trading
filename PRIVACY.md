# Cytisus-Trading Privacy Statement

Cytisus-Trading 1.1.7 retains bounded Longbridge Terminal authentication, Paper-channel readiness, and local NVIDIA device discovery while clarifying network boundaries. Market-data fixtures remain the default, Local Paper is independent from Longbridge CLI, model providers, and the Quant Worker, and Live broker submission remains unavailable.

## Current behavior

- Market-data fixtures do not invoke Longbridge CLI. Enabled model APIs and CLI access may use the network; quantitative CPU/GPU compute stays local.
- Local CLI mode invokes only capability-advertised read-only data operations. Any CLI network or authorization activity belongs to the separately installed CLI.
- The app never reads Longbridge token files or asks for a broker secret.
- A read-only broker-position snapshot may be held in memory to mark excluded holdings Reduce Only. It is not cached.
- The repository and release contain no tokens, API keys, certificates, authorization codes, or account bindings.
- Users may enter their own model API key. macOS stores it in Keychain Services and Windows stores it with CurrentUser DPAPI protection.
- The model-provider database stores only a secret reference. It has no plaintext API-key column.
- Model-provider authorization is separate from Longbridge OAuth. Model keys are never passed to Longbridge CLI or a strategy.
- Provider requests are built in process. API keys are never placed in command-line arguments.
- Provider test events and UI errors store only sanitized categories, messages, and optional latency.
- Model providers may charge the user under the provider's own terms. Cytisus does not supply or resell model access.
- Repository fixtures contain only fictional market, factor, and position data.
- Official and registered third-party strategies run as explicit local processes without a shell. They do not receive credentials or direct CLI access.
- Strategy messages are size-bounded, typed, and checked for prohibited sensitive payload keys before they are logged or accepted.
- Local Paper intents, simulated orders, fills, allocations, and virtual positions remain local and cannot reach Longbridge CLI or the Live adapter.
- The Global Live Lock is off by default. A bounded local authorization record is required for Live selection, but the Live adapter rejects without starting a process.
- The app has no real broker order, discretionary cancellation, fund-management, or account-configuration capability.
- Factor candidates are evaluated locally from one normalized source snapshot. Candidate search does not invoke Longbridge CLI, a network service, an LLM, or executable factor code.
- Factor definitions and all trial results, including failures, are stored locally. They contain dataset and universe versions but no broker credentials or account identifiers.
- Regime and capital-allocation results feed only the deterministic Local Paper execution gateway in this release.
- Live broker submission is unavailable.
- The Quant Worker receives typed project jobs and artifact paths under its local root. It receives no broker token, account credential, or direct order capability.
- A Python interpreter must be explicitly selected and validated. Cytisus does not install Python or silently choose an arbitrary system interpreter.
- Accelerator status is based on discovered local runtime providers. Optional package discovery does not install or download software.
- Agent project patches are limited to allowlisted relative project files and a configured token-cost ceiling. They cannot use a shell, read arbitrary files, or access secrets.
- Longbridge device and authorization-code login invoke only allowlisted commands. One-time codes are cleared after every outcome and are never persisted or logged.
- Authentication persistence contains only sanitized account environment, account channel, status-check time, CLI version, and permission summaries.
- Agent order authorizations contain limits and allowlists but no broker credential. An authorized intent must still pass the existing risk and execution gateways.

## Local persistence

The v1.1 foundation stores only:

- Non-sensitive interface settings.
- Schema and migration version information.
- Operational application logs.
- Audit events for local fixture actions.
- Model-provider metadata, model capability records, primary and fallback assignments, and sanitized provider-test events.
- Strategy manifests and runtime state.
- Parameter-change history and rollback version references.
- Bounded Live-authorization records that contain limits but no broker credential.
- Historical market bars and current snapshots.
- Daily universe snapshots.
- Factor definitions and append-only factor trial records.
- Local Paper intents, decisions, internal transfers, simulated broker orders and fills, virtual allocations, shortfalls, virtual ledger positions, reconciliation events, and critical risk events.
- Algorithm project versions and file hashes.
- Quant job metadata, progress, artifact references, and training checkpoints.
- ONNX model registry metadata and compatibility state.
- Synthetic account fixtures, strategy-account mappings, bounded Agent authorization records, and sanitized Longbridge connection metadata.

These files remain on the local device. They must not contain credentials, full account identifiers, raw authentication output, broker-position snapshots, or real broker instructions.

API keys must not be included in issues, logs, screenshots, diagnostic exports, or bug reports.

Future prompts will update this statement only when their behavior is implemented. The completed v1.1 PDM is a product plan and does not describe current functionality by itself.

The v1.1.7 release packages the native macOS and Windows applications. Publisher signing, notarization, and platform reputation depend on repository-owner certificates and external trust services.

Cytisus-Trading is intended for automated quantitative operations development and review. It is not a manual trading terminal and is not investment advice.
