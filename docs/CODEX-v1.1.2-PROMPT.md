# Codex Prompt: Implement Cytisus v1.1.2 Local Algorithm Studio

Repository: KDTikkly/Cytisus-Trading
Target release: 1.1.2
Execution order: after accepted v1.1.0 and v1.1.1
Output language: English only
Repository text: ASCII only

## 1. Verify Preconditions

Read the current repository before editing.

Confirm that v1.1.0 and v1.1.1 are fully present.

Required v1.1.0 foundations:

- Longbridge CLI adapter.
- Local data store.
- Strategy runtime.
- Factor governance.
- Paper and Live controls.
- Execution Gateway.
- Virtual ledger.
- Audit and redaction.

Required v1.1.1 foundations:

- Multiple model providers.
- Multiple models.
- Secure API key storage.
- Primary and fallback models.
- Model-client abstraction.

If either version is incomplete, stop without modifying code.

Do not create duplicate implementations of existing services.

## 2. Add Documents

Add the supplied PDM as:

```text
docs/PDM-v1.1.2.md
```

Add this prompt as:

```text
docs/CODEX-v1.1.2-PROMPT.md
```

Also add:

```text
docs/LOCAL-QUANT-RUNTIME.md
docs/COMPUTE-BACKENDS.md
docs/ALGORITHM-PROJECTS.md
docs/ONNX-MODELS.md
docs/AGENT-DEVELOPMENT.md
docs/AGENT-ORDER-AUTHORIZATION.md
```

Read the PDM before implementation.

## 3. Scope

Implement only the v1.1.2 additions:

- Shared local Quant Worker.
- Controlled Python runtime.
- Native accelerated compute core.
- CPU, GPU, and NPU discovery.
- Apple Metal and MPS.
- NVIDIA CUDA.
- AMD ROCm or HIP.
- Intel oneAPI or SYCL.
- Supported NPU inference providers.
- CPU fallback.
- Local algorithm projects.
- Local backtests and optimization.
- Local neural-network training.
- ONNX model management.
- Agent-assisted code development.
- Custom execution-algorithm development.
- Expanded Longbridge account management.
- Bounded Agent order intents.

Do not add manual order entry.

Do not add cloud compute, collaboration, or another broker.

## 4. Preserve Existing Architecture

Preserve:

- SwiftUI on macOS.
- WPF on Windows.
- Existing v1.1.0 services.
- Existing v1.1.1 model-provider services.
- Existing release workflow.
- ASCII validation.

Do not replace the UI framework.

## 5. Quant Worker

Implement one separate local Worker used by both desktop editions.

Transport:

- Unix Domain Socket on macOS.
- Named Pipe on Windows.
- NDJSON or length-prefixed JSON.

Protocol fields:

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

Support:

- Version and health.
- Submit job.
- Progress.
- Cancel.
- Structured logs.
- Artifact references.
- Stop and restart.

A Worker crash must not crash the UI.

## 6. Controlled Runtime

Use a Cytisus-managed environment or validated user-selected environment.

Requirements:

- No silent arbitrary system Python.
- Pinned supported packages.
- Per-project dependency isolation.
- Explicit approval for package installation.
- Runtime and package versions recorded in results.
- CPU-only baseline.

Recommended libraries:

- NumPy.
- Polars or pandas.
- SciPy.
- scikit-learn.
- PyTorch.
- ONNX.
- ONNX Runtime.

Optional accelerator packages may be separate compute packs.

## 7. Native Compute Core

Use a narrow shared native core, preferably C++ with a stable C ABI.

Implement:

- Rolling statistics.
- Return and volatility matrices.
- Cross-sectional ranking and normalization.
- Covariance and correlation.
- Matrix operations.
- Batched parameter evaluation.
- Monte Carlo primitives.

Do not put broker, authorization, or risk policy in this layer.

## 8. Compute Device Manager

Represent:

```text
device_id
device_type
vendor
model
driver_or_runtime_version
memory
supported_precisions
supported_backends
training_supported
inference_supported
health
failure_reason
```

Implement real capability checks or clear Unavailable states for:

### Apple

- Metal.
- MPS.
- Accelerate.
- Core ML.
- Apple Neural Engine inference where supported.

### NVIDIA

- CUDA.
- Supported cuBLAS and cuDNN paths.
- ONNX Runtime CUDA provider.

### AMD

- ROCm or HIP.
- MIGraphX where available.
- Vitis AI where available.
- Available ONNX Runtime providers.

Do not mark AMD Ready from vendor detection alone.

### Intel

- oneAPI.
- SYCL.
- oneMKL where used.
- OpenVINO.
- ONNX Runtime OpenVINO provider.
- Intel NPU provider where supported.

### NPU

Support available providers such as:

- Windows ML execution providers.
- Qualcomm QNN.
- Intel OpenVINO.
- AMD Vitis AI.
- Apple Neural Engine.
- DirectML fallback where appropriate.

Distinguish training from inference support.

## 9. Scheduling

Support:

```text
Auto
CPU Only
Prefer GPU
Prefer NPU for Inference
Specific Device
Maximum Performance
Balanced
Battery Saver
```

Use job type, size, compatibility, memory, transfer cost, limits, power state, and health.

Required:

- Record selected backend.
- Limit threads and memory.
- Support cancellation.
- CPU fallback.
- Clear fallback reason.
- Unhealthy backend quarantine.

Do not build a broad benchmarking product.

## 10. Algorithm Projects

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

Support:

- Create.
- Open.
- Clone version.
- Edit.
- Diff.
- Save candidate version.
- Run.
- Backtest.
- Train.
- Export ONNX.
- Deploy to Paper.
- Submit for Live eligibility.
- Roll back.
- Archive.

Every modification creates a new version.

No automatic Live deployment.

## 11. Focused Editor

Implement:

- Project tree.
- Syntax highlighting.
- Search.
- Diagnostics.
- Diff preview.
- Run and Stop.
- Output console.
- Links to jobs.

Do not build a full IDE.

## 12. Agent-assisted Development

Use the v1.1.1 selected model.

Allowed:

- Read approved project files.
- Explain code.
- Create ProjectPatch.
- Modify strategy, factor, training, and execution files.
- Create ComputeJobs.
- Read sanitized diagnostics.
- Read compact result summaries.
- Suggest deployment.
- Create AgentOrderIntent.

Forbidden:

- Arbitrary file access.
- Secure-store access.
- Longbridge token access.
- Shell execution.
- Package installation without approval.
- Direct Live deployment.
- Unrestricted broker commands.

All Agent patches create candidate versions and require local validation.

## 13. Agent Cost Limits

Default flow:

1. One Agent call creates patch and compute plan.
2. Local computation runs with no model calls.
3. One optional Agent call explains compact results.

Implement:

- Call limit.
- Input token limit.
- Output token limit.
- Daily and monthly spending limits.
- Confirmation above estimated cost.
- Local summarization.
- Cache by project version and request hash.

Do not call the Agent for every trial, epoch, bar, factor, or parameter.

Do not upload raw market datasets or training tensors.

## 14. Compute Jobs

Implement:

```text
FactorCalculation
Backtest
WalkForwardBacktest
ParameterSearch
PortfolioOptimization
MonteCarlo
TrainModel
ExportONNX
TestONNX
BenchmarkInference
ValidateProject
SimulateExecutionAlgorithm
```

Support runtime, CPU, RAM, GPU memory, epoch, trial, and output-size limits.

Support progress and cancellation.

## 15. Backtesting and Optimization

Use the v1.1.0 point-in-time data store.

Implement:

- Event-driven path.
- Vectorized factor path where useful.
- Costs and slippage.
- Purged walk-forward.
- Regime breakdown.
- Sensitivity.
- Baseline comparison.
- Fixed seeds.
- Dataset and runtime version recording.

Optimization:

- Grid.
- Fixed-seed random.
- Bounded Bayesian or equivalent.
- Early stopping.
- Trial limits.

Do not select parameters using the final holdout set.

## 16. Training

Implement local TrainingJobs:

- Time-series-safe splits.
- CPU training.
- Supported GPU training.
- Checkpoints and resume.
- Early stopping.
- Metrics and loss curves.
- Bounded hyperparameter search.
- Dataset and feature metadata.
- Normalization metadata.
- ONNX export.
- ONNX consistency check.
- Model Registry registration.

Training output starts as Draft.

Deployment path:

```text
Draft
-> Validated
-> Backtested
-> Shadow
-> Active
```

No automatic deployment.

## 17. ONNX Registry

Implement:

- Import.
- Trained-model registration.
- Hash and version.
- Input and output schema.
- Feature and normalization metadata.
- Dataset version.
- Provider discovery.
- Preferred and fallback provider.
- Actual provider used.
- One and batch inference tests.
- Small local latency comparison.
- Strategy binding.
- Rollback.
- Export.
- Dependency-aware deletion.

Statuses:

```text
Draft
Validated
Backtested
Shadow
Active
Retired
Incompatible
```

## 18. Execution-algorithm Development

Support local modules such as:

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

Modules produce structured child-order proposals.

They never call Longbridge CLI directly.

Required path:

```text
Strategy or Agent intent
-> Execution module
-> Child-order proposal
-> Existing Execution Gateway
-> Longbridge CLI
```

Require simulation, Paper validation, versioning, and Live eligibility.

## 19. Expanded Longbridge Management

Extend the existing integration for:

- CLI detection.
- Authorization initiation or guidance.
- Status.
- Refresh.
- Disconnect.
- Account discovery.
- Paper and Live classification.
- Permission summaries.
- Multiple accounts.
- Default account.
- Strategy mapping.
- Agent authorization mapping.
- Expiry and failure handling.

Do not read token files directly.

Never expose Longbridge credentials to Agent providers, projects, training jobs, logs, or diagnostics.

## 20. Agent Order Intents

Do not add manual order entry.

Implement structured AgentOrderIntent with:

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

Modes:

### Suggest Only

Cannot submit.

### Confirm Every Order

Requires user confirmation.

### Bounded Autonomy

May submit through the existing Execution Gateway within revocable, time-limited limits.

Limits include:

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

Reject or require confirmation when any limit, freshness, confidence, provider, model, market, risk, or reconciliation rule fails.

No unlimited authorization.

## 21. UI

Add or extend:

```text
Algorithm Studio
Compute
Models
Training
Backtests
Execution Lab
Agent
Longbridge Accounts
```

Do not add a manual order ticket.

## 22. Persistence and Sandbox

Add idempotent migrations for project, compute, training, ONNX, execution-module, account-mapping, and Agent-order records.

Store large artifacts as files with hashes.

Do not store tokens or API keys.

Worker access is limited to approved project, cache, artifact, and import paths.

Default-deny arbitrary home, browser, keychain, credential, token, SSH, and network access.

Audit all project, compute, model, deployment, account, authorization, and Agent order events.

## 23. Minimal Tests Only

Do not build a broad test suite.

Required tests:

1. Worker protocol and crash isolation.
2. CPU discovery and fallback.
3. One backend-discovery smoke test per family:
   - Metal.
   - CUDA.
   - ROCm or HIP.
   - oneAPI or SYCL.
   - NPU provider.
4. Sandbox path denial.
5. Agent patch candidate version and shell-command rejection.
6. One deterministic backtest fixture.
7. One purged walk-forward check.
8. One bounded optimization check.
9. One CPU training smoke job with checkpoint and resume.
10. One ONNX import, export, schema, and consistency check.
11. Execution module cannot bypass the Execution Gateway.
12. Longbridge token isolation.
13. Agent order modes and bounded authorization limits.
14. No manual order action exists.
15. ASCII validation.
16. One final macOS build.
17. One final Windows build.

Do not add:

- UI snapshot suites.
- Large compatibility matrices.
- Production-scale training.
- Large benchmarks.
- Real provider calls in CI.
- Real Longbridge accounts in CI.
- Real orders in CI.
- Repeated full test runs.
- Coverage-driven low-value tests.

Run each targeted test once.

On failure, rerun only the failed target.

Run one final smoke pass and one dual-platform release workflow near completion.

## 24. Documentation and Release

Update only changed behavior in README, INSTALL, PRIVACY, SANITIZATION, and Longbridge documentation.

Update version to 1.1.2.

Expected artifacts:

```text
dist/Cytisus-Trading-1.1.2-universal.dmg
dist/Cytisus-Trading-1.1.2-win11-x64.exe
```

Optional compute packs may be separate and versioned.

Preserve signing, notarization, self-contained Windows publishing, GitHub Actions, and ASCII validation.

## 25. Completion Rules

Before finishing:

1. Confirm v1.1.0 and v1.1.1 remain intact.
2. Confirm no duplicate core services were created.
3. Confirm both platforms use the shared Quant Worker.
4. Confirm CPU-only operation.
5. Confirm backend states are truthful.
6. Confirm Agent patches create candidate versions.
7. Confirm local compute does not require repeated model calls.
8. Confirm ONNX lifecycle works.
9. Confirm execution logic cannot bypass the Gateway.
10. Confirm Longbridge credentials remain isolated.
11. Confirm no manual order UI exists.
12. Confirm Agent authorization is bounded and revocable.
13. Run the minimal tests.
14. Run ASCII validation.
15. Build both artifacts.
16. Search tracked files for secrets, real accounts, positions, orders, and user paths.
17. Commit and push without force-pushing.

Suggested commit message:

```text
feat: add local algorithm studio and accelerated quant runtime
```

## 26. Final Response

Report only:

```text
Implementation summary
Precondition verification
Quant Worker architecture
Compute backends
Algorithm and Agent workflow
Training and ONNX behavior
Execution-algorithm behavior
Longbridge account behavior
Agent order authorization
Files changed
Tests and builds actually executed
Artifact paths and SHA-256 values
Commit SHA
Push status
Known limitations
Optional backend setup steps
```

Do not claim success for any action that was not actually completed.
