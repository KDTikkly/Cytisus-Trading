# Cytisus-Trading Privacy Statement

Cytisus-Trading 1.1.0 is under active implementation. Prompt 2 adds optional read-only market-data access through a separately installed Longbridge CLI. Fixture mode remains the default.

## Current behavior

- Fixture mode makes no network request and does not invoke Longbridge CLI.
- Local CLI mode invokes only capability-advertised read-only data operations. Any CLI network or authorization activity belongs to the separately installed CLI.
- The app never reads Longbridge token files or asks for a broker secret.
- A read-only broker-position snapshot may be held in memory to mark excluded holdings Reduce Only. It is not cached.
- The app contains no tokens, API keys, certificates, authorization codes, or account bindings.
- Repository fixtures contain only fictional market, factor, and position data.
- The app has no order, cancellation, fund-management, or account-configuration capability.
- Live execution is unavailable.

## Local persistence

The v1.1 foundation stores only:

- Non-sensitive interface settings.
- Schema and migration version information.
- Operational application logs.
- Audit events for local fixture actions.
- Historical market bars and current snapshots.
- Daily universe snapshots.

These files remain on the local device. They must not contain credentials, full account identifiers, raw authentication output, broker-position snapshots, or real orders.

Future prompts will update this statement only when their behavior is implemented. The completed v1.1 PDM is a product plan and does not describe current functionality by itself.

Cytisus-Trading is intended for automated quantitative operations development and review. It is not a manual trading terminal and is not investment advice.
