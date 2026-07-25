# Cytisus Longbridge Integration

Version: 1.1
Status: Read-only data foundation retained; Prompt 5 Live execution remains rejecting

## Security boundary

Longbridge CLI is installed and authorized separately by the user. Cytisus does not bundle it, download it, inspect its token directory, request a token, store OAuth material, or expose CLI arguments to a strategy.

Prompt 2 introduced provisional read-only discovery and fixture adapters. Prompt 5 adds an isolated typed Live execution boundary, but it does not submit an order or start Longbridge Terminal. Local Paper is a separate subsystem and never depends on this integration.

## Executable discovery

Both native applications:

1. Prefer the executable path stored by the user.
2. Otherwise search the process `PATH` for the platform executable name.
3. Require the resolved path to identify an existing executable.
4. Read `--version`.
5. Inspect `--help` before constructing capability-dependent commands.
6. Inspect command-group help where a market or account group is advertised.

The Prompt 2 adapter does not issue an unadvertised market command. Its fixture templates are not execution dependencies. Prompt 5 does not promote provisional commands such as `status`, `market bars`, `market snapshot`, or `account positions`, and does not rely on `--output json` or `--json`.

## Capability-aware calls

Supported operation identifiers are:

- `Status`
- `Connectivity`
- `HistoricalBars`
- `CurrentSnapshot`
- `MarketStatus`
- `SecurityList`
- `BrokerPositions`

Every constructed command has an executable path, an argument array, the `ReadOnlyData` category, and one operation identifier. Placeholder values are bounded and control characters are rejected.

The fixture capability file contains exact deterministic templates for offline checks. Those templates are fixture contracts, not a claim that every installed CLI version uses the same syntax.

## Process controls

The macOS and Windows adapters:

- Never invoke a shell.
- Pass one argument array to the executable.
- Capture standard output and standard error separately.
- Enforce a configurable timeout.
- Support cancellation at the process-runner boundary.
- Kill an over-time child process.
- Drain output while retaining at most 1 MiB per stream.
- Preserve the exit code and timeout, cancellation, duration, and truncation state.
- Reject non-read-only call categories.
- Parse JSON data and never fall back to a human table parser.

## Status states

- `Missing`: no selected or system-path executable resolves.
- `Unauthenticated`: the local status result reports missing authorization.
- `Degraded`: version, help, status, connectivity, permission, exit-code, timeout, or JSON validation fails.
- `Ready`: advertised status and connectivity checks succeed.

Missing and Unauthenticated states do not prevent the application from starting. Authorization must be completed through Longbridge CLI itself.

## Sensitive-data handling

Before application logs are created, Cytisus redacts JSON properties and named text fields for tokens, secrets, passwords, credentials, authorization codes, and full account identifiers. Bearer values are also redacted.

CLI logs contain the operation state and `ReadOnlyData` category. Raw status, authentication, standard output, and standard error are not written to application logs.

## Fixture mode

Fixture mode requires no CLI, account, network, or credential. Shared deterministic fixtures cover:

- CLI version, capabilities, and exact argument templates.
- Authorization and non-sensitive permissions.
- Connectivity.
- Historical daily bars.
- Current market snapshot.
- Market status.
- Security reference list.
- Broker-position snapshot for Reduce Only behavior.
- Universe rule configuration.

The same fixture files drive both native applications.

## Point-in-time market records

Market bars and current snapshots carry:

- `event_time`
- `available_time`
- `collected_at`
- `source_version`
- `adjustment_mode`
- `data_hash`

Historical bar cache identity uses symbol, interval, start, and end. Writing the same `data_hash` to the same identity is idempotent. Current snapshots and universe snapshots also use stable local identities.

The cache is a bounded-scope JSON foundation, not a complete historical warehouse. Cache-directory and retention preferences are persisted. A cache-directory change takes effect on the next application launch; automatic retention pruning is deferred.

## Daily universe

The implemented order is:

```text
Configured source
-> Tradable filter
-> Price filter
-> Liquidity filter
-> Listing-age filter
-> History-coverage filter
-> Suspension, delisting, and abnormal filter
-> Strategy-specific placeholder filter
-> Universe snapshot
```

Each entry stores date, symbol, inclusion flag, disposition, reason, liquidity metrics, data coverage, industry, rule version, and source version.

An excluded symbol with a non-zero broker-position fixture becomes `ReduceOnly`. It remains excluded from new-risk eligibility.

## Current limitations

- No local Longbridge CLI was present in the Prompt 2 Windows build environment, so real capability syntax and account permissions were not exercised.
- An installed CLI that does not advertise the required JSON options remains Degraded.
- Position snapshots are read only when the installed CLI advertises that capability.
- Cache retention is configured but not automatically pruned.
- No strategy receives CLI access.
- Local Paper, internal netting, partial-fill allocation, the virtual ledger, and fixture reconciliation are implemented without CLI access.
- Live authorization models exist, but the Longbridge Live adapter intentionally rejects without starting a process.

## Prompt 5 execution isolation

Local Paper remains available when Longbridge CLI is missing, unauthenticated, degraded, unsupported, disconnected, or has no account. The official Local Paper strategy cycle, deterministic Local Paper Broker, internal netting, partial-fill simulation, virtual-ledger updates, and fixture reconciliation do not inspect CLI help or status.

Prompt 5 command construction uses only a synthetic typed fixture. It proves placeholder substitution, bounded argument arrays, correlation identifiers, and safe rejection. The synthetic template is not a real Longbridge Terminal command and cannot be executed by the adapter.

## Deferred v1.1.3 work

v1.1.3 must verify the installed Longbridge Terminal and replace provisional read-only mappings with capability-aware typed mappings for:

- `auth status --format json`
- `check --format json`
- `quote`
- `kline history`
- `security-list`
- `positions`

v1.1.3 must also implement and validate the intended login, device authorization or authorization-code flow, logout, installer guidance, and any distinct Longbridge Paper account channel. None of those authentication features are implemented in v1.1.0.

Until that work is complete, users authorize Longbridge Terminal outside Cytisus using Longbridge's own supported interface. Cytisus must not request, read, or store the resulting credential.
