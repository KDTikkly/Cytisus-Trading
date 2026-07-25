# Compute Backends

## Readiness rule

CPU is the baseline and deterministic fallback. An accelerator is Ready only when an actual runtime execution provider is present. A hardware marketing name or operating-system device record is not enough.

The Worker checks optional installed runtimes without downloading them:

- PyTorch CUDA, MPS, and HIP;
- ONNX Runtime execution providers;
- OpenVINO.

Missing packages are reported as Unavailable with a reason.

## Scheduling

A compute policy records:

- preferred device;
- whether CPU fallback is allowed;
- maximum concurrent jobs;
- maximum threads;
- maximum memory.

If the preferred device is not Ready, the scheduler selects CPU only when fallback is allowed. Otherwise it rejects the job clearly.

## Native CPU core

`NativeCompute/quant_core.h` is the stable boundary. The implementation provides small dependency-free primitives and does not own higher-level job, broker, authorization, or UI behavior.

## Optional setup

Users may select a controlled Python environment and install compatible versions of PyTorch, ONNX Runtime, or OpenVINO themselves. Cytisus never performs those installations or promises that a provider is usable until discovery succeeds.
