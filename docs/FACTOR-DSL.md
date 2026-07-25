# Cytisus Factor DSL

Version: 1
Status: Implemented for deterministic daily fixture research in Prompt 4

## Purpose

The Factor DSL is a typed, deterministic, non-Turing-complete expression language. Native macOS and Windows implementations parse the same definitions and evaluate normalized Longbridge-backed data locally. A research run loads its source dataset once; candidate evaluation does not invoke Longbridge CLI.

The DSL has no variables, assignment, loops, recursion, file access, network access, arbitrary functions, subprocesses, or shell execution.

## Factor definition

Every factor declares:

- `factor_id`
- `factor_type`: `Alpha`, `Risk`, `Regime`, `Liquidity`, or `Execution`
- `target`
- `horizon`
- `universe`
- `required_data`
- `update_frequency`
- `version`

Definitions may also persist a global lifecycle state, per-strategy lifecycle states, and a DSL expression. Quarantine is global. Non-quarantine states may differ by strategy.

## Base fields

| Field | Type | Meaning |
| --- | --- | --- |
| `open` | number | Point-in-time open price |
| `high` | number | Point-in-time high price |
| `low` | number | Point-in-time low price |
| `close` | number | Point-in-time close price |
| `volume` | number | Point-in-time traded volume |
| `returns` | number | Locally derived historical return |
| `market_return` | number | Market reference return |
| `sector_return` | number | Sector reference return |
| `capital_flow` | number | Locally derived capital-flow proxy |

Each observation includes `event_time` and `available_time`. Data with `available_time` before `event_time` is rejected during normalization.

## Operators

| Operator | Arguments | Result | Minimum history and missing behavior |
| --- | --- | --- | --- |
| `lag(x,w)` | series, integer window | series | Adds `w`; propagates missing values |
| `delta(x,w)` | series, integer window | series | Adds `w`; propagates missing values |
| `rolling_mean(x,w)` | series, integer window | series | Full valid window required |
| `rolling_std(x,w)` | series, integer window | series | Full valid window required |
| `rolling_rank(x,w)` | series, integer window | series | Full valid window required |
| `ema(x,w)` | series, integer window | series | Emits after `w` valid observations |
| `rolling_corr(x,y,w)` | two series, integer window | series | Full paired window required |
| `rolling_beta(x,y,w)` | two series, integer window | series | Full paired window required |
| `cross_section_rank(x)` | series | series | Available values on the same date |
| `zscore(x)` | series | series | Available values on the same date |
| `winsorize(x)` | series | series | Five and 95 percent cross-section bounds |
| `sector_neutralize(x)` | series | series | Subtracts date and industry group mean |
| `safe_divide(x,y)` | two series or constants | series | Missing when denominator is near zero |
| `signed_power(x,p)` | series, bounded constant | series | Absolute exponent cannot exceed 3 |
| `min(x,y)` | two series or constants | series | Propagates missing values |
| `max(x,y)` | two series or constants | series | Propagates missing values |
| `conditional(c,x,y)` | three series or constants | series | Positive selects `x`; otherwise `y` |

Every operator definition declares arity, missing-value policy, cross-sectional behavior, temporal safety, and complexity cost.

## Bounds and temporal safety

- Maximum source length: 2048 characters.
- Default maximum expression depth: 8.
- Default maximum operator count: 16.
- Window values must be integers from 1 through 252.
- Numeric constants must be finite and have absolute value no greater than 1000.
- `signed_power` exponents have absolute value no greater than 3.
- Negative or zero windows are rejected as prohibited future references.
- Minimum history is computed before evaluation.
- Unknown fields and operators are rejected.
- No future field, dynamic name, arbitrary code, or shell syntax is accepted.

## Horizons

Production daily schema:

- `1d`
- `3d`
- `5d`
- `10d`
- `20d`
- `60d`
- `120d`
- `252d`

Reserved intraday identifiers are `1m`, `5m`, and `30m`. Prompt 4 does not implement a production intraday engine.

## Candidate search

The deterministic constrained beam search starts from nine economic families:

- Short-term reversal
- Medium-term momentum
- Volatility-adjusted momentum
- Volume shock
- Volatility contraction
- Liquidity
- Capital-flow persistence
- Market-relative strength
- Sector-relative strength

It applies standard-horizon, winsorization, z-score, sector-neutralization, and volatility-scaling mutations. Syntax, temporal safety, minimum history, and data quality provide cheap screening. Only a bounded Top-K beam expands. The tiny fixture run uses beam width 4, Top-K 3, two generations, 24 candidates, depth 8, and 16 operators.

Neighboring-horizon evidence is preferred over an isolated optimum. An otherwise eligible candidate with neighboring-horizon stability below 0.25 is rejected.

## Validation and trials

The implemented funnel is:

```text
Syntax and temporal safety
-> Data quality and minimum history
-> Task-specific target metric
-> Purged chronological OOS windows
-> Stability and multiple-testing penalty
-> Strategy marginal contribution
-> Shadow eligibility
```

Evidence includes coverage, missing rate, task metric, stability, turnover, cost proxy, capacity proxy, existing-factor correlation, neighboring-horizon stability, counterfactual marginal contribution, OOS-window count, and multiple-testing penalty.

Every attempted candidate is appended to the Trial Registry, including rejected and quarantined trials. Normal operation does not delete failed trials. Look-ahead bias, data contamination, train-test leakage, unreproducible output, a definition error, or a missing trial record requires global quarantine.

## Execution integration

Factor outputs never create broker commands. Lifecycle-approved strategy targets and governed capital budgets may produce structured trade intents. The sole execution gateway owns risk decisions, Local Paper netting, simulated fills, virtual allocations, ledger updates, and reconciliation. Factor search has no direct access to Longbridge CLI or either execution adapter.
