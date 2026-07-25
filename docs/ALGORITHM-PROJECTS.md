# Algorithm Projects

Algorithm projects are local, versioned research units. A project has an ID, name, type, current version, and immutable version history.

Each file record contains:

- an allowlisted relative path;
- SHA-256;
- byte size.

Project types are Research, Training, and Execution. Source labels distinguish user edits, validated Agent patches, fixtures, and imports.

## Agent patch boundary

Agent patches are limited to `.py`, `.json`, `.md`, `.txt`, `.yaml`, and `.yml` files under the selected project root. Absolute paths, empty segments, and `.` or `..` traversal are rejected. The request also has a configured token-cost ceiling.

The Agent cannot run a shell, read arbitrary local files, inspect secrets, or directly modify broker and risk services. A validated patch produces a proposed project version for review.

## Compute jobs

Projects submit typed jobs to the local Quant Worker. The UI process retains lifecycle and persistence authority. Worker output is an artifact reference, not an instruction to trade.
