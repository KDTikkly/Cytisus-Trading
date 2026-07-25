# Cytisus v1.1.3 Product Definition Model

Version: 1.1.3
Release type: Bug fix
Repository: KDTikkly/Cytisus-Trading
Dependency: v1.1.0, v1.1.1, and v1.1.2 must be complete and accepted first
Platforms: macOS 14+ and Windows 11 x64
Language: English
Repository text: ASCII only

## 1. Purpose

Cytisus v1.1.3 fixes Longbridge Terminal installation discovery, OAuth login, status detection, command mapping, Paper Trading account detection, and Paper-mode availability.

This release does not add a new product area.

It must not change:

- Quantitative algorithms.
- Factor discovery.
- Local compute.
- Model providers.
- Agent behavior except where account readiness is reported.
- Risk rules.
- Execution Gateway rules.
- Manual trading policy.
- Strategy lifecycle.
- Live authorization limits.

## 2. Verified Defect

The existing v1.1 Longbridge adapter was built against hypothetical command groups and JSON flags.

Examples of incorrect assumptions include:

```text
longbridge status
longbridge market bars
longbridge market snapshot
longbridge account positions
--output json
--json
```

The supported Longbridge Terminal interface uses commands such as:

```text
longbridge auth status --format json
longbridge check --format json
longbridge quote <SYMBOL> --format json
longbridge kline history <SYMBOL> --start <DATE> --end <DATE> --format json
longbridge security-list <MARKET> --format json
longbridge positions --format json
```

The existing UI also reports Unauthenticated but does not provide an in-app OAuth device-login flow or authorization-code redemption.

As a result, a correctly installed CLI can remain Degraded or Unauthenticated, market-data refresh can fail, and Longbridge-backed Paper Trading cannot become Ready.

## 3. Bug-fix Outcomes

v1.1.3 must:

1. Find supported Longbridge Terminal installations reliably.
2. Use the current Longbridge command hierarchy and `--format json`.
3. Allow a user to start OAuth device login from Cytisus.
4. Allow a user to redeem a one-time authorization code.
5. Allow login cancellation.
6. Allow logout.
7. Re-check status after authentication.
8. Parse Token state without reading Token files.
9. Detect Paper Trading account channel.
10. Distinguish Local Paper from Longbridge Paper.
11. Keep Local Paper available when CLI login fails.
12. Block Longbridge Paper when the authenticated account is not a Paper Trading account.
13. Keep Live gates unchanged.
14. Never log or persist OAuth Token material or one-time authorization codes.

## 4. Installation Discovery

### 4.1 User-selected path

The user-selected executable path remains the highest priority.

Validate that the path exists and is executable.

### 4.2 macOS automatic paths

In addition to the application process PATH, probe:

```text
/opt/homebrew/bin/longbridge
/usr/local/bin/longbridge
/usr/bin/longbridge
```

Resolve symlinks before execution.

Finder-launched applications must not depend on an interactive shell PATH.

### 4.3 Windows automatic paths

In addition to PATH, probe:

```text
%LOCALAPPDATA%\Programs\longbridge\longbridge.exe
%USERPROFILE%\scoop\shims\longbridge.exe
%USERPROFILE%\scoop\apps\longbridge\current\longbridge.exe
```

Do not execute an installer automatically.

### 4.4 Installation guidance

When the CLI is missing, display the official commands with Copy actions.

Windows PowerShell:

```powershell
iwr https://open.longbridge.cn/longbridge/longbridge-terminal/install.ps1 | iex
```

Windows Scoop:

```powershell
scoop install https://open.longbridge.cn/longbridge/longbridge-terminal/longbridge.json
```

macOS Homebrew:

```bash
brew install --cask longbridge/tap/longbridge-terminal
```

macOS or Linux installer:

```bash
curl -sSL https://open.longbridge.cn/longbridge/longbridge-terminal/install | sh
```

Also provide a link to:

```text
https://github.com/longbridge/longbridge-terminal
```

After installation, the user selects Check Again.

## 5. Allowed CLI Operations

Create a dedicated, allowlisted Longbridge maintenance and authentication service.

Allowed non-trading operations:

```text
--version
--help
auth --help
auth login
auth login --auth-code <ONE_TIME_CODE>
auth status --format json
auth logout
check --format json
update
```

Read-only data operations remain behind the existing data adapter.

No arbitrary command input is accepted.

The one-time authorization code:

- Is held only in memory.
- Is never stored.
- Is never logged.
- Is cleared after success, failure, or cancellation.

## 6. Authentication Flow

### 6.1 Device login

When the user selects Sign In:

1. Start `longbridge auth login`.
2. Capture bounded live stdout and stderr.
3. Redact sensitive fields.
4. Display the authorization URL, short code, and sanitized status.
5. Allow Open Browser when a URL is available.
6. Allow Copy Code.
7. Allow Cancel.
8. Use an authentication timeout separate from the normal data-command timeout.
9. After success, run:
   - `auth status --format json`
   - `check --format json`

Do not read the CLI Token directory.

### 6.2 Authorization-code login

Allow the user to paste a one-time code from:

```text
https://open.longbridge.cn/connect
```

Execute:

```text
longbridge auth login --auth-code <CODE>
```

The code must not appear in logs or persisted settings.

### 6.3 Logout

Logout requires explicit user confirmation.

Execute:

```text
longbridge auth logout
```

Then clear only non-sensitive Cytisus session metadata and re-check status.

Do not delete files directly from the Longbridge Token directory.

## 7. Status Model

Replace ambiguous readiness with explicit states:

```text
Missing
Installed
Authorizing
Unauthenticated
RefreshPending
Expired
ReadyPaper
ReadyLive
ReadyUnknownChannel
Degraded
UpdateRequired
```

Required interpretation:

- `Missing`: executable not found.
- `Installed`: executable found but authentication has not been checked.
- `Authorizing`: login process is active.
- `Unauthenticated`: no usable authorization.
- `RefreshPending`: access Token expired but refresh Token remains usable.
- `Expired`: re-login is required.
- `ReadyPaper`: authenticated Paper Trading account and connectivity check succeeded.
- `ReadyLive`: authenticated Live account and connectivity check succeeded.
- `ReadyUnknownChannel`: authenticated but account channel cannot be classified safely.
- `Degraded`: command, JSON, connectivity, or permission failure.
- `UpdateRequired`: installed CLI is too old for reliable Paper Trading channel detection.

## 8. CLI Version Policy

Parse the installed CLI semantic version.

Paper Trading channel classification requires Longbridge Terminal v0.20.0 or later.

For an older version:

- Show Update Required.
- Keep Local Paper available.
- Block Longbridge Paper.
- Offer an explicit Update CLI action after user confirmation, or show:
  `longbridge update`.

Do not silently update the binary.

## 9. Correct Command Discovery

Do not infer fictional command groups from words in root help.

Use a version-aware canonical command map and validate it using command-specific help.

Required command checks:

```text
auth status --help
check --help
quote --help
kline history --help
security-list --help
positions --help
```

JSON output must use:

```text
--format json
```

Support a compatibility alias only when the installed CLI help explicitly advertises it.

Do not require root help to advertise the JSON flag before checking a command.

## 10. Paper Trading Modes

Expose two distinct modes:

### Local Paper

- Uses the local Paper Broker and local or cached data.
- Does not require Longbridge authentication.
- Must remain available when CLI is Missing, Unauthenticated, Expired, Degraded, or UpdateRequired.
- Must never call Longbridge order commands.

### Longbridge Paper

- Uses the authenticated Longbridge Paper Trading account.
- Requires `ReadyPaper`.
- Requires the Paper Trading account channel reported by `auth status`.
- Uses the existing Execution Gateway.
- Must not be enabled for `ReadyLive` or `ReadyUnknownChannel`.
- Must not silently switch to a Live account.

UI labels must not use the single ambiguous label `Paper` where the distinction matters.

## 11. Paper Account Detection

Parse the sanitized `auth status --format json` response.

Detect the account channel using supported response fields.

Recognize the Longbridge Paper Trading channel, including the currently supported `lb_papertrading` value.

Do not identify a Paper account from an account name string alone.

Persist only non-sensitive metadata needed for UI state:

```text
account_environment
account_channel
status_checked_at
cli_version
permissions_summary
```

Do not persist full account IDs or raw status JSON.

## 12. Failure Handling

### Browser cannot open

Keep the URL and short code visible for manual use.

### Login process times out

Stop the child process and return Unauthenticated or Expired.

### Login is cancelled

Stop the process, clear the one-time code, and re-check local status.

### Token refresh is pending

Run one non-destructive `check --format json`.

Do not repeatedly retry.

### Connectivity fails

Authentication may remain valid, but Longbridge-backed data and Longbridge Paper remain unavailable until Check Again succeeds.

Local Paper remains available.

### Wrong account channel

Show that a Live account is connected and that Longbridge Paper requires a Paper Trading account.

Do not submit any test order.

### JSON changes

Return Degraded with a sanitized diagnostic category.

Do not fall back to parsing human tables.

## 13. UI Changes

Update the Longbridge connection card on both platforms.

Required controls:

```text
Check Again
Sign In
Sign In with Authorization Code
Cancel Sign In
Sign Out
Update CLI
Copy Install Command
Open Longbridge Terminal Repository
```

Show:

```text
CLI path
CLI version
Authentication state
Connectivity state
Account environment
Paper or Live channel
Quote permission summary
Last checked time
Sanitized failure reason
```

Disable controls that are not valid for the current state.

Do not show OAuth Tokens.

## 14. Logging and Audit

Application logs may include:

```text
operation
state transition
CLI version
duration
exit category
sanitized failure category
```

Application logs must not include:

- OAuth Token.
- Refresh Token.
- Authorization header.
- One-time authorization code.
- Raw `auth status` output.
- Full account ID.
- Full stderr from authentication.

Audit:

- Login started.
- Login succeeded.
- Login failed.
- Login cancelled.
- Logout.
- CLI update requested.
- Paper-mode selection.
- Account-channel mismatch.

## 15. Minimal Tests

Keep the test scope small.

Required tests only:

1. macOS standard-path discovery.
2. Windows standard-path discovery.
3. Canonical command construction:
   - `auth status --format json`
   - `check --format json`
   - `quote`
   - `kline history`
   - `security-list`
   - `positions`
4. Device-login state transition using a fake process runner.
5. Authorization-code redaction and memory clearing.
6. Paper Trading channel maps to `ReadyPaper`.
7. Live channel maps to `ReadyLive`.
8. CLI older than v0.20.0 maps to `UpdateRequired` for Longbridge Paper.
9. Local Paper remains available when authentication fails.
10. Longbridge Paper requires `ReadyPaper`.
11. No real login, network call, account, or order in CI.
12. ASCII validation.
13. One final macOS build.
14. One final Windows build.

Do not add:

- UI snapshot tests.
- Large CLI-version matrices.
- Real OAuth tests in CI.
- Real Paper orders.
- Real Live orders.
- Performance benchmarks.
- Coverage-driven tests.
- Repeated full test runs.

Run each targeted test once.

On failure, rerun only the failed target.

Run one final smoke pass and one dual-platform release workflow.

## 16. Documentation

Add:

```text
docs/PDM-v1.1.3.md
docs/LONGBRIDGE-AUTH-TROUBLESHOOTING.md
docs/CODEX-v1.1.3-PROMPT.md
```

Update only affected content in:

```text
README.md
INSTALL.txt
PRIVACY.md
SANITIZATION.json
docs/LONGBRIDGE-INTEGRATION.md
```

Document:

- Official installation commands.
- Device login.
- Authorization-code login.
- Status and account-channel states.
- Local Paper versus Longbridge Paper.
- Minimum CLI version for reliable Paper channel detection.
- Token isolation.
- Troubleshooting steps.

## 17. Release

Update version references to:

```text
1.1.3
```

Expected artifacts:

```text
dist/Cytisus-Trading-1.1.3-universal.dmg
dist/Cytisus-Trading-1.1.3-win11-x64.exe
```

Preserve:

- Native SwiftUI macOS application.
- Native WPF Windows application.
- Existing Execution Gateway.
- Universal 2 macOS build.
- Windows self-contained build.
- Signing and notarization support.
- Dual-platform GitHub Actions workflow.
- English-only ASCII validation.

## 18. Acceptance Criteria

v1.1.3 is accepted only when:

- The correct installed CLI is found from standard install locations.
- The application uses `auth status --format json`.
- The application uses `check --format json`.
- Data commands use the actual Longbridge Terminal command hierarchy.
- The user can complete device login from the Cytisus connection screen.
- The user can redeem a one-time authorization code.
- Login can be cancelled safely.
- Logout works through the CLI.
- No Token file is read directly.
- No Token or one-time code is persisted or logged.
- Paper Trading channel is detected correctly.
- Local Paper is never blocked by CLI authentication failure.
- Longbridge Paper is available only for `ReadyPaper`.
- A connected Live account is never silently used for Longbridge Paper.
- No real order is sent by tests.
- macOS and Windows builds succeed.
- Documentation matches the implemented behavior.

## 19. Current Branch Note

The inspected `codex/v1.1-foundations` branch is currently at the Prompt 4 implementation stage and has not completed Prompt 5.

Do not run the v1.1.3 implementation prompt on that branch yet.

The incorrect Longbridge command assumptions should be corrected before completing Prompt 5, then retained in the final v1.1.3 bug-fix release.
