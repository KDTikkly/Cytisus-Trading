# Cytisus v1.1.2 Product Definition Model

Version: 1.1.2
Status: Planned incremental release
Repository: KDTikkly/Cytisus-Trading
Dependencies: v1.1.0 and v1.1.1 must be complete and accepted first
Platforms: macOS 14+ and Windows 11 x64
Language: English
Repository text: ASCII only

## 1. Release Purpose

Cytisus v1.1.2 adds local algorithm development and accelerated local computation.

It must reuse, not duplicate:

- v1.1.0 strategy, factor, risk, execution, audit, and Longbridge foundations.
- v1.1.1 model provider, secure API key, primary model, and fallback model foundations.

The release focuses on:

- Local algorithm projects.
- A shared local Quant Worker.
- CPU, GPU, and NPU discovery.
- Apple Metal and MPS.
- NVIDIA CUDA.
- AMD ROCm or HIP.
- Intel oneAPI or SYCL.
- Supported NPU inference backends.
- Local backtesting and optimization.
- Local neural-network training.
- ONNX model management.
- Agent-assisted code and strategy development.
- Custom execution-algorithm development.
- Expanded Longbridge account and authorization management.
- Structured Agent order intents.
- No manual order entry.

## 2. System Roles

```text
Agent API
= understands user intent, creates project patches and compute jobs,
  explains results, and creates structured Agent order intents

Local Quant Worker
= runs local factors, backtests, optimization, training, inference,
  strategy logic, and execution-algorithm logic

Longbridge CLI
= provides market data, account data, and approved broker operations

Execution Gateway
= enforces authorization, risk, deduplication, audit, and broker safety
```

The Agent must not:

- Execute arbitrary shell commands.
- Read Longbridge OAuth tokens.
- Construct unrestricted CLI arguments.
- Run numerical workloads through repeated remote calls.
- Bypass the Quant Worker.
- Bypass the Execution Gateway.

The Quant Worker must not:

- Read model-provider API keys.
- Read Longbridge token files.
- Call Longbridge CLI outside the existing adapter.
- Submit broker operations outside the Execution Gateway.

## 3. Incremental Scope Rule

This document defines only v1.1.2 additions.

Existing v1.1.0 and v1.1.1 implementations remain authoritative.

Do not create duplicate:

- Strategy runtime.
- Factor lifecycle.
- Execution Gateway.
- Virtual ledger.
- Audit store.
- Model provider store.
- Secure secret store.
- Longbridge CLI adapter.

## 4. In Scope

1. Shared local Quant Worker.
2. Controlled Python research and strategy runtime.
3. Native accelerated compute layer.
4. CPU, GPU, and NPU device discovery.
5. Apple Metal, MPS, Accelerate, and supported Core ML paths.
6. NVIDIA CUDA and ONNX Runtime CUDA.
7. AMD ROCm or HIP and supported AMD inference providers.
8. Intel oneAPI or SYCL, OpenVINO, and supported Intel NPU providers.
9. Supported Windows NPU execution providers.
10. CPU fallback for all required functions.
11. Compute jobs with progress, cancellation, and limits.
12. Local algorithm project creation and versioning.
13. Local factor calculation.
14. Local backtesting and walk-forward validation.
15. Local parameter and model optimization.
16. Local neural-network training.
17. ONNX import, export, versioning, validation, and deployment.
18. Agent-generated project patches.
19. Agent-generated compute jobs.
20. Agent-assisted error fixing and result explanation.
21. Local execution-algorithm development.
22. Expanded Longbridge account discovery and mapping.
23. Agent order intents under bounded authorization.
24. Cross-platform UI for projects, compute, training, models, Agent activity, and accounts.
25. Release version update to 1.1.2.

## 5. Out of Scope

- Manual order ticket.
- Manual Buy or Sell buttons.
- Manual discretionary order creation.
- Cloud compute.
- Distributed training.
- Multi-machine clusters.
- Multi-user collaboration.
- Strategy marketplace.
- Remote notebook hosting.
- Cloud source synchronization.
- General-purpose chat unrelated to Cytisus projects.
- Unlimited autonomous Agent loops.
- Arbitrary local file access.
- Arbitrary shell access.
- A second broker.
- Guaranteed profitability.

## 6. Architecture

```text
SwiftUI macOS UI --------+
                         |
WPF Windows UI ----------+---- Local Application Services
                         |       |
Selected Agent Model ----+       +-- Project Registry
                                 +-- Agent Control Service
                                 +-- Compute Device Manager
                                 +-- Compute Job Scheduler
                                 +-- ONNX Model Registry
                                 +-- Longbridge Account Service
                                 +-- Existing Execution Gateway
                                           |
                                           v
                                    Local Quant Worker
                                    +-- Python Runtime
                                    +-- Native Compute Core
                                    +-- Backend Adapters
                                    +-- Training Runtime
                                    +-- ONNX Runtime
                                    +-- Strategy Sandbox
                                           |
                                           v
                                    Existing Longbridge CLI Adapter
```

The Quant Worker runs as a separate local process.

A worker crash must not terminate the desktop UI.

## 7. Quant Worker Protocol

Use a typed local protocol.

Preferred transport:

- Unix Domain Socket on macOS.
- Named Pipe on Windows.
- NDJSON or length-prefixed JSON.

Required fields:

```text
request_id
job_id
project_id
correlation_id
message_type
payload
progress
result
error
```

Required operations:

- Worker version.
- Health.
- Submit job.
- Cancel job.
- Read progress.
- Read structured logs.
- Read result artifact references.
- Graceful stop.
- Restart after failure.

## 8. Controlled Runtime

The worker must use a controlled runtime.

Requirements:

- Do not silently use an arbitrary system Python.
- Use a Cytisus-managed environment or validated user-selected environment.
- Pin supported package versions.
- Isolate project dependencies.
- Require approval before package installation.
- Record runtime and package versions in job results.
- Provide a CPU-only baseline.

Recommended libraries:

- NumPy.
- Polars or pandas.
- SciPy.
- scikit-learn.
- PyTorch.
- ONNX.
- ONNX Runtime.

Optional accelerator dependencies may be installed or packaged separately.

## 9. Native Compute Core

Use a narrow shared native layer, preferably C++ with a stable C ABI.

Required primitives:

- Rolling mean and standard deviation.
- Return and volatility matrices.
- Cross-sectional normalization and ranking.
- Covariance and correlation.
- Matrix operations.
- Batched parameter evaluation.
- Monte Carlo primitives.

Do not put authorization, risk, or broker behavior in the native layer.

## 10. Compute Device Manager

Device record:

```text
device_id
device_type
vendor
model
driver_or_runtime_version
dedicated_or_unified_memory
supported_precisions
supported_backends
training_supported
inference_supported
health
failure_reason
```

Device types:

- CPU.
- GPU.
- NPU.

### CPU

CPU is always available and is the required fallback.

### Apple

Support:

- Metal.
- Metal Performance Shaders.
- Accelerate.
- Core ML where appropriate.
- Apple Neural Engine inference where supported.

### NVIDIA

Support:

- CUDA.
- Supported cuBLAS and cuDNN paths.
- ONNX Runtime CUDA execution provider.

### AMD

Support real runtime checks for:

- ROCm or HIP.
- MIGraphX where available.
- Vitis AI where available.
- Available ONNX Runtime providers.

Do not mark AMD Ready based only on vendor detection.

### Intel

Support real runtime checks for:

- oneAPI.
- SYCL.
- oneMKL where used.
- OpenVINO.
- ONNX Runtime OpenVINO execution provider.
- Intel NPU provider where supported.

### NPU

Support compatible inference providers such as:

- Windows ML execution providers.
- Qualcomm QNN.
- Intel OpenVINO.
- AMD Vitis AI.
- Apple Neural Engine through Core ML.
- DirectML fallback where appropriate.

Do not claim NPU training unless the backend reports and passes a training capability check.

## 11. Compute Scheduling

User policies:

- Auto.
- CPU Only.
- Prefer GPU.
- Prefer NPU for Inference.
- Specific Device.
- Maximum Performance.
- Balanced.
- Battery Saver.

Scheduler inputs:

- Job type.
- Data size.
- Backend compatibility.
- Device memory.
- Transfer cost.
- Resource limits.
- Power state.
- Device health.

Required behavior:

- Record selected device and backend.
- Limit CPU threads and memory.
- Limit GPU memory where supported.
- Support progress and cancellation.
- Fall back to CPU when valid.
- Explain fallback.
- Mark unhealthy backends unavailable until retry.

Do not build a general hardware benchmark product.

## 12. Algorithm Projects

Recommended structure:

```text
strategy.yaml
main.py
factors/
models/
execution/
risk/
tests/
checkpoints/
artifacts/
```

Project metadata:

```text
project_id
name
version
runtime_version
entrypoint
required_data
supported_modes
parameter_schema
allowed_accounts
created_at
updated_at
```

Required operations:

- Create.
- Open.
- Clone version.
- Edit.
- View diff.
- Save candidate version.
- Run.
- Backtest.
- Train.
- Export ONNX.
- Deploy to Paper.
- Submit for Live eligibility.
- Roll back.
- Archive.

Every code change creates a new version.

No changed project is automatically deployed to Live.

## 13. Focused Editor

Provide:

- Project tree.
- Syntax highlighting.
- Search.
- Diagnostics.
- Diff preview.
- Run and Stop.
- Output console.
- Links to compute jobs.

It does not need to replace a full IDE.

## 14. Agent-assisted Development

Use the selected v1.1.1 model.

Allowed:

- Read approved project files.
- Explain code.
- Generate ProjectPatch.
- Modify factors.
- Modify strategy logic.
- Modify training configuration.
- Modify execution algorithms.
- Create ComputeJobs.
- Read sanitized diagnostics.
- Read compact result summaries.
- Suggest deployment.
- Create AgentOrderIntent.

Not allowed:

- Read arbitrary files.
- Read secure stores.
- Read Longbridge tokens.
- Execute shell commands.
- Install packages without approval.
- Deploy directly to Live.
- Submit unrestricted broker commands.

Patch flow:

```text
User request
-> approved project context
-> Agent ProjectPatch
-> local validation
-> diff preview
-> candidate project version
-> local compute validation
-> result comparison
-> approval
-> Paper or Live eligibility
```

## 15. Agent Cost Controls

Default flow:

1. One model call creates the patch and compute plan.
2. Local computation runs without model calls.
3. One optional model call explains compact results.

Required limits:

- Per-request call limit.
- Input token limit.
- Output token limit.
- Daily spending limit.
- Monthly spending limit.
- Confirmation above estimated cost.
- Local summarization before Agent analysis.
- Result caching by project version and request hash.

Do not call the Agent for every parameter, factor, trial, epoch, or bar.

Do not upload raw market datasets or training tensors.

## 16. Compute Jobs

Supported jobs:

- FactorCalculation.
- Backtest.
- WalkForwardBacktest.
- ParameterSearch.
- PortfolioOptimization.
- MonteCarlo.
- TrainModel.
- ExportONNX.
- TestONNX.
- BenchmarkInference.
- ValidateProject.
- SimulateExecutionAlgorithm.

Common fields:

```text
job_id
project_id
project_version
job_type
dataset_version
universe_version
compute_policy
resource_limits
status
progress
selected_device
selected_backend
result_artifacts
error
```

Resource limits:

- Runtime.
- CPU threads.
- RAM.
- GPU memory.
- Epochs.
- Trials.
- Output size.

All jobs support cancellation.

## 17. Backtesting and Optimization

Use v1.1.0 local point-in-time data.

Required:

- Event-driven path.
- Vectorized factor path where applicable.
- Trading costs.
- Slippage.
- Purged walk-forward validation.
- Regime breakdown.
- Sensitivity.
- Baseline comparison.
- Fixed random seeds.
- Dataset and runtime version recording.

Optimization:

- Grid search.
- Fixed-seed random search.
- Bounded Bayesian or equivalent search.
- Early stopping.
- Trial limits.

Do not use final holdout data for parameter selection.

## 18. Local Neural-network Training

Required:

- Time-series-safe splits.
- Configurable model definition.
- CPU training.
- Supported GPU training.
- Checkpoints.
- Resume.
- Early stopping.
- Metrics.
- Loss curves.
- Bounded hyperparameter search.
- Dataset version.
- Feature schema.
- Normalization metadata.
- Seed where supported.
- ONNX export.
- ONNX consistency check.
- Model Registry registration.

Training completion creates Draft status.

Deployment path:

```text
Draft
-> Validated
-> Backtested
-> Shadow
-> Active
```

Do not automatically deploy a trained model.

## 19. ONNX Model Registry

Required model fields:

```text
model_id
project_id
name
version
source
onnx_path
model_hash
input_schema
output_schema
feature_schema
normalization_metadata
dataset_version
training_job_id
supported_execution_providers
preferred_execution_provider
fallback_execution_provider
precision
status
created_at
updated_at
```

Required operations:

- Import.
- Register trained model.
- Inspect input and output schema.
- Validate shapes and types.
- Test one inference.
- Test batch inference.
- Discover execution providers.
- Select preferred provider.
- Record actual provider used.
- Compare small local latency samples.
- Bind to strategy.
- Roll back version.
- Export.
- Dependency-aware deletion.

Statuses:

- Draft.
- Validated.
- Backtested.
- Shadow.
- Active.
- Retired.
- Incompatible.

## 20. Execution-algorithm Development

Support local execution modules such as:

- Market.
- Limit.
- TWAP.
- VWAP.
- POV.
- Iceberg.
- Adaptive Limit.
- Passive.
- Aggressive.
- Spread-aware.
- Participation-capped.
- Cancel-and-replace.
- Slippage-protected.

Modules create structured child-order proposals.

They never call Longbridge CLI directly.

Required path:

```text
Strategy or Agent intent
-> Execution module
-> Child-order proposal
-> Existing Execution Gateway
-> Longbridge CLI
```

Execution changes require simulation, Paper validation, versioning, and Live eligibility.

## 21. Expanded Longbridge Management

Extend the existing integration to support:

- CLI detection.
- Authorization initiation or guidance.
- Authorization status.
- Refresh.
- Disconnect.
- Account discovery.
- Paper and Live account classification.
- Market-data permission summary.
- Trading permission summary.
- Multiple accounts.
- Default account.
- Strategy-to-account mapping.
- Agent authorization-to-account mapping.
- Expiry and failure handling.

Do not read token files directly.

Never send Longbridge credentials to Agent providers, projects, training jobs, logs, or diagnostics.

## 22. Agent Order Intents

v1.1.2 does not add manual order entry.

It adds structured AgentOrderIntent.

Fields:

```text
intent_id
agent_session_id
model_id
account_id
symbol
side
quantity_or_notional
order_type
limit_price_optional
time_in_force
outside_regular_hours
reason
confidence
authorization_id
created_at
expires_at
```

Permission modes:

### Suggest Only

The Agent can create a proposal but cannot submit.

### Confirm Every Order

The Agent prepares the order and the user confirms it.

### Bounded Autonomy

The Agent may submit through the existing Execution Gateway within a revocable and time-limited authorization.

Authorization fields:

```text
allowed_accounts
allowed_markets
allowed_symbols_or_universe
maximum_order_value
maximum_daily_value
maximum_position
maximum_daily_loss
allowed_order_types
allowed_trading_hours
outside_regular_hours_permission
minimum_confidence
valid_from
expires_at
```

Mandatory rejection or confirmation:

- Unauthorized symbol.
- Limit exceeded.
- Authorization expired.
- Stale data.
- Provider or model changed.
- Confidence below threshold.
- Incompatible market status.
- Ambiguous Longbridge result.
- Failed risk check.
- Unresolved reconciliation.

No unlimited authorization.

## 23. User Interface

Add or extend:

- Algorithm Studio.
- Compute.
- Models.
- Training.
- Backtests.
- Execution Lab.
- Agent.
- Longbridge Accounts.

Do not add a manual order ticket.

### Algorithm Studio

Project tree, editor, diagnostics, diff, versions, Run, Backtest, Train, and deployment workflow.

### Compute

Devices, backends, limits, jobs, progress, cancel, fallback, and failure reason.

### Models

ONNX models, versions, schema, execution providers, tests, status, and strategy bindings.

### Training

Jobs, device, dataset, epochs, metrics, checkpoints, Stop, Resume, and Export.

### Backtests

Baseline comparison, OOS, regimes, costs, drawdown, sensitivity, and eligibility.

### Execution Lab

Execution module versions, simulation, Paper result, eligibility, and child-order proposals.

### Agent

Request, context scope, patch, compute plan, cost estimate, explanation, order permission, and order-intent history.

### Longbridge Accounts

CLI state, authorization, accounts, permissions, mappings, refresh, and disconnect.

## 24. Persistence

Add idempotent migrations for:

```text
algorithm_projects
project_versions
project_files
project_patches
compute_devices
compute_backends
compute_jobs
compute_job_events
training_jobs
training_checkpoints
model_registry
model_deployments
execution_modules
execution_simulations
longbridge_accounts
account_mappings
agent_order_authorizations
agent_order_intents
```

Large artifacts are local files with database references and hashes.

Do not store Longbridge tokens, model API keys, raw authorization headers, or plaintext secrets.

## 25. Sandbox and Audit

Worker access is limited to:

- Approved project directories.
- Cytisus data cache.
- Job artifact directories.
- Explicitly approved imports.

Default-deny:

- Arbitrary home-directory access.
- Browser profiles.
- Keychains.
- Credential stores.
- Longbridge token files.
- SSH keys.
- Arbitrary network destinations.

Typed services provide Longbridge data, model-provider calls, and approved package installation.

Audit:

- Agent patches.
- Project versions.
- Compute jobs.
- Device and backend selection.
- Package approvals.
- Training.
- ONNX registration.
- Deployment.
- Account mapping.
- Agent authorization.
- Agent order intent.
- Execution result.

## 26. Failure Handling

Required:

- Worker restart without UI crash.
- Clear CPU fallback when an accelerator is unavailable.
- Out-of-memory handling.
- Training checkpoint preservation.
- ONNX Incompatible state.
- Agent provider failure without stopping local deterministic jobs.
- Longbridge authorization failure without blocking cached local research.
- No infinite training or Agent retry loop.

## 27. Minimal Test Plan

Testing must remain small and high-value.

Required tests only:

1. Worker request, progress, cancellation, and result.
2. Worker crash isolation.
3. CPU discovery and CPU fallback.
4. One capability-discovery smoke test per accelerator family:
   - Apple Metal adapter.
   - NVIDIA CUDA adapter.
   - AMD ROCm or HIP adapter.
   - Intel oneAPI or SYCL adapter.
   - NPU provider adapter.
5. Project sandbox denies unauthorized paths.
6. Agent patch creates a candidate version and cannot request shell execution.
7. One deterministic backtest fixture.
8. One purged walk-forward split check.
9. One bounded optimization trial-limit check.
10. One CPU training smoke job with checkpoint and resume.
11. One ONNX import, export, schema, and inference consistency check.
12. Execution module cannot bypass the existing Execution Gateway.
13. Longbridge token is not exposed to the Worker or Agent.
14. Agent order authorization:
    - Suggest Only cannot submit.
    - Confirm Every Order requires confirmation.
    - Bounded Autonomy enforces limits and expiry.
15. No manual order UI action exists.
16. ASCII validation.
17. One final macOS build and one final Windows build.

Do not add:

- Broad UI snapshot suites.
- Large hardware compatibility matrices.
- Production-scale training.
- Large performance benchmarks.
- Real model-provider calls in CI.
- Real Longbridge accounts in CI.
- Real orders in CI.
- Repeated full test runs.
- Coverage-driven low-value tests.

Execution rule:

- Run targeted tests once.
- When a test fails, rerun only that target.
- Run one final smoke pass before release.
- Run the dual-platform release workflow once near completion.

## 28. Documentation

Add:

```text
docs/PDM-v1.1.2.md
docs/LOCAL-QUANT-RUNTIME.md
docs/COMPUTE-BACKENDS.md
docs/ALGORITHM-PROJECTS.md
docs/ONNX-MODELS.md
docs/AGENT-DEVELOPMENT.md
docs/AGENT-ORDER-AUTHORIZATION.md
docs/CODEX-v1.1.2-PROMPT.md
```

Update only changed behavior in:

```text
README.md
INSTALL.txt
PRIVACY.md
SANITIZATION.json
docs/LONGBRIDGE-INTEGRATION.md
```

Documentation must explain:

- Algorithms run locally.
- Agent models control development and orchestration, not numerical computation.
- Longbridge CLI remains the data and broker gateway.
- Optional accelerators require compatible hardware and runtimes.
- CPU fallback remains available.
- Project code is sandboxed.
- Manual order entry is not supported.
- Agent orders require explicit bounded authorization.

## 29. Version and Release

Update to version 1.1.2.

Expected artifacts:

```text
dist/Cytisus-Trading-1.1.2-universal.dmg
dist/Cytisus-Trading-1.1.2-win11-x64.exe
```

Optional compute packs may be separate and versioned.

Preserve:

- Native SwiftUI macOS UI.
- Native WPF Windows UI.
- Universal 2 macOS build.
- Windows self-contained build.
- Apple signing and notarization support.
- Existing dual-platform GitHub Actions workflow.
- English-only ASCII validation.

Do not silently bundle incompatible or excessively large accelerator runtimes.

## 30. Acceptance Criteria

v1.1.2 is accepted only when:

- Accepted v1.1.0 and v1.1.1 are present.
- Both apps can start without the Worker.
- Both apps can start the Worker.
- Both apps can create, edit, and version local algorithm projects.
- The Agent can create a reviewed candidate patch.
- The Agent cannot execute arbitrary shell commands.
- A local backtest runs without model API calls.
- A local CPU training job runs.
- Supported accelerator adapters report truthful Ready or Unavailable states.
- CPU fallback works.
- ONNX models can be imported, exported, validated, versioned, and bound to a strategy.
- Custom execution logic is simulated and routed through the existing Execution Gateway.
- Longbridge account discovery and mapping work.
- Longbridge credentials are not exposed.
- No manual order ticket exists.
- Suggest Only, Confirm Every Order, and Bounded Autonomy work.
- Bounded Agent authorization limits are enforced.
- Audit records cover project, compute, model, account, authorization, and Agent order events.
- ASCII validation passes.
- macOS 1.1.2 builds.
- Windows 1.1.2 builds.
- No real credentials, accounts, positions, or orders are committed.

## 31. Final Scope Rule

When implementation choices are ambiguous:

- Prefer local computation.
- Reuse v1.1.0 and v1.1.1 services.
- Prefer typed services over arbitrary commands.
- Prefer CPU fallback over false accelerator support.
- Prefer bounded Agent authority over unlimited autonomy.
- Do not add manual trading.
- Do not add cloud or collaboration features.
