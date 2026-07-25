# Cytisus Longbridge Integration

Version: 1.1.3
Status: Authentication and Paper-channel readiness implemented; Live submission remains rejecting

## Security boundary

Longbridge Terminal is installed and authorized separately by the user. Cytisus does not bundle or download it, inspect token directories, request or store a broker token, retain raw authentication JSON, or expose arbitrary command execution to a strategy, model, Agent, or Quant Worker.

Local Paper is a separate subsystem. Missing, Unauthenticated, RefreshPending, Expired, Degraded, UpdateRequired, ReadyLive, or ReadyUnknownChannel states never block:

- The official Local Paper strategy cycle.
- The deterministic Local Paper Broker.
- Internal netting.
- Partial-fill simulation and allocation.
- Virtual-ledger updates.
- Fixture reconciliation.

## Executable discovery

Both native applications use this order:

1. A user-selected executable path.
2. The process `PATH`.
3. Platform candidates.

macOS candidates:

```text
/opt/homebrew/bin/longbridge
/usr/local/bin/longbridge
/usr/bin/longbridge
```

Windows candidates:

```text
%LOCALAPPDATA%\Programs\longbridge\longbridge.exe
%USERPROFILE%\scoop\shims\longbridge.exe
%USERPROFILE%\scoop\apps\longbridge\current\longbridge.exe
```

Resolved symbolic links are followed and the final path must identify an executable file.

## Capability discovery and command mapping

Root help is informational only. Cytisus checks each command with its own help:

```text
auth status --help
check --help
quote --help
kline history --help
security-list --help
positions --help
```

Machine-readable calls are constructed only as typed argument arrays:

```text
auth status --format json
check --format json
quote SYMBOL --format json
kline history SYMBOL --start DATE --end DATE --format json
security-list MARKET --format json
positions --format json
```

Cytisus does not construct the superseded provisional command shapes documented in early v1.1 foundations and does not use alternate JSON switches unless a future compatibility profile verifies them explicitly.

All data calls are read only. There is no market-session command in the verified mapping; the UI reports quote availability instead of inventing one.

## Process controls

The adapters:

- Never invoke a shell.
- Pass one bounded argument array to the executable.
- Capture standard output and standard error separately.
- Apply timeouts and cancellation.
- Kill an over-time process.
- Bound retained output.
- Preserve exit code, duration, truncation, timeout, and cancellation facts.
- Parse JSON only where machine-readable output is required.
- Redact sensitive fields before any diagnostic or audit record is created.

## Authentication

The allowlisted maintenance and authentication operations are:

```text
--version
--help
auth --help
auth login
auth login --auth-code CODE
auth status --format json
auth logout
check --format json
update
```

Device authorization and authorization-code login are bounded and cancellable. The UI may show a sanitized HTTPS authorization URL and short code. Authorization codes exist only in memory for the call, are never logged or persisted, and are cleared after success, failure, timeout, cancellation, or parsing errors.

Sign Out and Update CLI require an explicit UI confirmation.

## Connection states

- `Missing`: no executable resolves.
- `Installed`: an allowlisted maintenance call completed and status is being rechecked.
- `Authorizing`: a login is in progress.
- `Unauthenticated`: sign-in is required.
- `RefreshPending`: authentication refresh has not completed.
- `Expired`: authentication has expired.
- `ReadyPaper`: authenticated, connected, and channel is exactly `lb_papertrading`.
- `ReadyLive`: authenticated to a recognized Live channel. Live submission is still unavailable.
- `ReadyUnknownChannel`: authenticated, but the channel is not recognized.
- `Degraded`: command, connectivity, timeout, exit-code, or JSON validation failed.
- `UpdateRequired`: CLI is older than 0.20.0 or cannot be safely version-classified.

Display names are never used to infer Paper. Only `lb_papertrading` enables Longbridge Paper readiness.

## Persistence and logs

The schema-v8 store persists only:

- `account_environment`
- `account_channel`
- `status_checked_at`
- `cli_version`
- `permissions_summary`

It does not persist raw JSON, tokens, authorization codes, account numbers, full account identifiers, device-login output, or broker secrets.

Audit events record state transitions and operation outcomes with sanitized environment and channel values. Standard output and standard error are never copied into logs.

## Paper modes

`Local Paper` always uses the local deterministic Paper Broker and never calls Longbridge Terminal.

`Longbridge Paper` is a distinct readiness classification. It is allowed only in `ReadyPaper` and must remain behind the Execution Gateway. This release does not silently switch account channels, submit a real Paper order, or enable Live submission.

## Fixtures

Deterministic fixtures cover CLI version and command help, Paper and Live channel status, refresh-pending, expired, unknown channel, device-login progress, connectivity, historical daily bars, current quote, market status for offline demonstrations, security reference data, and positions for Reduce Only behavior.

Fixture mode requires no CLI, account, credential, or network.

## Known limitations

- No real OAuth, brokerage account, network, or order call is used by repository smoke checks.
- Actual Longbridge service availability and the fields returned by a future Terminal version remain external dependencies.
- The read-only data parsers retain the v1.1 fixture contracts; additional verified Terminal response-shape adapters may be needed for a real account.
- Longbridge Paper readiness is classified, but real Paper order submission is not claimed or tested.
- The Live adapter remains process-free and rejecting.
- Windows publisher signing and macOS notarization require repository-owner certificates and external trust services.

See [Longbridge authentication troubleshooting](LONGBRIDGE-AUTH-TROUBLESHOOTING.md).
