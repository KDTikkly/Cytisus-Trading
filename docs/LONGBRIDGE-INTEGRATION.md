# Cytisus Longbridge Integration

Version: 1
Status: Contract only in Prompt 1

## Boundary

Longbridge CLI is installed and authorized separately by the user. Cytisus does not bundle it, install it, read its token store, copy credentials, or request broker secrets in the UI.

Prompt 1 does not invoke Longbridge or collect market data. Both applications start in offline fixture mode.

## Allowed stored data

- Selected executable path.
- CLI version.
- Capability inspection results.
- Last successful check time.
- Non-sensitive permission summaries.
- Non-sensitive account aliases when needed.
- Timeout and cache settings.

Credentials, authorization codes, raw authentication output, and full account identifiers are prohibited.

## Process contract

- Resolve an explicitly configured executable or a trusted system-path result.
- Pass arguments as an array.
- Never use `sh -c`, `cmd /c`, or command-string execution.
- Apply timeout and cancellation.
- Capture exit code, standard output, and standard error separately.
- Limit captured output.
- Prefer documented machine-readable JSON.
- Redact sensitive fields before logging.
- Categorize every call as read-only data access or broker execution.
- Reject arbitrary arguments originating from a strategy process.

## Capability model

The adapter must inspect the installed CLI rather than assuming command availability. Missing CLI, missing authorization, unsupported commands, missing permissions, stale data, and malformed JSON are separate degraded states.

Health identifiers are:

- `Healthy`
- `Degraded`
- `Unhealthy`

## Fixture mode

Fixture mode is the default for Prompt 1 and automated checks. It requires no CLI, network, account, or credential. Shared fixtures exercise only contract parsing and offline application state until Prompt 2 implements the read-only adapter.

## Deferred work

Prompt 2 owns CLI discovery, capability inspection, read-only market collection, point-in-time cache fields, and universe snapshots. Broker execution remains deferred until Prompt 5.
