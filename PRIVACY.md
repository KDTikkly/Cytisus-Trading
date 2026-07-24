# Cytisus-Trading Privacy Statement

Cytisus-Trading 1.1.0 is under active implementation. Prompt 1 runs entirely in offline fixture mode.

## Current behavior

- The app does not make network requests.
- The app does not invoke Longbridge CLI.
- The app does not connect to brokers, exchanges, market-data providers, or analytics services.
- The app does not read or store accounts, positions, orders, profit and loss, or identity data.
- The app contains no tokens, API keys, certificates, authorization codes, or account bindings.
- Every factor name, metric, curve, and state is a built-in fictional fixture.
- The app has no order, cancellation, fund-management, or account-configuration capability.
- Live execution is unavailable.

## Local persistence

The v1.1 foundation stores only:

- Non-sensitive interface settings.
- Schema and migration version information.
- Operational application logs.
- Audit events for local fixture actions.

These files remain on the local device. They must not contain credentials, full account identifiers, authentication output, positions, or real orders.

Future prompts will update this statement only when their behavior is implemented. The completed v1.1 PDM is a product plan and does not describe current functionality by itself.

Cytisus-Trading is intended for automated quantitative operations development and review. It is not a manual trading terminal and is not investment advice.
