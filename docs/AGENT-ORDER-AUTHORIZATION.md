# Agent Order Authorization

Agent order intents are automated proposals, not manual order tickets.

## Modes

- `SuggestOnly`: record a suggestion without authorization.
- `ConfirmEveryOrder`: require explicit confirmation for every intent.
- `BoundedAutonomy`: authorize only when every configured boundary passes.

## Required boundaries

An authorization includes:

- allowed strategy IDs;
- allowed symbols;
- maximum notional per order;
- maximum daily notional;
- maximum order count per day;
- expiry;
- revocation state.

Mismatched, expired, revoked, or over-limit intents are rejected.

## Downstream controls

An Authorized result is not a broker order. The intent must still pass the existing strategy mode, risk decision, execution gateway, broker adapter, audit, virtual-ledger, and reconciliation controls.

Live broker submission remains rejecting in v1.1.2. Local Paper remains available without the Agent, Quant Worker, model providers, or Longbridge CLI.
