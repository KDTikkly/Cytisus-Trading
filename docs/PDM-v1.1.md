# Cytisus v1.1 Product Definition Model

Version: 1.1
Status: Implementation-ready
Repository: KDTikkly/Cytisus-Trading
Primary platforms: macOS 14+ and Windows 11 x64
Product language: English
Document format requirement: ASCII-only repository text
Target release version: 1.1.0

## 1. Repository Baseline

The current repository maintains two native desktop editions:

- A macOS SwiftUI application built directly with `swiftc` and packaged as a Universal 2 DMG.
- A Windows 11 WPF application targeting .NET 8 and published as a self-contained single-file executable.

The two editions currently implement the same offline factor-governance demonstration through separate platform-specific models and views. Both use in-memory sample data. There is no broker connection, persistent application state, strategy process protocol, execution gateway, or shared runtime contract.

The repository also contains:

- A GitHub Actions desktop release workflow.
- Separate macOS and Windows build scripts.
- An English-only ASCII validation script.
- English README, installation, privacy, and sanitization documents.

v1.1 must preserve the native desktop editions and their release paths. It must not replace both applications with Electron, a browser shell, Flutter, or another new cross-platform UI framework.

## 2. Product Definition

Cytisus is a local desktop front end for an automated quantitative trading system.

Cytisus is not a manual trading terminal.

The user may:

- Observe strategy state, health, logs, signals, factor evidence, risk, positions, and automated execution results.
- Configure strategy parameters within platform safety limits.
- Switch a strategy between Paper Only and Live.
- Approve a bounded Live authorization.
- Review automated trade intents, risk decisions, broker orders, fills, allocation results, and audit history.
- Observe and govern factor discovery, promotion, reduction, probation, retirement, and quarantine.

The user may not:

- Create an arbitrary buy or sell order.
- Edit the price or quantity of an automated broker order.
- Submit a discretionary order from the UI.
- Bypass the strategy engine, portfolio allocator, risk checks, or execution gateway.
- Give a strategy process direct access to Longbridge CLI credentials.
- Disable mandatory Cytisus safety limits.

All broker orders must originate from automated strategy trade intents and pass through the Cytisus execution gateway.

## 3. Product Principles

### 3.1 Local-first

Account integration, data collection, factor calculation, strategy execution, logs, settings, and audit data remain on the user's device unless a future version explicitly introduces an optional remote service.

### 3.2 Broker credential isolation

Longbridge CLI is installed and authorized by the user.

Cytisus:

- Does not bundle Longbridge CLI.
- Does not download or silently install Longbridge CLI.
- Does not read, copy, export, or store Longbridge OAuth tokens.
- Does not ask the user to paste broker secrets into the Cytisus UI.
- Uses the existing local Longbridge CLI authorization state.
- Invokes Longbridge through a restricted adapter using argument arrays, never shell string concatenation.
- Redacts sensitive authentication and account fields from logs.

### 3.3 Automated execution only

Paper and Live execution share the same intent, risk, netting, allocation, ledger, and audit pipeline. Only the final broker adapter differs.

No UI path may create a manual order.

### 3.4 Risk contracts override strategy declarations

A strategy may describe recommended parameter ranges and operating requirements. Cytisus may impose stricter ranges, confirmation requirements, mode restrictions, and risk limits. A strategy may never weaken the platform safety contract.

### 3.5 Native UI, shared behavior

macOS remains SwiftUI and Windows remains WPF.

v1.1 does not require a shared compiled cross-platform core. Instead, platform parity is maintained through:

- Shared JSON schemas.
- Shared fixture files.
- Shared protocol documents.
- Shared deterministic algorithm specifications.
- Shared acceptance scenarios.
- Equivalent platform-specific implementations.

This avoids introducing a third runtime solely to share code while still preventing semantic drift.

## 4. Goals

v1.1 must:

1. Reposition both desktop editions from an offline demo to an automated quantitative operations console.
2. Introduce local Longbridge CLI discovery, capability inspection, and JSON-based data access.
3. Introduce persistent local stores for settings, audit events, market snapshots, universe snapshots, strategies, parameters, factors, and virtual ledgers.
4. Introduce a restricted local strategy process protocol.
5. Introduce mixed official and third-party strategy registration.
6. Introduce dynamic strategy parameter forms with risk-tiered activation.
7. Introduce Paper Only and Live modes with a global Live lock.
8. Introduce bounded Live authorizations.
9. Introduce a unified execution gateway.
10. Introduce strategy virtual positions and broker net-position reconciliation.
11. Introduce internal netting and partial-fill allocation.
12. Introduce a dynamic strategy capital allocator.
13. Introduce probabilistic market regime estimation.
14. Introduce a Longbridge-backed dynamic security universe.
15. Introduce multi-task factor definitions.
16. Introduce a constrained Factor DSL and deterministic candidate search.
17. Introduce multi-evidence factor validation and lifecycle governance.
18. Preserve English-only, ASCII-only repository text.
19. Produce macOS and Windows 1.1.0 release artifacts.
20. Keep tests focused on safety boundaries and deterministic algorithms.

## 5. Non-goals

v1.1 does not include:

- Manual order entry.
- An order ticket.
- Manual single-order cancellation.
- Direct strategy access to Longbridge CLI.
- Bundled broker credentials.
- Cloud-hosted strategy execution.
- Mobile applications.
- A strategy marketplace.
- Social trading or copy trading.
- Production-grade high-frequency trading.
- Sub-millisecond execution.
- Unlimited symbolic search.
- General arbitrary code execution inside Factor DSL.
- A deep-learning factor discovery dependency.
- A complete historical constituent database for every market.
- Full options analytics.
- Guaranteed profitability or investment advice.

## 6. Platform Strategy

### 6.1 macOS

- SwiftUI.
- macOS 14 or later.
- Universal 2 artifact.
- Existing glass visual language retained.
- Existing direct `swiftc` build may remain if maintainable.
- System frameworks and lightweight local code are preferred.
- SQLite3 may be linked directly if used.

### 6.2 Windows

- WPF.
- .NET 8.
- Windows 11 x64 is the required v1.1 release target.
- Self-contained single-file executable retained.
- Existing glass visual language retained.
- Microsoft.Data.Sqlite may be used if SQLite is selected.

### 6.3 Parity policy

Both editions must implement the same product states and safety behavior.

Pixel-level visual equality is not required. Semantic parity is required for:

- CLI status.
- Strategy modes.
- Parameter governance.
- Risk decisions.
- Factor states.
- Trade-intent states.
- Internal transfers.
- Broker orders and fills.
- Virtual allocations.
- Reconciliation alerts.
- Audit event categories.

### 6.4 Shared repository assets

Add platform-neutral assets under paths such as:

```text
docs/
schemas/
fixtures/
```

Recommended schemas:

```text
schemas/strategy-manifest.schema.json
schemas/strategy-message.schema.json
schemas/factor-definition.schema.json
schemas/factor-trial.schema.json
schemas/live-authorization.schema.json
schemas/audit-event.schema.json
```

Recommended fixtures:

```text
fixtures/longbridge/
fixtures/strategies/
fixtures/factors/
fixtures/execution/
```

## 7. High-level Architecture

```text
Native Desktop UI
  |
  +-- Application State
  +-- Settings and Capability State
  +-- Local Persistence
  +-- Longbridge CLI Adapter
  +-- Strategy Registry and Runtime
  +-- Parameter Governance
  +-- Market Data and Universe Service
  +-- Factor Engine
  +-- Regime Engine
  +-- Portfolio Allocator
  +-- Execution Gateway
  +-- Paper Broker / Live Broker Adapter
  +-- Virtual Ledger and Reconciliation
  +-- Logs and Audit Store
```

The UI may call typed application services. It must not directly construct CLI commands, parse broker JSON, run strategy processes, or implement allocation algorithms inside views.

## 8. Longbridge CLI Integration

### 8.1 Installation and authorization boundary

The user installs Longbridge CLI separately and completes authorization using the CLI's supported local flow.

Cytisus stores only:

- The selected executable path.
- Capability inspection results.
- Last successful check time.
- Non-sensitive market permission summaries.
- Non-sensitive account aliases where appropriate.
- Timeouts and cache settings.

Cytisus must not access the CLI token storage directory.

### 8.2 Capability discovery

The adapter must inspect the locally installed CLI rather than assuming every command and flag is stable.

The implementation should:

1. Resolve the executable from user settings or the system path.
2. Read the CLI version.
3. Inspect relevant help output when required.
4. Run non-destructive status and connectivity checks.
5. Prefer machine-readable JSON output.
6. Record supported capabilities.
7. Degrade gracefully when a command or permission is unavailable.

### 8.3 Process safety

Every CLI invocation must:

- Use an executable path and argument list.
- Avoid `sh -c`, `cmd /c`, `powershell -Command`, or equivalent command-string execution.
- Have a timeout.
- Support cancellation.
- Capture exit code, stdout, and stderr separately.
- Apply output-size limits.
- Redact sensitive fields before logging.
- Reject arbitrary arguments originating from a strategy process.
- Be categorized as read-only data access or broker execution.

### 8.4 Fixture mode

Both applications must support a fixture mode that exercises the complete parsing and UI path without a real CLI, network, or account.

Fixture mode is the default automated-test mode.

## 9. Local Persistence

Use a lightweight local SQLite store without an ORM, or an equivalently durable structured store if a platform limitation is documented.

Preferred logical tables:

```text
app_settings
cli_capabilities
market_bars
market_snapshots
fundamental_snapshots
universe_snapshots
strategy_manifests
strategy_parameters
parameter_changes
strategy_events
factor_definitions
factor_trials
factor_observations
factor_evidence
trade_intents
risk_decisions
internal_transfers
broker_orders
broker_fills
virtual_allocations
virtual_positions
broker_positions
reconciliation_events
audit_events
application_logs
```

Persistence requirements:

- Schema versioning.
- Idempotent migrations.
- UTC timestamps.
- Stable identifiers.
- No broker tokens.
- Bounded log retention.
- Durable audit events.
- Deterministic fixture reset.
- Safe handling of database corruption or migration failure.

Market data records must distinguish:

- `event_time`: when the market event occurred.
- `available_time`: when the strategy could legally observe it.
- `collected_at`: when Cytisus collected it.
- `source_version`: CLI and adapter version.
- `adjustment_mode`: price-adjustment mode.
- `data_hash`: source-response digest.

Backtests and factor validation must use `available_time`, not revised future knowledge.

## 10. Strategy Integration

### 10.1 Mixed strategy model

Cytisus supports:

- Official strategies distributed with the product.
- User and third-party local strategies.

Both run as independent local processes under the same protocol.

### 10.2 Strategy manifest

A manifest declares:

```json
{
  "strategy_id": "cross-sectional-multifactor",
  "name": "Cross-Sectional Multi-Factor",
  "version": "1.1.0",
  "entrypoint": "./strategy",
  "supported_modes": ["paper", "live"],
  "required_data": ["daily_bars", "market_status"],
  "parameter_schema_version": 1
}
```

The manifest does not grant broker access.

### 10.3 Transport

v1.1 uses NDJSON over standard input and standard output.

Core-to-strategy messages include:

```text
initialize
load_parameters
apply_parameters
market_snapshot
allocation_budget
start_cycle
pause
resume
shutdown
```

Strategy-to-core messages include:

```text
ready
heartbeat
log
health
signal
factor_observation
target_position
trade_intent
cycle_complete
error
```

Each message includes:

```text
event_id
correlation_id
strategy_id
strategy_version
cycle_id
timestamp
message_type
payload
```

### 10.4 Runtime controls

Cytisus may:

- Start a configured strategy.
- Pause it.
- Resume it.
- Stop it.
- Restart it after a documented fault policy.
- Reject malformed messages.
- Stop accepting new intents after heartbeat loss.
- Apply resource and message-size limits.

The user does not manually trigger a single trade.

## 11. Parameter Governance

### 11.1 Mixed ownership

A strategy supplies:

- Parameter key.
- Label.
- Description.
- Type.
- Default value.
- Recommended range.
- Recommended activation mode.

Cytisus supplies or overrides:

- Hard minimum and maximum.
- Risk tier.
- Live-mode mutability.
- Required preview.
- Required pause.
- Required confirmation.
- Activation point.
- Rollback requirements.

### 11.2 Risk tiers

Low-risk parameters:

- May activate during a running strategy.
- Must still produce an audit event.

Medium-risk parameters:

- Activate at the next strategy cycle, bar boundary, or rebalance boundary.

High-risk parameters:

- Block new risk.
- Require a clear old-versus-new preview.
- Require explicit confirmation.
- Create a new parameter version.
- Activate only at a safe boundary.
- Preserve a rollback reference.

### 11.3 Audit fields

Every change records:

```text
change_id
strategy_id
parameter_key
old_value
new_value
requested_at
effective_at
requested_by
risk_tier
parameter_version
activation_mode
result
rollback_version
```

## 12. Paper Only and Live

### 12.1 Mode hierarchy

```text
Global Live Lock
  -> Per-strategy mode
  -> Live authorization
  -> Execution gateway
  -> Live broker adapter
```

Defaults:

```text
Global Live Lock = OFF
Every strategy = Paper Only
```

### 12.2 Paper Only

Paper Only:

- Uses live or cached market data.
- Runs the complete strategy and risk path.
- Produces trade intents.
- Applies internal netting and allocation.
- Uses a local paper broker.
- Produces simulated fills and virtual positions.
- Never calls a live broker execution command.

### 12.3 Live authorization

A Live authorization includes:

```text
authorization_id
strategy_id
allowed_markets
allowed_symbols_or_universe
maximum_capital
maximum_strategy_allocation
maximum_single_position_exposure
maximum_daily_loss
maximum_drawdown
maximum_order_frequency
outside_regular_hours_permission
parameter_version
valid_from
expires_at
```

An expired, missing, or incompatible authorization blocks new Live risk.

### 12.4 Live to Paper transition

When switching a running Live strategy to Paper Only, the user chooses:

1. Stop opening risk and continue managing existing real positions.
2. Freeze the strategy and leave real positions unmanaged by that strategy.
3. Start a controlled automated exit.

The default is option 1.

The transition itself must not create an arbitrary manual order. Controlled exit orders are generated by the strategy or a defined risk-exit policy through the execution gateway.

## 13. Execution Gateway

### 13.1 Sole broker path

Only the execution gateway may submit a broker order through Longbridge CLI.

Strategies submit structured trade intents.

### 13.2 Processing order

```text
Mode gate
-> Live authorization
-> Data freshness
-> Market status
-> Strategy health
-> Capital budget
-> Position limits
-> Duplicate-intent check
-> Internal netting
-> Broker order construction
-> Broker submission
-> Fill allocation
-> Virtual ledger update
-> Reconciliation
-> Audit
```

### 13.3 Intent fields

```text
intent_id
strategy_id
strategy_version
cycle_id
symbol
target_quantity_or_target_weight
priority
allow_partial
minimum_effective_fill
time_to_live
reason_code
parameter_version
created_at
```

### 13.4 Duplicate protection

The gateway must use stable intent identifiers and correlation identifiers to prevent retries from creating duplicate broker risk.

## 14. Strategy Virtual Ledger

The broker account holds a net position. Cytisus maintains strategy-level virtual ownership.

Each strategy ledger tracks:

- Target position.
- Virtual quantity.
- Cost basis.
- Realized P&L.
- Unrealized P&L.
- Capital usage.
- Risk contribution.
- Intent ownership.
- Fill allocation.
- Internal-transfer history.

The sum of virtual positions must reconcile with the broker net position, subject to documented residual handling.

A reconciliation failure must:

- Block new risk for the affected symbol.
- Create a critical risk event.
- Remain visible until resolved.
- Preserve all source records.

## 15. Internal Netting

For the same security and settlement cycle, opposing strategy intents are internally netted before a broker order is submitted.

Example:

```text
Strategy A wants to buy 100.
Strategy B wants to sell 60.
Internal transfer = 60.
Broker net order = buy 40.
```

An internal transfer:

- Is not a broker fill.
- Is separately labeled.
- Has a documented reference price.
- Preserves both strategies' intent ownership.
- Is included in strategy attribution.
- Is separately visible in the Execution UI.

## 16. Partial-fill Allocation

Use mixed allocation:

1. Group strategies by priority.
2. Allocate within the same priority in proportion to unmet demand.
3. Enforce each strategy's minimum effective fill.
4. Reallocate unusable fragments.
5. Fully satisfy non-partial strategies or allocate zero.
6. Record unfilled demand as `Allocation Shortfall`.

The allocator must be deterministic for identical inputs.

## 17. Dynamic Capital Allocation

Do not use a fixed capital pool per strategy.

Use a layered allocator:

```text
Strategy health filter
-> Total portfolio risk budget
-> Risk-parity or minimum-variance base
-> Capped expected-alpha tilt
-> Correlation penalty
-> Drawdown penalty
-> Capacity penalty
-> Liquidity penalty
-> Turnover limiter
-> Final strategy budget
```

The expected-alpha score combines:

- Long-term out-of-sample evidence.
- Recent Live performance.
- Recent Paper performance.
- Current signal strength.
- Market-regime fit.
- Confidence calibration.
- Data quality.
- Model uncertainty.

Rules:

- Live, Paper, and backtest evidence are not weighted equally.
- New strategies receive conservative priors.
- Alpha tilt is capped.
- Weight changes are smoothed.
- Recent winners cannot consume unbounded capital.
- Every allocation result includes an explanation breakdown.

## 18. Market Regime Engine

The regime engine outputs probabilities, not one forced label:

```text
Trend
Range
High Volatility
Crisis
```

v1.1 uses a lightweight deterministic ensemble of:

- Interpretable rule scores.
- Statistical feature-distance scores.
- Cross-asset risk indicators.
- Strategy-reported environment fit.

Regime uncertainty lowers the total portfolio risk budget.

The interface must allow a future HMM or other statistical model without making it a v1.1 dependency.

## 19. Dynamic Security Universe

Longbridge CLI is the primary source for available market and security data.

Universe sources may include:

- Index or ETF constituents available through the installed CLI.
- User watchlists.
- Current broker positions.
- Strategy-configured static candidates.

Daily universe generation:

```text
Configured market scope
-> Tradable status
-> Price filter
-> Liquidity filter
-> Listing-age filter
-> History-coverage filter
-> Suspension and delisting filter
-> Abnormal-security filter
-> Strategy-specific filter
-> Daily universe snapshot
```

A snapshot stores:

```text
date
symbol
included
reason
liquidity_metrics
data_coverage
industry
rule_version
source_version
```

An already-held security removed from the universe becomes Reduce Only.

v1.1 does not require a complete historical constituent service for every market.

## 20. Multi-task Factor Model

Factor types:

```text
Alpha
Risk
Regime
Liquidity
Execution
```

Each factor declares:

```text
factor_id
factor_type
target
horizon
universe
required_data
update_frequency
version
```

Evaluation differs by type:

- Alpha: Rank IC, ICIR, quantile monotonicity, after-cost marginal return.
- Risk: volatility error, correlation error, tail-risk coverage.
- Regime: probability calibration, transition delay, conditional strategy performance.
- Liquidity: spread, capacity, and volume prediction error.
- Execution: fill probability, slippage error, and impact-cost error.

A factor does not need direct return contribution if its task is risk or execution quality.

## 21. Standard Horizons

Allowed daily horizons:

```text
1d
3d
5d
10d
20d
60d
120d
252d
```

Intraday schema may reserve:

```text
1m
5m
30m
```

Intraday production research is not a v1.1 acceptance requirement.

A factor declares an economically reasonable horizon family. Candidate search may not select an arbitrary isolated optimum. Neighboring horizons must show directional stability.

## 22. Factor Data Source

Longbridge CLI is the primary raw-data input.

Phase-one data domains:

- Price.
- Volume.
- Realized volatility.
- Liquidity proxies.
- Capital flow where available.
- Market-relative performance.
- Sector-relative performance.

Reserved future domains:

- Point-in-time fundamentals.
- Earnings release timing.
- Corporate actions.
- Valuation and quality.
- Analyst expectations.
- Options.
- Macro data.
- News and alternative data.

Longbridge collects data. Cytisus performs local normalization, caching, time alignment, factor calculation, candidate search, validation, and lifecycle governance.

## 23. Factor DSL

Allowed base fields include:

```text
open
high
low
close
volume
returns
market_return
sector_return
capital_flow
```

Allowed operators include:

```text
lag
delta
rolling_mean
rolling_std
rolling_rank
ema
rolling_corr
rolling_beta
cross_section_rank
zscore
winsorize
sector_neutralize
safe_divide
signed_power
min
max
conditional
```

Every operator declares:

- Input type.
- Output type.
- Minimum history.
- Missing-value behavior.
- Cross-sectional compatibility.
- Temporal-safety properties.
- Complexity cost.

The engine enforces:

- Maximum expression depth.
- Maximum operator count.
- No future reference.
- Valid windows.
- No arbitrary code.
- No arbitrary shell command.
- No unbounded constant fitting.
- Deterministic evaluation.

## 24. Factor Discovery

v1.1 uses four controlled inputs:

1. Economic hypothesis seeds.
2. Standard-horizon variations.
3. Normalization, neutralization, and risk-scaling variations.
4. Deterministic constrained beam search.

Recommended seeds:

- Short-term reversal.
- Medium-term momentum.
- Volatility-adjusted momentum.
- Volume shock.
- Volatility contraction.
- Liquidity.
- Capital-flow persistence.
- Market-relative strength.
- Sector-relative strength.

Beam search:

```text
Seed expressions
-> Legal local transformations
-> Cheap screening
-> Keep Top K
-> Expand one level
-> Stop at complexity or generation limit
```

Do not make genetic programming, MCTS, PyTorch, TensorFlow, or an LLM-generated arbitrary formula engine a v1.1 requirement.

## 25. Trial Registry

Every attempted factor candidate must be recorded, including failures.

Fields include:

```text
trial_id
factor_family
expression
parameters
dataset_version
universe_version
search_algorithm
generation
oos_windows
metrics
result
rejection_reason
created_at
```

Keeping only successful candidates is prohibited.

Candidate scoring accounts for:

- Number of attempted variants.
- Candidate correlation.
- Expression complexity.
- Parameter sensitivity.
- Multiple-testing risk.
- Trading cost.
- Turnover.
- Capacity.
- Existing-factor redundancy.

## 26. Factor Validation

Validation funnel:

```text
Syntax and temporal safety
-> Data quality
-> Basic predictive metrics
-> Purged walk-forward OOS
-> Stability and multiple-testing penalty
-> Strategy marginal contribution
-> Shadow observation
```

Evidence may include:

- Coverage.
- Missing rate.
- Rank IC.
- ICIR.
- Directional consistency.
- Quantile monotonicity.
- Cross-period stability.
- Cross-regime stability.
- Turnover.
- Cost.
- Capacity.
- Correlation with existing factors.
- Counterfactual removal result.
- Neighboring-horizon stability.

Immediate rejection or quarantine conditions:

- Look-ahead bias.
- Data contamination.
- Train-test leakage.
- Unreproducible result.
- Missing trial history.
- Untrusted data source.

## 27. Factor Lifecycle

Lifecycle:

```text
Candidate
-> Shadow
-> Active
-> Reduced
-> Probation
-> Retired
```

Any state may transition to:

```text
Quarantined
```

Definitions:

- Candidate: passed inexpensive research screening.
- Shadow: calculated on current data but cannot expand Live risk.
- Active: permitted in production strategy logic.
- Reduced: automatically down-weighted while evidence continues.
- Probation: generally blocked from adding risk.
- Retired: removed from a strategy after high-confidence deterioration.
- Quarantined: globally blocked because of data or methodology safety failure.

A factor may be retired in one strategy and remain active in another. Quarantine is global.

## 28. Factor Retirement and Recovery

Use multi-evidence, multi-timescale governance:

- Short-term decay.
- Medium-term OOS decay.
- Long-term cross-regime stability.
- Change-point probability.
- Strategy marginal contribution.
- Counterfactual removal performance.
- Cost and capacity.
- Redundancy and replacement quality.
- Data quality.

Rules:

- Data contamination, look-ahead bias, or definition error -> Quarantined immediately.
- Short-term deterioration with stable long-term evidence -> Reduced.
- Failure limited to one regime -> Regime Conditional.
- Repeated OOS deterioration -> Probation.
- High change-point probability plus sustained counterfactual improvement -> Retired.
- Highly redundant factor -> Prefer the simpler, more stable, and lower-cost alternative.

Risk contraction may occur automatically.

Risk expansion requires renewed evidence.

Retired or Quarantined factors may not jump directly to Active.

## 29. User Interface

Both editions implement these primary areas:

### Dashboard

- CLI status.
- Global Live lock.
- Paper and Live strategy counts.
- Strategy health.
- Market-regime probabilities.
- Capital usage.
- Portfolio risk.
- High-priority alerts.
- Latest strategy cycles.

### Strategies

- Strategy identity and version.
- Health and heartbeat.
- Paper Only or Live mode.
- Parameter version.
- Capital budget.
- Signals.
- Target positions.
- Recent intents.
- Dynamic parameter form.
- Parameter activation and rollback history.

### Factor Governance

- Global and strategy-level factor status.
- Factor task type.
- Horizon.
- Health evidence.
- OOS evidence.
- Regime performance.
- Marginal contribution.
- Trial Registry.
- State-change reasons.

### Portfolio

- Broker net positions.
- Strategy virtual positions.
- Internal transfers.
- Capital allocation.
- Realized and unrealized P&L.
- Reconciliation state.

### Execution

Read-only presentation of:

- Strategy Intent.
- Risk Decision.
- Internal Transfer.
- Broker Order.
- Broker Fill.
- Virtual Allocation.
- Allocation Shortfall.

No manual order button is permitted.

### Logs

- Time.
- Severity.
- Strategy.
- Module.
- Correlation ID.
- Cycle ID.
- Message.
- Structured context.
- Search and filters.

### Data and Universe

- CLI path and version.
- Authorization status summary.
- Data permissions summary.
- Data freshness.
- Universe snapshots.
- Data gaps.
- Cache size.
- Last synchronization.

### Settings

- CLI path.
- Cache directory.
- Default market.
- Process timeout.
- Data-retention limits.
- Risk safety overrides.
- Global Live lock.
- Fixture mode.
- Log retention.

## 30. Logging and Audit

Application logs are operational and may follow a retention policy.

Audit events are durable and record:

- Parameter changes.
- Mode changes.
- Live authorization.
- Strategy lifecycle.
- Factor lifecycle.
- Risk rejection.
- Internal transfer.
- Broker order and fill.
- Virtual allocation.
- Reconciliation failure.
- Safety override.

Sensitive fields must be redacted:

- Tokens.
- Secrets.
- Authorization codes.
- Full account numbers.
- Raw authentication output.
- Sensitive user-local paths when not required.

## 31. Failure and Degradation

### CLI missing

- App starts normally.
- Settings shows installation guidance.
- Fixture mode remains available.
- Live is unavailable.

### CLI unauthenticated

- App shows the status.
- User is directed to complete authorization through the CLI.
- Cytisus does not display or read the token.

### Permission unavailable

- Dependent data is marked unavailable.
- No synthetic replacement is silently substituted.
- Affected factors become Data Unavailable.
- Live strategies cannot add risk based on stale or missing required data.

### Stale data

- Paper may continue with a clear warning if configured.
- Live new-risk intents are blocked.
- Existing positions follow the approved transition policy.

### Strategy heartbeat loss

- No new intents are accepted.
- Strategy becomes Unhealthy.
- Existing-position behavior follows its approved policy.

### Reconciliation failure

- New risk for the affected symbol is blocked.
- A critical alert is created.
- Audit and source records are preserved.

## 32. Default Official Strategy

Provide one official demonstration strategy, defaulting to Paper Only:

```text
Cross-Sectional Multi-Factor
```

Suggested factor inputs:

- 20-day momentum.
- 60-day momentum.
- 20-day realized volatility.
- Volume or liquidity.
- Market-relative strength.
- Sector-relative strength.

The strategy must:

- Exercise parameter schemas.
- Exercise factor observations.
- Produce target positions.
- Produce structured intents.
- Use the same execution path as third-party strategies.

It must not claim production-quality alpha.

## 33. Testing Strategy

The goal is high-value safety validation, not broad coverage.

Required deterministic tests:

1. Global Live lock blocks all Live broker submission.
2. Paper mode never invokes the Live broker adapter.
3. High-risk parameter changes cannot bypass pause, preview, confirmation, and versioning.
4. Internal netting produces the expected net broker quantity.
5. Partial fills allocate deterministically under priority and minimum-fill constraints.
6. Factor safety failures transition directly to Quarantined.
7. Factor risk expansion cannot bypass promotion evidence.
8. Sensitive fields are redacted.
9. Longbridge fixture JSON parses correctly.
10. Virtual positions reconcile with the expected broker net position.

Testing rules:

- Use local fixtures.
- Do not require a real Longbridge account.
- Do not use network access.
- Do not send real orders.
- Do not add UI snapshot tests in v1.1.
- Do not create a large randomized test matrix.
- Do not generate coverage reports solely to increase coverage.
- Run only targeted tests during stages 1 through 4.
- Run one complete cross-platform release workflow in stage 5.
- After a failure, rerun the failing target, then one final smoke run.

## 34. Release and Repository Requirements

Release version:

```text
1.1.0
```

Artifacts:

```text
dist/Cytisus-Trading-1.1.0-universal.dmg
dist/Cytisus-Trading-1.1.0-win11-x64.exe
```

Preserve:

- macOS Developer ID signing support.
- Apple notarization support.
- Windows self-contained single-file publishing.
- GitHub Actions release publishing.
- English-only ASCII validation.

Update:

```text
README.md
INSTALL.txt
PRIVACY.md
SANITIZATION.json
Resources/Info.plist
Windows/CytisusTrading.Windows.csproj
tools/build_dmg.sh
tools/build_win11.ps1
.github/workflows/desktop-release.yml
```

Add:

```text
docs/PDM-v1.1.md
docs/STRATEGY-PROTOCOL.md
docs/FACTOR-DSL.md
docs/LONGBRIDGE-INTEGRATION.md
docs/CODEX-v1.1-PROMPT-SERIES.md
schemas/
fixtures/
```

Never commit:

- Broker tokens.
- Real account identifiers.
- Real positions.
- Real orders.
- Authentication output.
- User-specific absolute paths.
- Personal logs.

## 35. Staged Delivery Plan

### Stage 1: Foundation and parity contracts

- Add the v1.1 documentation.
- Upgrade version metadata and artifact names.
- Refactor both apps into UI, domain, and service boundaries.
- Add shared schemas and fixtures.
- Add persistence foundations and audit/log models.
- Preserve existing demo behavior through repositories rather than view-owned sample state.

### Stage 2: Longbridge data and universe

- Add secure CLI adapters.
- Add capability and status inspection.
- Add fixture mode.
- Add market-data caching.
- Add point-in-time fields.
- Add dynamic universe snapshots.
- Add Data and Universe and Settings UI states.

### Stage 3: Strategy runtime and governance

- Add strategy registry and NDJSON runtime.
- Add official sample strategy.
- Add parameter schemas and risk-tiered activation.
- Add global Live lock, Paper Only, and Live authorization models.
- Add Strategies, Dashboard, and Logs behavior.
- Keep Live broker submission disabled.

### Stage 4: Quant research and allocation

- Add multi-task factor definitions.
- Add Factor DSL.
- Add deterministic beam search and Trial Registry.
- Add validation and lifecycle governance.
- Add probabilistic regime engine.
- Add dynamic strategy capital allocator.
- Upgrade Factor Governance UI.

### Stage 5: Execution, ledger, parity, and release

- Add execution gateway.
- Add paper broker.
- Add tightly gated Longbridge Live broker adapter.
- Add internal netting.
- Add partial-fill allocation.
- Add virtual ledger and reconciliation.
- Add Portfolio and Execution pages.
- Complete cross-platform parity.
- Run final release workflow.
- Produce both 1.1.0 artifacts.

## 36. Acceptance Criteria

v1.1 is complete only when:

- Both native applications start without Longbridge CLI installed.
- Both support fixture mode.
- Both discover or accept a local CLI path.
- Both display CLI version and non-sensitive status.
- Both can parse at least one historical and one current market-data fixture.
- Both create a daily universe snapshot.
- Both can run the official strategy in Paper Only.
- Both show strategy health, signals, targets, and intents.
- Both support dynamic parameter forms.
- High-risk parameters follow the required activation flow.
- Global Live lock defaults to OFF.
- No manual order entry exists.
- Paper mode cannot invoke Live execution.
- Live mode requires a compatible authorization.
- Execution gateway risk decisions are visible.
- Internal transfers are separate from broker fills.
- Partial fills are allocated deterministically.
- Virtual strategy positions reconcile with broker net positions.
- Factor candidates can be generated through constrained beam search.
- Failed factor trials are retained.
- Factor lifecycle evidence is visible.
- Safety failures cause quarantine.
- Regime probabilities are visible.
- Dynamic strategy capital allocation is visible and explainable.
- Audit events exist for all critical changes.
- Sensitive fields are redacted.
- ASCII validation passes.
- macOS release build succeeds.
- Windows release build succeeds.
- README and privacy documents describe actual v1.1 behavior.
- The final report identifies any unimplemented limitation honestly.

## 37. Implemented v1.1.0 release boundary

The user-facing label for the serialized `PaperOnly` state is `Local Paper`. Local Paper is fully independent from Longbridge CLI installation, authentication, connectivity, capability support, and account availability.

v1.1.0 implements the sole execution gateway, deterministic Local Paper Broker, internal netting, partial-fill allocation, virtual strategy ledger, reconciliation risk blocks, persistent alerts, non-trading diagnostics, and read-only Portfolio and Execution views on both native platforms.

The Live Longbridge adapter is an intentional process-free rejecting boundary in v1.1.0. Real order submission was not validated. Longbridge Terminal authentication, verified command mapping, and any separate Longbridge Paper account channel are deferred to v1.1.3.
