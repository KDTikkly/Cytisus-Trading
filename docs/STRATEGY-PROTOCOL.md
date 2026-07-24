# Cytisus Strategy Protocol

Version: 1
Status: Contract only in Prompt 1

## Purpose

Cytisus strategies are independent local processes. They exchange NDJSON messages with a platform-specific Cytisus service. A strategy never receives broker credentials and never invokes Longbridge directly.

Prompt 1 defines this contract but does not start strategy processes or execute strategies.

## Process boundary

- The core launches an explicitly registered executable with an argument array.
- Shell command strings are prohibited.
- Standard input carries core-to-strategy NDJSON.
- Standard output carries strategy-to-core NDJSON.
- Standard error is captured separately and redacted before logging.
- Every process has timeout, cancellation, message-size, and output-size limits.
- Malformed or oversized messages are rejected.
- Heartbeat loss changes health to `Unhealthy` and blocks new intents.

## Envelope

Every message contains:

```json
{
  "event_id": "evt-0001",
  "correlation_id": "corr-0001",
  "strategy_id": "fixture-multifactor",
  "strategy_version": "1.1.0",
  "cycle_id": "cycle-0001",
  "timestamp": "2026-01-01T00:00:00Z",
  "message_type": "initialize",
  "payload": {}
}
```

Identifiers are stable strings. Timestamps are UTC. Unknown message types fail closed.

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

- The default mode is `PaperOnly`.
- `Live` is unavailable during Prompt 1.
- A strategy message cannot create a broker command directly.
- The core validates message shape, strategy identity, cycle identity, and timestamp.
- Duplicate event identifiers are rejected or treated idempotently.
- Payload fields that can contain credentials are prohibited and redacted.
- UI views observe typed application state; they do not parse protocol messages.
