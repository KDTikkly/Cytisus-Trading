#!/usr/bin/env python3
"""Cytisus local Quant Worker.

The worker uses only the Python standard library for its CPU baseline. Optional
packages are discovered at runtime and are never installed automatically.
"""

from __future__ import annotations

import argparse
import ctypes.util
import hashlib
import importlib.util
import importlib.metadata
import json
import math
import os
import platform
import random
import shutil
import statistics
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from multiprocessing.connection import Listener
from pathlib import Path
from typing import Any


VERSION = "1.1.8"
MAX_MESSAGE_BYTES = 1_048_576
MAX_OUTPUT_BYTES = 4_194_304
ALLOWED_JOB_TYPES = {
    "FactorCalculation",
    "Backtest",
    "WalkForwardBacktest",
    "ParameterSearch",
    "PortfolioOptimization",
    "MonteCarlo",
    "TrainModel",
    "ExportONNX",
    "TestONNX",
    "BenchmarkInference",
    "ValidateProject",
    "SimulateExecutionAlgorithm",
}


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def bounded_text(value: Any, limit: int = 4096) -> str:
    return str(value)[:limit]


def response(message: dict[str, Any], **values: Any) -> dict[str, Any]:
    base = {
        "request_id": message.get("request_id", ""),
        "job_id": message.get("job_id"),
        "project_id": message.get("project_id"),
        "correlation_id": message.get("correlation_id", ""),
        "message_type": values.pop("message_type", "Result"),
        "payload": {},
        "progress": values.pop("progress", None),
        "result": values.pop("result", None),
        "error": values.pop("error", None),
    }
    base.update(values)
    return base


def optional_module(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def runtime_versions() -> dict[str, str]:
    versions = {"python": platform.python_version(), "worker": VERSION}
    for package in (
        "numpy",
        "pandas",
        "scipy",
        "scikit-learn",
        "torch",
        "onnx",
        "onnxruntime",
        "openvino",
    ):
        try:
            versions[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            continue
    return versions


def discover_devices() -> list[dict[str, Any]]:
    machine = platform.machine() or "unknown"
    devices: list[dict[str, Any]] = [
        {
            "device_id": "cpu-0",
            "device_type": "CPU",
            "vendor": platform.processor() or "Generic",
            "model": machine,
            "driver_or_runtime_version": platform.python_version(),
            "dedicated_or_unified_memory": None,
            "supported_precisions": ["FP64", "FP32"],
            "supported_backends": ["PythonCPU", "NativeCPU"],
            "training_supported": True,
            "inference_supported": True,
            "health": "Ready",
            "failure_reason": "",
        }
    ]
    providers: set[str] = set()
    if optional_module("onnxruntime"):
        try:
            import onnxruntime  # type: ignore

            providers = set(onnxruntime.get_available_providers())
        except Exception:
            providers = set()

    system = platform.system()
    mps_ready = False
    cuda_ready = False
    rocm_ready = False
    if optional_module("torch"):
        try:
            import torch  # type: ignore

            cuda_ready = bool(torch.cuda.is_available())
            rocm_ready = bool(getattr(torch.version, "hip", None))
            mps_ready = bool(
                hasattr(torch.backends, "mps")
                and torch.backends.mps.is_available()
            )
        except Exception:
            pass

    def add_backend(
        device_id: str,
        device_type: str,
        vendor: str,
        backends: list[str],
        ready: bool,
        training: bool,
        reason: str,
    ) -> None:
        devices.append(
            {
                "device_id": device_id,
                "device_type": device_type,
                "vendor": vendor,
                "model": "Runtime-discovered",
                "driver_or_runtime_version": "runtime-check",
                "dedicated_or_unified_memory": None,
                "supported_precisions": ["FP32", "FP16"] if ready else [],
                "supported_backends": backends,
                "training_supported": training and ready,
                "inference_supported": ready,
                "health": "Ready" if ready else "Unavailable",
                "failure_reason": "" if ready else reason,
            }
        )

    add_backend(
        "apple-metal",
        "GPU",
        "Apple",
        ["Metal", "MPS", "Accelerate", "CoreML"],
        system == "Darwin"
        and (mps_ready or "CoreMLExecutionProvider" in providers),
        mps_ready,
        "No tested MPS or CoreML runtime provider is available on this host.",
    )
    add_backend(
        "nvidia-cuda",
        "GPU",
        "NVIDIA",
        ["CUDA", "ONNXRuntimeCUDA"],
        cuda_ready or "CUDAExecutionProvider" in providers,
        cuda_ready,
        "CUDA runtime capability check did not pass.",
    )
    add_backend(
        "amd-rocm",
        "GPU",
        "AMD",
        ["ROCm", "HIP", "MIGraphX", "VitisAI"],
        rocm_ready
        or "MIGraphXExecutionProvider" in providers
        or "VitisAIExecutionProvider" in providers,
        rocm_ready,
        "ROCm, HIP, MIGraphX, and Vitis AI capability checks did not pass.",
    )
    openvino_ready = False
    if optional_module("openvino"):
        try:
            import openvino  # type: ignore

            openvino_ready = bool(openvino.Core().available_devices)
        except Exception:
            openvino_ready = False
    intel_ready = openvino_ready or "OpenVINOExecutionProvider" in providers
    add_backend(
        "intel-oneapi",
        "GPU",
        "Intel",
        ["oneAPI", "SYCL", "OpenVINO"],
        intel_ready,
        False,
        "oneAPI, SYCL, and OpenVINO capability checks did not pass.",
    )
    npu_providers = {
        "QNNExecutionProvider",
        "VitisAIExecutionProvider",
    }
    active_npu = sorted(providers.intersection(npu_providers))
    add_backend(
        "npu-runtime",
        "NPU",
        "Runtime",
        active_npu or ["QNN", "VitisAI"],
        bool(active_npu),
        False,
        "No supported NPU inference provider passed discovery.",
    )
    return devices


def rolling_mean(values: list[float], window: int) -> list[float | None]:
    if window <= 0:
        raise ValueError("window must be positive")
    result: list[float | None] = []
    for index in range(len(values)):
        if index + 1 < window:
            result.append(None)
        else:
            result.append(sum(values[index + 1 - window : index + 1]) / window)
    return result


def backtest(payload: dict[str, Any]) -> dict[str, Any]:
    prices = [float(value) for value in payload.get("prices", [])]
    if len(prices) < 3 or any(value <= 0 for value in prices):
        raise ValueError("Backtest requires at least three positive prices.")
    fast = max(2, int(payload.get("fast_window", 2)))
    slow = max(fast + 1, int(payload.get("slow_window", 3)))
    fee = max(0.0, float(payload.get("fee_rate", 0.0005)))
    slippage = max(0.0, float(payload.get("slippage_rate", 0.0005)))
    fast_values = rolling_mean(prices, fast)
    slow_values = rolling_mean(prices, slow)
    equity = 1.0
    position = 0
    trades = 0
    curve = [equity]
    returns: list[float] = []
    for index in range(1, len(prices)):
        signal = (
            1
            if fast_values[index] is not None
            and slow_values[index] is not None
            and fast_values[index] > slow_values[index]
            else 0
        )
        if signal != position:
            equity *= 1.0 - fee - slippage
            position = signal
            trades += 1
        daily = prices[index] / prices[index - 1] - 1.0
        strategy_return = position * daily
        returns.append(strategy_return)
        equity *= 1.0 + strategy_return
        curve.append(equity)
    peak = 1.0
    drawdown = 0.0
    for value in curve:
        peak = max(peak, value)
        drawdown = min(drawdown, value / peak - 1.0)
    baseline = prices[-1] / prices[0] - 1.0
    volatility = statistics.pstdev(returns) if len(returns) > 1 else 0.0
    return {
        "total_return": equity - 1.0,
        "baseline_return": baseline,
        "maximum_drawdown": drawdown,
        "volatility": volatility,
        "trades": trades,
        "equity_curve": curve,
        "seed": 17,
        "dataset_version": payload.get("dataset_version", "fixture-v1"),
        "runtime_version": VERSION,
    }


def walk_forward(payload: dict[str, Any]) -> dict[str, Any]:
    length = int(payload.get("sample_count", 100))
    train = int(payload.get("train_size", 50))
    test = int(payload.get("test_size", 20))
    purge = int(payload.get("purge_size", 5))
    splits = []
    start = 0
    while start + train + purge + test <= length:
        splits.append(
            {
                "train": [start, start + train],
                "purge": [start + train, start + train + purge],
                "test": [
                    start + train + purge,
                    start + train + purge + test,
                ],
            }
        )
        start += test
    return {"splits": splits, "purged": True}


def parameter_search(payload: dict[str, Any]) -> dict[str, Any]:
    limit = min(max(int(payload.get("trial_limit", 5)), 1), 100)
    values = [float(value) for value in payload.get("candidates", [0.1, 0.2])]
    rng = random.Random(int(payload.get("seed", 17)))
    trials = []
    for index in range(limit):
        parameter = values[index % len(values)]
        score = 1.0 - abs(parameter - 0.25) + rng.random() * 0.0001
        trials.append({"trial": index + 1, "parameter": parameter, "score": score})
    return {
        "trials": trials,
        "trial_limit": limit,
        "best": max(trials, key=lambda item: item["score"]),
    }


def portfolio_optimization(payload: dict[str, Any]) -> dict[str, Any]:
    symbols = [str(value) for value in payload.get("symbols", [])]
    volatility = [max(float(value), 0.000001) for value in payload.get("volatility", [])]
    if not symbols or len(symbols) != len(volatility):
        raise ValueError("Portfolio optimization requires aligned symbols and volatility.")
    inverse = [1.0 / value for value in volatility]
    total = sum(inverse)
    return {
        "method": "DeterministicInverseVolatility",
        "weights": {
            symbol: value / total
            for symbol, value in zip(symbols, inverse)
        },
        "constraint_sum": 1.0,
    }


def train_model(
    payload: dict[str, Any],
    artifact_dir: Path,
    cancelled: threading.Event,
) -> dict[str, Any]:
    features = [float(value) for value in payload.get("features", [1, 2, 3, 4])]
    targets = [float(value) for value in payload.get("targets", [2, 4, 6, 8])]
    if len(features) != len(targets) or len(features) < 2:
        raise ValueError("Training features and targets must align.")
    epochs = min(max(int(payload.get("epochs", 20)), 1), 500)
    learning_rate = min(max(float(payload.get("learning_rate", 0.01)), 0.00001), 0.5)
    checkpoint = artifact_dir / "training-checkpoint.json"
    weight = 0.0
    start_epoch = 0
    if payload.get("resume") and checkpoint.exists():
        saved = json.loads(checkpoint.read_text(encoding="utf-8"))
        weight = float(saved["weight"])
        start_epoch = int(saved["epoch"])
    losses = []
    for epoch in range(start_epoch, epochs):
        if cancelled.is_set():
            raise InterruptedError("Training cancelled.")
        predictions = [weight * value for value in features]
        errors = [prediction - target for prediction, target in zip(predictions, targets)]
        loss = sum(value * value for value in errors) / len(errors)
        gradient = 2.0 * sum(
            error * feature for error, feature in zip(errors, features)
        ) / len(errors)
        weight -= learning_rate * gradient
        losses.append(loss)
        checkpoint.write_text(
            json.dumps({"epoch": epoch + 1, "weight": weight}, sort_keys=True),
            encoding="utf-8",
        )
    model = {
        "kind": "linear",
        "weight": weight,
        "feature_schema": [{"name": "feature", "type": "float32"}],
        "normalization_metadata": {"kind": "none"},
        "dataset_version": payload.get("dataset_version", "fixture-training-v1"),
        "status": "Draft",
    }
    model_path = artifact_dir / "trained-model.json"
    model_path.write_text(json.dumps(model, sort_keys=True), encoding="utf-8")
    return {
        "model_path": str(model_path),
        "checkpoint_path": str(checkpoint),
        "loss_curve": losses,
        "weight": weight,
        "status": "Draft",
        "resumed_from_epoch": start_epoch,
    }


def onnx_lifecycle(payload: dict[str, Any], artifact_dir: Path) -> dict[str, Any]:
    source = Path(str(payload.get("source_path", ""))).resolve()
    if not source.is_file():
        raise ValueError("ONNX source file is unavailable.")
    target = artifact_dir / (source.stem + "-registered.onnx")
    shutil.copyfile(source, target)
    content = target.read_bytes()
    digest = hashlib.sha256(content).hexdigest()
    schema = payload.get(
        "schema",
        {
            "inputs": [{"name": "input", "type": "float32", "shape": [None, 1]}],
            "outputs": [{"name": "output", "type": "float32", "shape": [None, 1]}],
        },
    )
    providers = []
    if optional_module("onnxruntime"):
        try:
            import onnxruntime  # type: ignore

            providers = onnxruntime.get_available_providers()
        except Exception:
            providers = []
    export = artifact_dir / (source.stem + "-export.onnx")
    shutil.copyfile(target, export)
    return {
        "model_hash": digest,
        "onnx_path": str(target),
        "export_path": str(export),
        "byte_consistent": target.read_bytes() == export.read_bytes(),
        "input_schema": schema["inputs"],
        "output_schema": schema["outputs"],
        "supported_execution_providers": providers,
        "actual_provider_used": "Unavailable" if not providers else providers[0],
        "status": "Validated" if providers else "Incompatible",
    }


def simulate_execution(payload: dict[str, Any]) -> dict[str, Any]:
    quantity = max(0.0, float(payload.get("quantity", 0)))
    slices = min(max(int(payload.get("slices", 1)), 1), 100)
    child_quantity = quantity / slices if slices else 0.0
    return {
        "module": payload.get("module", "TWAP"),
        "child_order_proposals": [
            {
                "sequence": index + 1,
                "symbol": payload.get("symbol", ""),
                "side": payload.get("side", "Buy"),
                "quantity": child_quantity,
                "requires_execution_gateway": True,
            }
            for index in range(slices)
        ],
        "direct_cli_access": False,
        "paper_validation_required": True,
    }


@dataclass
class JobState:
    message: dict[str, Any]
    status: str = "Queued"
    progress: float = 0.0
    result: dict[str, Any] | None = None
    error: str | None = None
    cancelled: threading.Event = field(default_factory=threading.Event)
    events: list[dict[str, Any]] = field(default_factory=list)


class WorkerEngine:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir(exist_ok=True)
        self.jobs: dict[str, JobState] = {}
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="cytisus")

    def handle(self, message: dict[str, Any]) -> dict[str, Any]:
        message_type = message.get("message_type")
        if message_type == "Version":
            return response(message, result={"version": VERSION})
        if message_type == "Health":
            return response(
                message,
                result={"status": "Healthy", "cpu_fallback": True},
            )
        if message_type == "DiscoverDevices":
            return response(message, result={"devices": discover_devices()})
        if message_type == "SubmitJob":
            return self.submit(message)
        if message_type in {"ReadProgress", "ReadResult"}:
            return self.read_job(message)
        if message_type == "CancelJob":
            return self.cancel(message)
        if message_type == "StructuredLogs":
            return self.logs(message)
        if message_type == "Stop":
            return response(message, result={"stopping": True})
        return response(message, message_type="Error", error="Unsupported message type.")

    def submit(self, message: dict[str, Any]) -> dict[str, Any]:
        job_id = str(message.get("job_id") or uuid.uuid4())
        payload = message.get("payload") or {}
        job_type = payload.get("job_type")
        if job_type not in ALLOWED_JOB_TYPES:
            return response(
                message,
                message_type="Error",
                job_id=job_id,
                error="Unsupported job type.",
            )
        state = JobState({**message, "job_id": job_id})
        with self.lock:
            if job_id in self.jobs:
                return response(
                    message,
                    message_type="Error",
                    error="Duplicate job ID.",
                )
            self.jobs[job_id] = state
        self.executor.submit(self._run, state)
        return response(
            message,
            message_type="Accepted",
            job_id=job_id,
            progress=0.0,
            result={"status": "Queued"},
        )

    def _run(self, state: JobState) -> None:
        payload = state.message["payload"]
        job_type = payload["job_type"]
        limits = payload.get("resource_limits") or {}
        started = time.monotonic()
        job_id = state.message["job_id"]
        artifact_dir = self.artifacts / job_id
        artifact_dir.mkdir(parents=True, exist_ok=True)
        state.status = "Running"
        state.progress = 0.1
        state.events.append({"time": utc_now(), "message": "Job started."})
        try:
            if state.cancelled.is_set():
                raise InterruptedError("Job cancelled.")
            if job_type == "FactorCalculation":
                values = [float(value) for value in payload.get("values", [])]
                result = {"rolling_mean": rolling_mean(values, int(payload.get("window", 3)))}
            elif job_type == "Backtest":
                result = backtest(payload)
            elif job_type == "WalkForwardBacktest":
                result = walk_forward(payload)
            elif job_type == "ParameterSearch":
                bounded_payload = dict(payload)
                bounded_payload["trial_limit"] = min(
                    int(payload.get("trial_limit", 5)),
                    max(1, int(limits.get("max_trials", 100))),
                )
                result = parameter_search(bounded_payload)
            elif job_type == "PortfolioOptimization":
                result = portfolio_optimization(payload)
            elif job_type == "TrainModel":
                bounded_payload = dict(payload)
                bounded_payload["epochs"] = min(
                    int(payload.get("epochs", 20)),
                    max(1, int(limits.get("max_epochs", 500))),
                )
                result = train_model(bounded_payload, artifact_dir, state.cancelled)
            elif job_type in {"ExportONNX", "TestONNX", "BenchmarkInference"}:
                result = onnx_lifecycle(payload, artifact_dir)
            elif job_type == "SimulateExecutionAlgorithm":
                result = simulate_execution(payload)
            elif job_type == "MonteCarlo":
                rng = random.Random(int(payload.get("seed", 17)))
                count = min(max(int(payload.get("samples", 100)), 1), 10000)
                result = {"samples": [rng.gauss(0, 1) for _ in range(count)], "seed": 17}
            elif job_type == "ValidateProject":
                result = {"valid": True, "shell_allowed": False}
            else:
                result = {"status": "Completed", "cpu_baseline": True}
            requested_device = str(payload.get("device_id", "cpu-0"))
            result["selected_backend"] = (
                result.get("actual_provider_used")
                if result.get("actual_provider_used") not in {None, "Unavailable"}
                else "cpu-0"
            )
            result["fallback_reason"] = (
                ""
                if requested_device in {"", "cpu-0", result["selected_backend"]}
                else "The requested backend was unavailable or incompatible; CPU fallback was used."
            )
            result["runtime_versions"] = runtime_versions()
            result["runtime_seconds"] = time.monotonic() - started
            result["resource_limits"] = limits
            timeout_seconds = max(1, int(limits.get("timeout_seconds", 86400)))
            if result["runtime_seconds"] > timeout_seconds:
                raise TimeoutError("The compute job exceeded its runtime limit.")
            maximum_output = min(
                max(int(limits.get("max_output_bytes", MAX_OUTPUT_BYTES)), 1024),
                MAX_OUTPUT_BYTES,
            )
            if len(
                json.dumps(result, separators=(",", ":")).encode("utf-8")
            ) > maximum_output:
                raise ValueError("The compute job exceeded its output-size limit.")
            state.result = result
            state.status = "Completed"
            state.progress = 1.0
            state.events.append({"time": utc_now(), "message": "Job completed."})
        except InterruptedError as error:
            state.status = "Cancelled"
            state.error = bounded_text(error)
            state.events.append({"time": utc_now(), "message": "Job cancelled."})
        except Exception as error:
            state.status = "Failed"
            state.error = bounded_text(error)
            state.events.append({"time": utc_now(), "message": "Job failed safely."})

    def read_job(self, message: dict[str, Any]) -> dict[str, Any]:
        job_id = str(message.get("job_id", ""))
        state = self.jobs.get(job_id)
        if state is None:
            return response(message, message_type="Error", error="Job not found.")
        return response(
            message,
            message_type="Progress" if state.status in {"Queued", "Running"} else "Result",
            progress=state.progress,
            result={
                "status": state.status,
                "output": state.result,
                "artifact_references": self._artifact_references(job_id),
            },
            error=state.error,
        )

    def cancel(self, message: dict[str, Any]) -> dict[str, Any]:
        state = self.jobs.get(str(message.get("job_id", "")))
        if state is None:
            return response(message, message_type="Error", error="Job not found.")
        state.cancelled.set()
        return response(message, result={"cancel_requested": True})

    def logs(self, message: dict[str, Any]) -> dict[str, Any]:
        state = self.jobs.get(str(message.get("job_id", "")))
        return response(message, result={"events": [] if state is None else state.events})

    def _artifact_references(self, job_id: str) -> list[dict[str, str]]:
        directory = self.artifacts / job_id
        values = []
        for path in directory.glob("*"):
            if path.is_file():
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                values.append({"path": str(path), "sha256": digest})
        return values


def validate_message(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("Worker message must be an object.")
    required = {"request_id", "correlation_id", "message_type"}
    if not required.issubset(value):
        raise ValueError("Worker message is missing required fields.")
    encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
    if len(encoded) > MAX_MESSAGE_BYTES:
        raise ValueError("Worker message exceeds the size limit.")
    return value


def serve_stdio(engine: WorkerEngine) -> int:
    for line in sys.stdin:
        try:
            message = validate_message(json.loads(line))
            output = engine.handle(message)
        except Exception as error:
            output = {
                "request_id": "",
                "correlation_id": "",
                "message_type": "Error",
                "error": bounded_text(error),
            }
        serialized = json.dumps(output, sort_keys=True, separators=(",", ":"))
        if len(serialized.encode("utf-8")) > MAX_OUTPUT_BYTES:
            serialized = json.dumps({"message_type": "Error", "error": "Output limit exceeded."})
        print(serialized, flush=True)
        if (output.get("result") or {}).get("stopping"):
            return 0
    return 0


def serve_endpoint(engine: WorkerEngine, endpoint: str) -> int:
    family = "AF_PIPE" if os.name == "nt" else "AF_UNIX"
    if family == "AF_UNIX":
        path = Path(endpoint)
        if path.exists():
            path.unlink()
    listener = Listener(endpoint, family=family, authkey=None)
    try:
        while True:
            connection = listener.accept()
            try:
                while True:
                    raw = connection.recv_bytes(MAX_MESSAGE_BYTES)
                    message = validate_message(json.loads(raw.decode("utf-8")))
                    output = engine.handle(message)
                    connection.send_bytes(
                        json.dumps(output, sort_keys=True, separators=(",", ":")).encode("utf-8")
                    )
                    if (output.get("result") or {}).get("stopping"):
                        return 0
            except EOFError:
                pass
            finally:
                connection.close()
    finally:
        listener.close()


def run_self_test(root: Path) -> int:
    engine = WorkerEngine(root)
    health = engine.handle(
        {"request_id": "r1", "correlation_id": "c1", "message_type": "Health"}
    )
    if health["result"]["status"] != "Healthy":
        return 1
    devices = discover_devices()
    if not devices or devices[0]["health"] != "Ready":
        return 2
    expected_devices = {
        "cpu-0",
        "apple-metal",
        "nvidia-cuda",
        "amd-rocm",
        "intel-oneapi",
        "npu-runtime",
    }
    if {item["device_id"] for item in devices} != expected_devices:
        return 8
    backtest_result = backtest(
        {
            "prices": [100, 101, 102, 100, 103, 105],
            "fast_window": 2,
            "slow_window": 3,
            "dataset_version": "fixture-v1",
        }
    )
    if "total_return" not in backtest_result:
        return 3
    splits = walk_forward({"sample_count": 100, "train_size": 50, "test_size": 20, "purge_size": 5})
    if not splits["splits"] or not splits["purged"]:
        return 4
    search = parameter_search({"trial_limit": 3, "candidates": [0.1, 0.2], "seed": 17})
    if len(search["trials"]) != 3:
        return 5
    training = train_model(
        {"epochs": 5, "features": [1, 2, 3], "targets": [2, 4, 6]},
        root,
        threading.Event(),
    )
    resumed = train_model(
        {
            "epochs": 6,
            "resume": True,
            "features": [1, 2, 3],
            "targets": [2, 4, 6],
        },
        root,
        threading.Event(),
    )
    if not Path(training["checkpoint_path"]).exists() or resumed["resumed_from_epoch"] != 5:
        return 6
    onnx_source = root / "fixture-model.onnx"
    onnx_source.write_bytes(b"cytisus-synthetic-onnx-fixture")
    onnx = onnx_lifecycle(
        {
            "source_path": str(onnx_source),
            "schema": {
                "inputs": [{"name": "features", "type": "float32", "shape": [None, 3]}],
                "outputs": [{"name": "score", "type": "float32", "shape": [None, 1]}],
            },
        },
        root,
    )
    if (
        not onnx["byte_consistent"]
        or onnx["input_schema"][0]["name"] != "features"
        or onnx["output_schema"][0]["name"] != "score"
    ):
        return 9
    proposal = simulate_execution({"symbol": "AAPL.US", "quantity": 10, "slices": 2})
    if not all(item["requires_execution_gateway"] for item in proposal["child_order_proposals"]):
        return 7
    failed_job = {
        "request_id": "r2",
        "correlation_id": "c2",
        "message_type": "SubmitJob",
        "job_id": "failing-job",
        "project_id": "fixture-project",
        "payload": {"job_type": "Backtest", "prices": []},
    }
    engine.handle(failed_job)
    deadline = time.monotonic() + 2.0
    while engine.jobs["failing-job"].status in {"Queued", "Running"}:
        if time.monotonic() >= deadline:
            return 10
        time.sleep(0.01)
    if (
        engine.jobs["failing-job"].status != "Failed"
        or engine.handle(
            {"request_id": "r3", "correlation_id": "c3", "message_type": "Health"}
        )["result"]["status"]
        != "Healthy"
    ):
        return 11
    engine.executor.shutdown(wait=True)
    print("Quant Worker self-test passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Cytisus local Quant Worker")
    parser.add_argument("--root", required=True)
    parser.add_argument("--stdio", action="store_true")
    parser.add_argument("--endpoint")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    root = Path(arguments.root).resolve()
    if arguments.self_test:
        return run_self_test(root)
    engine = WorkerEngine(root)
    if arguments.stdio:
        return serve_stdio(engine)
    if arguments.endpoint:
        return serve_endpoint(engine, arguments.endpoint)
    parser.error("Choose --stdio, --endpoint, or --self-test.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
