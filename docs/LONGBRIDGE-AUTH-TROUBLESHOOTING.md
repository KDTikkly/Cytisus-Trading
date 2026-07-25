# Longbridge Authentication Troubleshooting

Version: 1.1.3

Local Paper never requires Longbridge Terminal. If Longbridge is missing, signed out, expired, degraded, disconnected, or on an unsupported account channel, select Local Paper and continue using the deterministic local broker.

## Missing

Install Longbridge Terminal separately. Cytisus never downloads or bundles it.

macOS Homebrew:

```text
brew install --cask longbridge/tap/longbridge-terminal
```

macOS shell installer:

```text
curl -sSL https://open.longbridge.cn/longbridge/longbridge-terminal/install | sh
```

Windows PowerShell:

```text
iwr https://open.longbridge.cn/longbridge/longbridge-terminal/install.ps1 | iex
```

Windows Scoop:

```text
scoop install https://open.longbridge.cn/longbridge/longbridge-terminal/longbridge.json
```

Repository: https://github.com/longbridge/longbridge-terminal

After installation, use Check Again. If automatic discovery does not find the executable, select or enter its path in Settings.

## Unauthenticated or Expired

Use Sign In for device authorization, or Sign In with Authorization Code when Longbridge support provides a one-time code. Cytisus passes the code only to the allowlisted login command, clears it after every outcome, and never stores or logs it.

## RefreshPending

Wait briefly and use Check Again. Local Paper remains available. If the state does not clear, cancel the sign-in and start a new device authorization.

## UpdateRequired

Cytisus requires Longbridge Terminal 0.20.0 or later to classify the Paper account channel safely. Use Update CLI after reviewing the confirmation, or update Longbridge Terminal outside Cytisus.

## ReadyLive or ReadyUnknownChannel

Longbridge Paper is blocked. Cytisus recognizes Paper only when the sanitized channel value is exactly `lb_papertrading`. A display name is never used to infer account type. Live submission remains unavailable.

## Degraded

Check the executable path, local connectivity, and the command-specific help advertised by the installed CLI. Cytisus uses only:

```text
auth status --format json
check --format json
quote SYMBOL --format json
kline history SYMBOL --start DATE --end DATE --format json
security-list MARKET --format json
positions --format json
```

Cytisus does not read token directories, parse human tables, log raw authentication output, or expose arbitrary CLI execution.
