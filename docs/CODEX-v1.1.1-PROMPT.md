# Codex Prompt: Implement Cytisus v1.1.1 Model Providers

Repository: KDTikkly/Cytisus-Trading
Target release: 1.1.1
Execution order: Run only after v1.1.0 is complete, accepted, committed, and pushed
Output language: English only
Repository text: ASCII only

## 1. Verify the Precondition

Read the repository and verify that the checked-out branch contains the completed v1.1.0 implementation described by docs/PDM-v1.1.md.

Confirm the material v1.1.0 foundations exist:

- Native SwiftUI macOS application.
- Native WPF Windows application.
- Longbridge CLI adapter.
- Local persistence.
- Strategy runtime.
- Parameter governance.
- Paper Only and Live controls.
- Factor governance.
- Execution gateway and safety boundaries.
- Version 1.1.0 metadata or an equivalent accepted v1.1.0 commit.

If v1.1.0 is not present, stop without modifying code. Report the missing precondition.

Do not run this prompt concurrently with the v1.1.0 prompt series.

## 2. Add the Authoritative Files

Add the supplied PDM as:

docs/PDM-v1.1.1.md

Add this prompt as:

docs/CODEX-v1.1.1-PROMPT.md

Also create:

docs/MODEL-PROVIDERS.md

Read the PDM before implementation.

## 3. Narrow Scope

The only product goal is:

Allow users to securely add multiple AI model providers and multiple models, select a primary model and fallbacks, and make the selected model available to the Longbridge AI orchestration layer.

Do not change:

- Quant algorithms.
- Factor algorithms.
- Regime algorithms.
- Capital allocation.
- Execution policy.
- Risk limits.
- Netting.
- Fill allocation.
- Virtual ledgers.
- Trading authorization.
- Manual trading policy.

## 4. Architecture Boundary

Longbridge CLI and model APIs are separate.

Longbridge CLI continues to use the v1.1.0 installation, OAuth, and restricted process adapter.

Model provider APIs:

- Are configured by the user.
- Use separate secure storage.
- Supply the AI model used by Cytisus.
- Must not receive Longbridge OAuth credentials.
- Must not bypass the CLI adapter or execution gateway.

Do not label a model API key as a Longbridge API key.

## 5. UX Reference

Use Cherry Studio only as a provider-settings UX reference:

- Provider list.
- Provider enable switch.
- API key.
- Base URL.
- Model discovery.
- Manual model entry.
- Connectivity check.
- Default model selection.

Do not copy source code, assets, branding, or text.

Do not add chat, assistants, knowledge bases, translation, image generation, or prompt management.

## 6. Provider Protocols

Implement equivalent macOS and Windows support for:

- OpenAI Compatible.
- Anthropic Compatible.
- Gemini Compatible.

Support multiple named provider profiles.

Each provider stores:

- provider_id
- display_name
- protocol_type
- base_url
- enabled
- request_timeout_seconds
- last_tested_at
- last_test_status
- last_test_message
- secret_reference

Never store the plaintext key in the main database.

## 7. Secure Secret Storage

Create one secret-store contract and platform-specific implementations.

macOS:

Use Keychain Services.

Windows:

Use Windows Credential Manager or DPAPI CurrentUser protection.

Required operations:

- Save.
- Replace.
- Retrieve for provider requests.
- Delete with provider deletion.

Hard rules:

- No plaintext key database column.
- No plaintext key settings file.
- No key in logs.
- No key in crash messages.
- No key in command-line arguments.
- No key in Longbridge CLI environment variables.
- Database stores only a secret reference.
- UI shows a masked saved state.
- UI supports Replace API Key.
- Do not add a normal full-key reveal action.

## 8. Persistence and Migration

Add an idempotent migration from v1.1.0.

Add logical stores for:

- model_providers
- provider_models
- model_role_assignments
- provider_test_events

Model fields:

- model_record_id
- provider_id
- model_id
- display_name
- enabled
- source
- supports_text
- supports_tool_calling
- supports_structured_output
- context_window_optional
- created_at
- updated_at
- last_verified_at

Source is Discovered or Manual.

Capabilities are Supported, Unsupported, or Unknown.

Unknown is not sufficient for tool calling.

## 9. Provider Clients

Create equivalent model-provider client contracts on macOS and Windows:

- listModels
- testConnection
- generateText
- generateStructuredResponse
- requestToolDecision

Implement protocol-specific adapters.

OpenAI Compatible:

- Custom Base URL.
- Model discovery where supported.
- Manual model IDs.
- In-process HTTP requests.
- No curl or shell command.

Anthropic Compatible:

- Custom Base URL.
- Manual model IDs.
- Required protocol headers.
- Model discovery may be unavailable.

Gemini Compatible:

- Custom Base URL.
- Model discovery where supported.
- Manual model IDs.

Do not assume all providers support all optional features.

## 10. Base URL Rules

- Default to HTTPS.
- Allow HTTP without extra warning only for localhost, 127.0.0.1, or ::1.
- Require explicit confirmation for other HTTP endpoints.
- Use structured URL parsing.
- Keep endpoint construction inside protocol adapters.
- Do not implement arbitrary request scripting.
- Do not add a raw custom-header editor unless the supported protocols require it.

## 11. User Interface

Add:

Settings -> Model Providers

Implement it in SwiftUI and WPF.

Provider list shows:

- Name.
- Protocol.
- Enabled state.
- Model count.
- Connection state.
- Last tested time.
- Primary or fallback badge.

Actions:

- Add Provider.
- Edit.
- Enable or Disable.
- Test Connection.
- Manage Models.
- Replace API Key.
- Delete.

Provider editor fields:

- Provider Name.
- Protocol Type.
- Base URL.
- API Key or Saved Key state.
- Request Timeout.
- Enabled state.

Model management actions:

- Fetch Models.
- Add Model Manually.
- Enable or Disable.
- Edit Display Name.
- Remove.
- Set as Primary.
- Add to Fallbacks.
- Remove from Fallbacks.
- Reorder Fallbacks.

Do not automatically enable all discovered models.

## 12. Connectivity Test

Connectivity tests are user-triggered.

Map results into:

- InvalidConfiguration
- InvalidBaseURL
- InsecureEndpointRejected
- SecretStoreFailure
- DNSFailure
- ConnectionTimeout
- TLSFailure
- Unauthorized
- Forbidden
- RateLimited
- ProviderUnavailable
- ModelNotFound
- UnsupportedCapability
- ResponseParseFailure
- Cancelled
- Unknown

Test flow:

- Validate configuration.
- Retrieve key from secure storage.
- Attempt discovery where supported.
- Send a minimal non-sensitive request using a selected model.
- Store only sanitized status and optional latency.
- Never call a Longbridge trading command.
- No real provider request is allowed in CI.

## 13. Primary and Fallback Models

Support:

- One primary Longbridge orchestration model.
- Zero or more ordered fallback models.

Fallback is allowed only for provider transport or availability failure.

Fallback cannot bypass:

- A valid refusal.
- A safety rejection.
- A confirmation requirement.
- A Longbridge risk rejection.
- A valid no-action response.

Skip disabled and unavailable providers.

## 14. Minimal Longbridge Integration

Connect the selected model to a minimal model-backed coordinator using the existing v1.1.0 CLI adapter.

For the v1.1.1 validation path, expose only allowlisted read-only tools:

- Quote.
- Market status.
- Symbol lookup.

Flow:

selected model
-> fixed system instruction
-> approved read-only tool schema
-> structured tool decision
-> existing CLI adapter
-> sanitized result

Automated tests use fixtures.

Hard rules:

- The model never executes a shell command.
- The model never receives Longbridge credentials.
- The model never creates raw CLI arguments.
- Typed tool decisions map to allowlisted adapter methods.
- Trading and account-mutation tools are rejected.
- Existing v1.1.0 trading remains behind the strategy and execution gateway.
- Do not redesign trading.

## 15. Logging and Redaction

Redact:

- api_key
- apikey
- apiKey
- token
- authorization
- secret
- x-api-key

Sanitize:

- Request headers.
- Provider errors.
- Test output.
- Diagnostic exports.
- Audit events.
- UI error details.

Logs may contain provider ID, protocol, model ID, status, and latency. They may not contain the key.

## 16. Documentation and Metadata

Update:

- README.md
- INSTALL.txt
- PRIVACY.md
- SANITIZATION.json

Document:

- Users supply their own model API.
- Keys remain in OS secure storage.
- Model-provider authorization is separate from Longbridge OAuth.
- Multiple providers and models are supported.
- Provider usage may incur provider charges.
- Cytisus does not supply or resell model access.
- Trading safety controls are unchanged.
- Provider add, test, enable, model selection, and deletion steps.
- Keep all tracked text English and ASCII only.

## 17. Version and Release

Update version references to 1.1.1.

Expected artifacts:

- dist/Cytisus-Trading-1.1.1-universal.dmg
- dist/Cytisus-Trading-1.1.1-win11-x64.exe

Preserve:

- Native SwiftUI macOS application.
- Native WPF Windows application.
- Universal 2 macOS build.
- Windows self-contained single-file build.
- Apple signing and notarization support.
- Existing dual-platform GitHub Actions workflow.
- ASCII validation.

## 18. Focused Tests

Add only focused deterministic tests for:

- No plaintext key in provider records.
- Secret-store contract save, replace, retrieve, and delete through test doubles.
- Secret redaction.
- OpenAI-compatible request construction.
- Anthropic-compatible request construction.
- Gemini-compatible request construction.
- HTTPS and local HTTP validation.
- Remote HTTP warning or rejection.
- Model-discovery fixture parsing.
- Manual model entry.
- Primary assignment.
- Ordered fallback behavior.
- Disabled-provider skipping.
- Connectivity result mapping.
- Fixture minimal text generation.
- Fixture structured tool decision.
- Fixture read-only Longbridge quote flow.
- Trading-tool rejection.
- v1.1.0 to v1.1.1 migration.
- ASCII validation.

Testing rules:

- No real API keys.
- No real provider calls in CI.
- No network dependency.
- No real Longbridge account.
- No real orders.
- No UI snapshots.
- No provider benchmark.
- No large compatibility matrix.
- Run targeted tests once.
- Rerun only a failed target and one final focused smoke.
- Run the complete cross-platform release workflow once near completion.

## 19. Scope Protection

Do not implement:

- Chat.
- Conversation history.
- Assistants.
- Knowledge bases.
- Prompt libraries.
- Model benchmarking.
- Automatic cost routing.
- Multi-model voting.
- Multiple API-key rotation.
- Local model installation.
- New quant logic.
- New factor logic.
- New execution logic.
- Manual trading.

When uncertain, choose the smaller secure provider-management implementation.

## 20. Completion

Before finishing:

- Confirm v1.1.0 remains intact.
- Confirm both platforms have equivalent provider behavior.
- Confirm no plaintext key is persisted.
- Confirm no key appears in logs or fixtures.
- Confirm tests require no real provider.
- Confirm trading tools are rejected by the smoke coordinator.
- Run ASCII validation.
- Run focused tests.
- Build both release artifacts locally or through the existing workflow.
- Search tracked files for secrets, tokens, account data, orders, and absolute user paths.
- Commit all v1.1.1 changes.
- Push without force-pushing.

Suggested commit message:

feat: add secure multi-model provider configuration

## 21. Final Response Format

Report only:

- Implementation summary.
- v1.1.0 precondition verification.
- Provider protocols implemented.
- Secure storage implementation by platform.
- Model selection and fallback behavior.
- Longbridge read-only smoke integration.
- Files changed.
- Tests and builds actually executed.
- Artifact paths and SHA-256 values.
- Commit SHA.
- Push status.
- Known limitations.
- User setup steps.

Do not claim success for an action that was not actually completed.

## Current Packaging Override

The repository owner instructed that packaging must wait until v1.1.3. Therefore v1.1.1 implementation work must not create, upload, tag, or publish a DMG, Windows installer, GitHub Actions release artifact, or GitHub Release. Source metadata and release scripts may be prepared for version 1.1.1, but the complete cross-platform packaging step above is deferred to v1.1.3.
