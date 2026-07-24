# Cytisus Factor DSL

Version: 1
Status: Contract only in Prompt 1

## Purpose

The Factor DSL is a constrained, deterministic expression language for later v1.1 research passes. Prompt 1 defines contracts and fixtures only. It does not implement parsing, evaluation, or candidate search.

## Allowed base fields

- `open`
- `high`
- `low`
- `close`
- `volume`
- `returns`
- `market_return`
- `sector_return`
- `capital_flow`

## Allowed operators

- `lag`
- `delta`
- `rolling_mean`
- `rolling_std`
- `rolling_rank`
- `ema`
- `rolling_corr`
- `rolling_beta`
- `cross_section_rank`
- `zscore`
- `winsorize`
- `sector_neutralize`
- `safe_divide`
- `signed_power`
- `min`
- `max`
- `conditional`

Each implementation must declare input and output types, minimum history, missing-value behavior, cross-sectional compatibility, temporal-safety behavior, and complexity cost for every operator.

## Standard daily horizons

- `1d`
- `3d`
- `5d`
- `10d`
- `20d`
- `60d`
- `120d`
- `252d`

Reserved intraday horizons are `1m`, `5m`, and `30m`. Intraday production research is not required for v1.1.

## Factor lifecycle identifiers

- `Candidate`
- `Shadow`
- `Active`
- `Reduced`
- `Probation`
- `Retired`
- `Quarantined`

## Required restrictions

- No future reference.
- No arbitrary code or shell execution.
- No invalid or unbounded windows.
- No unbounded constant fitting.
- Maximum expression depth and operator count.
- Deterministic evaluation for identical inputs.
- Explicit missing-value behavior.
- Trial records for both accepted and rejected candidates.

Look-ahead bias, contamination, leakage, unreproducible results, or missing trial history must result in rejection or `Quarantined`.
