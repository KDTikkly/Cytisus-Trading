# Codex Prompt: Implement Cytisus v1.1.3 Longbridge Authentication Fix

Repository: KDTikkly/Cytisus-Trading
Target release: 1.1.3
Release type: Bug fix
Output language: English only
Repository text: ASCII only

## 1. Verify Preconditions

Read the repository before editing.

Verify that accepted v1.1.0, v1.1.1, and v1.1.2 implementations are present.

If the current branch is still `codex/v1.1-foundations` at Prompt 4 or Prompt 5 is incomplete:

- Do not implement v1.1.3 on that incomplete branch.
- Report the current stage and stop.
- Note that the command-mapping defect must be corrected before v1.1.0 final release.

Do not recreate existing strategy, factor, model-provider, local-compute, risk, ledger, or execution systems.

## 2. Add Documents

Add the supplied PDM as:

```text
docs/PDM-v1.1.3.md
```

Add this prompt as:

```text
docs/CODEX-v1.1.3-PROMPT.md
```

Add:

```text
docs/LONGBRIDGE-AUTH-TROUBLESHOOTING.md
```

Read the PDM before implementation.

## 3. Bug Scope

Fix only:

- CLI executable discovery.
- OAuth device login.
- Authorization-code login.
- Logout.
- Status parsing.
- Connectivity parsing.
- Correct Longbridge command mapping.
- CLI version validation.
- Paper Trading account-channel detection.
- Local Paper availability.
- Longbridge Paper readiness.
- Related UI, logs, audit, and documentation.

Do not change quant algorithms, Agent models, factor research, risk limits, manual-trading policy, or unrelated UI.

## 4. Correct the Existing Command Adapter

Remove assumptions such as:

```text
status
market bars
market snapshot
account positions
--output json
--json
```

Implement the canonical current commands:

```text
auth status --format json
check --format json
quote <SYMBOL> --format json
kline history <SYMBOL> --start <DATE> --end <DATE> --format json
security-list <MARKET> --format json
positions --format json
```

Inspect command-specific help before enabling each operation:

```text
auth status --help
check --help
quote --help
kline history --help
security-list --help
positions --help
```

Do not require root help to advertise `--format`.

Use compatibility aliases only when help explicitly advertises them.

Keep executable plus argument-array process invocation.

Never construct a shell command string.

## 5. Fix Executable Discovery

Priority:

1. User-selected executable.
2. Process PATH.
3. Standard platform paths.

macOS paths:

```text
/opt/homebrew/bin/longbridge
/usr/local/bin/longbridge
/usr/bin/longbridge
```

Windows paths:

```text
%LOCALAPPDATA%\Programs\longbridge\longbridge.exe
%USERPROFILE%\scoop\shims\longbridge.exe
%USERPROFILE%\scoop\apps\longbridge\current\longbridge.exe
```

Resolve symlinks where applicable.

Validate executable status.

Do not run an installer automatically.

## 6. Add Installation Guidance

When Missing, show platform-appropriate official commands with Copy actions.

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

macOS or Linux:

```bash
curl -sSL https://open.longbridge.cn/longbridge/longbridge-terminal/install | sh
```

Repository:

```text
https://github.com/longbridge/longbridge-terminal
```

Provide Check Again after installation.

## 7. Add an Allowlisted Authentication Service

Allowed operations only:

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

Do not accept arbitrary arguments from UI, Agent, or strategy code.

Keep authentication operations separate from read-only market-data calls and trading calls.

## 8. Device Login

Implement asynchronous `longbridge auth login`.

Requirements:

- Capture bounded live output.
- Parse or surface a sanitized authorization URL and short code.
- Allow Open Browser.
- Allow Copy Code.
- Allow Cancel.
- Use a dedicated authentication timeout.
- Kill the login process after timeout or cancellation.
- Clear temporary code state.
- Run status and check after success.

Do not read the Token directory.

Do not log raw authentication output.

## 9. Authorization-code Login

Add a one-time code input for codes obtained from:

```text
https://open.longbridge.cn/connect
```

Execute:

```text
longbridge auth login --auth-code <CODE>
```

The code:

- Exists only in memory.
- Is never saved.
- Is never logged.
- Is cleared after every outcome.

## 10. Logout and Update

Logout:

```text
longbridge auth logout
```

Require confirmation.

Do not delete Token files directly.

Update:

```text
longbridge update
```

Require explicit confirmation.

Do not update silently.

## 11. Status States

Implement:

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

Run:

```text
longbridge auth status --format json
longbridge check --format json
```

Parse status without persisting raw JSON.

Recognize refresh-pending separately from expired.

## 12. Version and Paper Account Detection

Parse CLI semantic version.

Longbridge Paper account-channel detection requires v0.20.0 or later.

For older versions:

- Return UpdateRequired for Longbridge Paper.
- Keep Local Paper available.
- Do not guess account channel.

Parse the Paper Trading channel from supported status fields.

Recognize `lb_papertrading`.

Do not infer Paper from display name text.

Persist only:

```text
account_environment
account_channel
status_checked_at
cli_version
permissions_summary
```

Do not persist full account IDs.

## 13. Separate Paper Modes

Implement explicit:

```text
Local Paper
Longbridge Paper
```

Local Paper:

- Never requires CLI authentication.
- Uses the local Paper Broker.
- Remains available for Missing, Unauthenticated, Expired, Degraded, or UpdateRequired.
- Never sends a Longbridge order.

Longbridge Paper:

- Requires ReadyPaper.
- Uses the authenticated Paper Trading channel.
- Uses the existing Execution Gateway.
- Must be unavailable for ReadyLive and ReadyUnknownChannel.
- Must not silently use a Live account.

Keep existing Live authorization and risk gates unchanged.

## 14. UI

Update Longbridge connection UI on macOS and Windows.

Controls:

```text
Check Again
Sign In
Sign In with Authorization Code
Cancel Sign In
Sign Out
Update CLI
Copy Install Command
Open Repository
```

Show:

```text
CLI path
CLI version
Authentication state
Connectivity state
Account environment
Account channel
Paper or Live classification
Permission summary
Last checked time
Sanitized failure category
```

Do not display Tokens.

Do not add manual order entry.

## 15. Redaction and Audit

Never log or store:

- OAuth Token.
- Refresh Token.
- Authorization header.
- One-time code.
- Raw auth status JSON.
- Full account ID.
- Full authentication stderr.

Audit only state transitions:

- Login started.
- Login succeeded.
- Login failed.
- Login cancelled.
- Logout.
- Update requested.
- Paper mode selected.
- Channel mismatch.

## 16. Minimal Tests Only

Required tests:

1. macOS standard-path discovery.
2. Windows standard-path discovery.
3. Canonical command construction.
4. Device-login state flow with a fake runner.
5. Authorization-code redaction and clearing.
6. Paper channel -> ReadyPaper.
7. Live channel -> ReadyLive.
8. CLI version below v0.20.0 -> UpdateRequired for Longbridge Paper.
9. Local Paper remains available after login failure.
10. Longbridge Paper requires ReadyPaper.
11. ASCII validation.
12. One final macOS build.
13. One final Windows build.

Do not add:

- Real OAuth tests.
- Real network tests in CI.
- Real account tests.
- Real Paper orders.
- Real Live orders.
- UI snapshot tests.
- Large version matrices.
- Performance tests.
- Coverage-driven tests.
- Repeated full test runs.

Run each focused test once.

Rerun only a failed target.

Run one final smoke pass and one dual-platform release workflow.

## 17. Documentation and Release

Update only affected documentation:

```text
README.md
INSTALL.txt
PRIVACY.md
SANITIZATION.json
docs/LONGBRIDGE-INTEGRATION.md
docs/LONGBRIDGE-AUTH-TROUBLESHOOTING.md
```

Update version to 1.1.3.

Expected artifacts:

```text
dist/Cytisus-Trading-1.1.3-universal.dmg
dist/Cytisus-Trading-1.1.3-win11-x64.exe
```

Preserve signing, notarization, Windows self-contained publishing, GitHub Actions, and ASCII validation.

## 18. Completion

Before finishing:

1. Confirm correct command hierarchy.
2. Confirm correct executable discovery.
3. Confirm device login and authorization-code login.
4. Confirm no Token file is read.
5. Confirm no Token or code is logged.
6. Confirm Paper Trading account detection.
7. Confirm Local Paper does not require login.
8. Confirm Longbridge Paper requires ReadyPaper.
9. Confirm a Live account cannot be used silently for Paper.
10. Run minimal tests.
11. Build both artifacts.
12. Search tracked files for secrets, real accounts, positions, orders, and user-specific paths.
13. Commit and push without force-pushing.

Suggested commit message:

```text
fix: repair Longbridge login and paper account readiness
```

## 19. Final Response

Report only:

```text
Implementation summary
Precondition verification
Root causes fixed
CLI discovery behavior
Authentication behavior
Paper account classification
Local Paper and Longbridge Paper behavior
Files changed
Tests and builds actually executed
Artifact paths and SHA-256 values
Commit SHA
Push status
Known limitations
User recovery steps
```

Do not claim success for an action that was not actually completed.
