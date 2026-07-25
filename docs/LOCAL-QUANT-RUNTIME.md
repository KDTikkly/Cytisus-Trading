# Local Quant Runtime

The local Quant Worker is a separate process under `Worker/quant_worker.py`. It communicates with the desktop through typed JSON messages.

## Transports

- NDJSON over redirected standard input and output is the portable desktop-launch transport.
- Endpoint mode uses an AF_UNIX Unix-domain socket on macOS and an AF_PIPE named pipe on Windows.

Each request has `request_id`, `correlation_id`, and `message_type`, with optional `job_id`, `project_id`, and `payload`. Replies echo the identifiers and contain either `result` or a structured `error`.

## Lifecycle

Supported methods are:

- `Version`;
- `Health`;
- `DiscoverDevices`;
- `SubmitJob`;
- `ReadProgress`;
- `ReadResult`;
- `CancelJob`;
- `StructuredLogs`;
- `Stop`.

Jobs run outside the UI process. Requests and responses are size-limited. Desktop clients apply cancellation and time limits and may terminate a stuck child process.

## Python boundary

Cytisus does not install Python or silently choose a system interpreter. The desktop requires a user-selected absolute executable path and validates the bundled Worker script path. Optional packages are discovered but never installed automatically.

`Worker/runtime-manifest.json` records the supported Python range and exact optional compute-pack package versions. The CPU baseline uses only the Python standard library. Installing an optional pack is a separate, explicit user-approved action and is not performed by the application.

The Worker root contains job artifacts and checkpoints only. Broker secrets and account-token files are outside its contract.

## Determinism

Fixtures use fixed seeds. Backtests include explicit cost and slippage inputs. Walk-forward evaluation separates training, purge, and test ranges. Artifacts are content-addressed with SHA-256.

## Failure behavior

Worker absence, failure, cancellation, or incompatible optional runtimes does not block the official Local Paper strategy cycle, local broker, netting, allocation, ledger, or reconciliation.
