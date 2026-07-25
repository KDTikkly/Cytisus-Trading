# ONNX Models

The v1.1.2 model registry stores:

- model ID, name, and version;
- immutable artifact path and SHA-256;
- input and output names;
- compatible execution providers;
- import time;
- Imported, Validated, Incompatible, or Retired status.

The Worker can import and hash an ONNX artifact and report discovered providers. It does not mark a model compatible when ONNX Runtime or another matching provider is absent.

The deterministic fixture path validates registry, lifecycle, and byte consistency. Full numerical parity across every optional provider remains dependent on a user-managed compatible runtime.

ONNX inference is advisory compute. It cannot authorize or submit broker orders.
