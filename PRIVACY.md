# Cytisus-Trading Privacy Statement

Cytisus-Trading 1.1.0 is under active implementation. Prompt 4 adds local deterministic factor research, lifecycle evidence, regime probabilities, and strategy capital budgets. Fixture mode remains the default, and Live broker submission remains unavailable.

## Current behavior

- Fixture mode makes no network request and does not invoke Longbridge CLI.
- Local CLI mode invokes only capability-advertised read-only data operations. Any CLI network or authorization activity belongs to the separately installed CLI.
- The app never reads Longbridge token files or asks for a broker secret.
- A read-only broker-position snapshot may be held in memory to mark excluded holdings Reduce Only. It is not cached.
- The app contains no tokens, API keys, certificates, authorization codes, or account bindings.
- Repository fixtures contain only fictional market, factor, and position data.
- Official and registered third-party strategies run as explicit local processes without a shell. They do not receive credentials or direct CLI access.
- Strategy messages are size-bounded, typed, and checked for prohibited sensitive payload keys before they are logged or accepted.
- Paper strategy intents remain local records and cannot reach the Live adapter.
- The Global Live Lock is off by default. A bounded local authorization record is required for Live selection, but the Live adapter still rejects submission.
- The app has no order, cancellation, fund-management, or account-configuration capability.
- Factor candidates are evaluated locally from one normalized source snapshot. Candidate search does not invoke Longbridge CLI, a network service, an LLM, or executable factor code.
- Factor definitions and all trial results, including failures, are stored locally. They contain dataset and universe versions but no broker credentials or account identifiers.
- Regime and capital-allocation results are deterministic local recommendations. They cannot submit or net broker orders.
- Live broker submission is unavailable.

## Local persistence

The v1.1 foundation stores only:

- Non-sensitive interface settings.
- Schema and migration version information.
- Operational application logs.
- Audit events for local fixture actions.
- Strategy manifests and runtime state.
- Parameter-change history and rollback version references.
- Bounded Live-authorization records that contain limits but no broker credential.
- Historical market bars and current snapshots.
- Daily universe snapshots.
- Factor definitions and append-only factor trial records.

These files remain on the local device. They must not contain credentials, full account identifiers, raw authentication output, broker-position snapshots, or real broker instructions.

Future prompts will update this statement only when their behavior is implemented. The completed v1.1 PDM is a product plan and does not describe current functionality by itself.

Cytisus-Trading is intended for automated quantitative operations development and review. It is not a manual trading terminal and is not investment advice.
