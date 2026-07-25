# Cytisus Strategy Protocol

Version: 1
Status: Implemented for local runtime and Paper operation in Prompt 3

## Purpose

Cytisus strategies are independent local processes. They exchange newline-delimited JSON (NDJSON) with a platform-specific Cytisus runtime. A strategy never receives broker credentials, invokes Longbridge directly, submits a broker command, or exposes a manual execution surface.

The official `Cross-Sectional Multi-Factor` strategy uses deterministic fixture factors. It demonstrates protocol flow and makes no alpha or return claim.

## Registry and manifest

Both native applications load the official registry and can register a local third-party manifest. Every manifest is validated against the shared contract before it can start.

Registration rejects:

- Duplicate strategy identifiers.
- Missing third-party entrypoints.
- Unsupported protocol or manifest versions.
- Invalid or mismatched parameter schemas.
- A manifest that does not support `PaperOnly`.
- Unknown capabilities or any direct CLI access declaration.

The allowed capabilities are `market_data`, `strategy_events`, and `structured_logs`. Strategy entrypoints receive no arbitrary command-line input.

## Process boundary

- The core launches an explicitly registered executable without a shell.
- Standard input carries core-to-strategy NDJSON.
- Standard output carries strategy-to-core NDJSON.
- Standard error is bounded, redacted, and logged separately.
- One JSON object is allowed per line.
- The default message limit is 64 KiB.
- Every envelope is checked for direction, identity, version, type, and sensitive keys.
- Duplicate event identifiers and malformed output are rejected.
- Heartbeats drive runtime health. A timeout marks the process `Unhealthy`, blocks new risk, and permits termination.
- `shutdown` is sent before the core waits for graceful exit. The process is terminated after the bounded shutdown interval.
- Exit status and lifecycle state are preserved for observability.

## Envelope

Every message contains:

```json
{
  "schema_version": 1,
  "event_id": "evt-0001",
  "correlation_id": "corr-0001",
  "strategy_id": "cross-sectional-multifactor",
  "strategy_version": "1.1.0",
  "cycle_id": "cycle-0001",
  "timestamp": "2026-01-01T00:00:00Z",
  "message_type": "initialize",
  "payload": {}
}
```

Identifiers are stable strings. Timestamps are UTC. Unknown or directionally invalid message types fail closed. Payload keys associated with tokens, secrets, credentials, authorization codes, or account numbers are prohibited.

## Core-to-strategy message types

- `initialize`
- `load_parameters`
- `apply_parameters`
- `market_snapshot`
- `allocation_budget`
- `start_cycle`
- `pause`
- `resume`
- `shutdown`

## Strategy-to-core message types

- `ready`
- `heartbeat`
- `log`
- `health`
- `signal`
- `factor_observation`
- `target_position`
- `trade_intent`
- `cycle_complete`
- `error`

## Parameter governance

The parameter UI is generated from `strategy-parameter-schema.schema.json`; arbitrary JSON is not the normal editing surface.

- `Low` changes validate against type and Cytisus hard bounds, apply immediately, create a new parameter version, and append an audit record.
- `Medium` changes validate immediately and become effective at the next safe cycle boundary.
- `High` changes first produce an impact preview and block new risk. Explicit confirmation creates a new version, pauses when required, applies at a safe boundary, and retains a rollback version.

Each record stores the change identifier, strategy identifier, parameter key, old and new values, request and effective timestamps, requester, risk tier, parameter version, activation mode, result, and rollback version.

## Paper and Live modes

- `PaperOnly` is the persisted state identifier; its user-facing label is `Local Paper`.
- The Global Live Lock is `OFF` by default.
- Turning the lock off returns every selected Live strategy to `PaperOnly`.
- Live selection requires the global lock, strategy Live support, and a matching enabled authorization within its validity interval.
- Authorization is bounded by strategy, markets, symbols or universe, capital, strategy allocation, single-position exposure, daily loss, drawdown, frequency, regular-hours permission, parameter version, and time.
- The v1.1.0 Live Longbridge adapter is a process-free rejecting boundary. No real broker submission is implemented.

Live-to-Paper transitions are:

- `StopOpeningRisk`: block new real risk while retaining existing-position management state.
- `Freeze`: pause strategy activity without generating a real instruction.
- `ControlledExit`: generate risk-reducing policy intents through the Local Paper gateway; no real broker instruction is generated.

## Shared state identifiers

Strategy modes:

- `PaperOnly`
- `Live`

Health:

- `Healthy`
- `Degraded`
- `Unhealthy`

Execution records:

- `StrategyIntent`
- `RiskDecision`
- `InternalTransfer`
- `BrokerOrder`
- `BrokerFill`
- `VirtualAllocation`
- `AllocationShortfall`

## Safety contract

- Strategy output creates typed observations, targets, and intents, never broker commands.
- Local Paper routing cannot reach Longbridge CLI or the Live adapter.
- The sole execution gateway accepts structured `TradeIntent` records and performs ordered mode, authorization, freshness, market, health, capital, position, duplicate, netting, submission, allocation, ledger, reconciliation, and audit stages.
- Internal transfers preserve strategy ownership and are never represented as broker fills.
- UI views are read only and cannot construct an arbitrary broker intent.
- UI views observe typed application state and do not parse protocol messages.
- Logs include strategy, correlation, and cycle identifiers without sensitive raw output.
- Real Longbridge broker submission and verified Terminal authentication remain outside v1.1.0 and are deferred to v1.1.3.
