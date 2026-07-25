# Cytisus v1.1.1 Product Definition Model

Version: 1.1.1
Status: Planned follow-up release
Repository: KDTikkly/Cytisus-Trading
Dependency: v1.1.0 must be completed, accepted, committed, and pushed first
Platforms: macOS 14+ and Windows 11 x64
Product language: English
Repository text: ASCII only

## 1. Release Position

Cytisus v1.1.1 is an independent, narrow follow-up release.

Its only product goal is to let users add their own AI model APIs, manage multiple providers and models, and select the model used by Cytisus for Longbridge-assisted AI operations.

v1.1.1 must not redesign or extend:

- Quantitative strategy algorithms.
- Factor discovery or retirement.
- Regime detection.
- Capital allocation.
- Execution risk controls.
- Internal netting.
- Partial-fill allocation.
- Virtual ledgers.
- Broker reconciliation.
- Manual or automated trading policy.

All v1.1.0 safety boundaries remain authoritative.

## 2. Architecture Distinction

Longbridge CLI and model providers are separate systems.

Longbridge connection:

- CLI installation.
- Longbridge OAuth authorization.
- CLI capability checks.
- Market, account, and trading commands.
- Existing v1.1.0 CLI adapter.

Model provider connection:

- User-supplied provider.
- User-supplied API key.
- Provider Base URL.
- Available model IDs.
- Primary model.
- Optional fallback models.
- Connectivity and capability checks.

A model API key is not a Longbridge API key.

A valid model provider does not authorize a Longbridge account.

A valid Longbridge login does not provide an AI model.

## 3. Product Goal

Provide a Cherry Studio-inspired provider-management experience limited to Cytisus needs:

- Provider list.
- Provider protocol type.
- API key.
- Base URL.
- Enable or disable state.
- Automatic model discovery where supported.
- Manual model entry.
- Connectivity test.
- Primary model selection.
- Ordered fallback models.

Cytisus must not become a general AI chat application.

## 4. In Scope

v1.1.1 includes:

1. Model Providers settings on macOS and Windows.
2. Multiple provider profiles.
3. Multiple models per provider.
4. OpenAI-compatible providers.
5. Anthropic-compatible providers.
6. Gemini-compatible providers.
7. Custom Base URLs.
8. Secure local API key storage.
9. Provider enable and disable state.
10. Automatic model discovery where supported.
11. Manual model-ID entry.
12. User-triggered connectivity tests.
13. Model capability metadata.
14. One primary model.
15. Ordered fallback models.
16. A minimal model-client abstraction.
17. A fixture-based read-only Longbridge integration smoke path.
18. Version and release updates to 1.1.1.
19. Focused security and compatibility tests.

## 5. Out of Scope

v1.1.1 does not include:

- Chat or conversation history.
- Assistants or personas.
- Knowledge bases.
- File upload.
- Image generation.
- Translation.
- Prompt marketplace.
- Model benchmarking.
- Automatic cheapest-model routing.
- Automatic fastest-model routing.
- Multi-model debate or voting.
- Provider billing.
- Cloud synchronization.
- API key sharing.
- API key import from other applications.
- Multiple key rotation inside one provider.
- Local model installation.
- Proxy management beyond a custom Base URL.
- Arbitrary request templates.
- Arbitrary authentication scripts.
- Changes to Longbridge OAuth.
- Changes to the execution gateway.
- Model-generated direct broker orders.

## 6. Supported Provider Protocols

### 6.1 OpenAI Compatible

Required fields:

- Provider name.
- Protocol type.
- Base URL.
- API key.
- Enabled state.
- Request timeout.

Behavior:

- Fetch models when a compatible models endpoint exists.
- Allow manual model IDs.
- Send minimal text or structured requests.
- Use tool calling only when the model is marked capable.
- Do not assume every compatible gateway implements every endpoint.

### 6.2 Anthropic Compatible

Required fields are the same.

Behavior:

- Manual model entry.
- Provider-specific connectivity check.
- Tool-use capability metadata.
- Protocol-specific version headers.
- Model discovery is optional.

### 6.3 Gemini Compatible

Required fields are the same.

Behavior:

- Fetch models where supported.
- Allow manual model IDs.
- Minimal generation connectivity check.
- Function-calling capability metadata.

### 6.4 Custom Profiles

Users may create multiple named profiles using the supported protocol types.

The protocol determines request construction. The display name is user-defined.

No raw request scripting language is allowed.

## 7. Provider Data Model

Suggested provider fields:

- provider_id
- display_name
- protocol_type
- base_url
- enabled
- request_timeout_seconds
- created_at
- updated_at
- last_tested_at
- last_test_status
- last_test_message
- secret_reference

The plaintext API key must not be stored in the application database.

## 8. Model Data Model

Suggested model fields:

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

Model source:

- Discovered
- Manual

Capability state:

- Supported
- Unsupported
- Unknown

Unknown must not be treated as Supported for tool calling.

## 9. Model Selection

Support:

- One primary Longbridge orchestration model.
- Zero or more ordered fallback models.

Fallback is allowed only for transport or provider availability failure.

Fallback must not bypass:

- A valid model refusal.
- A safety rejection.
- A user-confirmation requirement.
- A Longbridge risk rejection.
- A valid no-action response.

Disabled providers and models must be skipped.

## 10. Secure Secret Storage

### macOS

Use macOS Keychain Services.

### Windows

Use Windows Credential Manager or DPAPI CurrentUser protection.

Requirements:

- Save a new key.
- Replace a key.
- Retrieve a key only for provider requests.
- Delete the key when its provider is deleted.
- Store only a secret reference in the database.
- Never store the key in plaintext files.
- Never pass it to Longbridge CLI.
- Never include it in command-line arguments.

UI behavior:

- Show a masked saved state.
- Allow Replace API Key.
- Do not provide a normal full-key reveal action.
- Confirm deletion when the provider is assigned as primary or fallback.

Logs must redact:

- api_key
- apikey
- apiKey
- token
- authorization
- secret
- x-api-key

## 11. Base URL Safety

- Default to HTTPS.
- Allow HTTP without extra warning only for localhost, 127.0.0.1, or ::1.
- Require explicit confirmation for any other HTTP endpoint.
- Use structured URL parsing.
- Keep endpoint construction inside protocol adapters.
- Do not copy special URL suffix conventions from another application.
- Do not silently rewrite a valid custom endpoint incorrectly.

## 12. User Experience

Add:

Settings -> Model Providers

### Provider List

Show:

- Name.
- Protocol.
- Enabled state.
- Enabled-model count.
- Connection status.
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

### Add or Edit Provider

Fields:

- Provider Name.
- Protocol Type.
- Base URL.
- API Key or Saved Key state.
- Request Timeout.
- Enabled state.

Rules:

- Name is required and unique.
- Base URL must be valid.
- Remote HTTP requires explicit warning confirmation.
- A provider may be saved as Not Verified.
- Enabling may require a successful test.

### Manage Models

Actions:

- Fetch Models.
- Add Model Manually.
- Enable or Disable.
- Edit Display Name.
- Remove.
- Set as Primary.
- Add to Fallbacks.
- Remove from Fallbacks.
- Reorder Fallbacks.

Discovered models are not automatically enabled.

### Connectivity Test

A user-triggered test should:

1. Validate configuration.
2. Retrieve the key from secure storage.
3. Attempt model discovery where supported.
4. Use a selected model for a minimal non-sensitive request.
5. Save only a sanitized result.
6. Never call a Longbridge trading function.

Result categories:

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

## 13. Model Client

Add equivalent macOS and Windows model-client contracts:

- listModels
- testConnection
- generateText
- generateStructuredResponse
- requestToolDecision

Requests must be built in-process. Do not invoke curl, shell scripts, or arbitrary user commands.

## 14. Minimal Longbridge Integration

Provide one safe read-only smoke path:

Selected model
-> fixed system instruction
-> allowlisted read-only Longbridge tool schema
-> structured tool decision
-> existing Longbridge CLI adapter
-> sanitized result

Allowed smoke tools may include:

- Quote.
- Market status.
- Symbol lookup.

Automated tests use fixtures.

Hard rules:

- The model never runs a shell command.
- The model never receives Longbridge credentials.
- The model never creates raw CLI arguments.
- The coordinator maps a typed decision to an allowlisted adapter method.
- Trading and account-mutation tools are rejected.
- Existing v1.1.0 trading continues only through the strategy and execution gateway.

## 15. Provider and Model Status

Provider states:

- Not Configured
- Not Verified
- Ready
- Degraded
- Rate Limited
- Unauthorized
- Unavailable
- Disabled

Model states:

- Available
- Unverified
- Unavailable
- Disabled

A primary model must be enabled and Ready before model-assisted Longbridge features can start.

Without a ready model:

- Deterministic v1.1.0 features may remain available.
- Model-assisted features are disabled.
- Trading safety behavior is unchanged.
- The application shows a setup requirement.

## 16. Cross-platform Parity

macOS and Windows must have the same:

- Provider protocol types.
- Provider fields.
- Provider statuses.
- Model fields.
- Model statuses.
- Primary selection.
- Fallback ordering.
- Connection-test result categories.
- Redaction rules.
- Read-only smoke scenario.

Secure storage remains platform-specific.

Pixel-level visual equality is not required.

## 17. Persistence and Migration

Add an idempotent migration from v1.1.0.

Suggested new tables:

- model_providers
- provider_models
- model_role_assignments
- provider_test_events

Do not add an API-key column.

Provider test events store only:

- event_id
- provider_id
- model_record_id_optional
- started_at
- completed_at
- result_category
- sanitized_message
- latency_ms_optional

## 18. Import and Export

v1.1.1 does not require provider import or export.

If application settings export already exists:

- Export provider metadata only with explicit user action.
- Exclude API keys and secret references.
- Imported providers remain disabled until a key is added and verified.

## 19. Testing Strategy

Required focused tests:

1. Provider metadata contains no plaintext key.
2. Secret-store contract save, replace, retrieve, and delete.
3. Secret redaction.
4. OpenAI-compatible request construction.
5. Anthropic-compatible request construction.
6. Gemini-compatible request construction.
7. HTTPS and localhost HTTP validation.
8. Remote HTTP warning or rejection.
9. Model-discovery fixture parsing.
10. Manual model entry.
11. Primary selection.
12. Fallback ordering.
13. Disabled-provider skipping.
14. Connectivity-status mapping.
15. Fixture minimal completion.
16. Fixture structured tool decision.
17. Fixture read-only Longbridge quote flow.
18. Trading-tool rejection.
19. v1.1.0 database migration.
20. ASCII validation.

Do not add:

- UI snapshot tests.
- Real provider requests in CI.
- Real API keys.
- Large provider compatibility matrices.
- Cost or quality benchmarks.
- Real Longbridge orders.

## 20. Documentation

Add:

- docs/PDM-v1.1.1.md
- docs/MODEL-PROVIDERS.md
- docs/CODEX-v1.1.1-PROMPT.md

Update:

- README.md
- INSTALL.txt
- PRIVACY.md
- SANITIZATION.json

Documentation must state:

- Users supply their own model API.
- Keys remain local in operating-system secure storage.
- Model-provider authorization is separate from Longbridge OAuth.
- Multiple providers and models are supported.
- Provider usage may incur charges from the provider.
- Cytisus does not supply or resell model API access.
- Trading safety controls are unchanged.
- API keys must not be included in issues, logs, screenshots, or bug reports.

## 21. Version and Release

Update to version 1.1.1.

Expected artifacts:

- dist/Cytisus-Trading-1.1.1-universal.dmg
- dist/Cytisus-Trading-1.1.1-win11-x64.exe

Preserve:

- Universal 2 macOS build.
- Apple signing and notarization support.
- Windows self-contained single-file build.
- Existing dual-platform release workflow.
- English-only ASCII validation.

## 22. Acceptance Criteria

v1.1.1 is accepted only when:

- Accepted v1.1.0 is already present.
- Both apps start without a provider.
- Both apps expose Model Providers settings.
- Users can add multiple providers.
- Users can add multiple models per provider.
- OpenAI-compatible, Anthropic-compatible, and Gemini-compatible protocols exist.
- Custom Base URLs work.
- Keys use operating-system secure storage.
- Plaintext keys never enter the database or logs.
- Providers and models can be enabled and disabled.
- Models can be discovered where supported.
- Models can be added manually.
- Connectivity tests categorize failures.
- A primary model can be selected.
- Ordered fallback models can be selected.
- Disabled or unavailable providers are skipped.
- Fixture minimal model invocation succeeds.
- Fixture read-only Longbridge orchestration succeeds.
- Trading tools are rejected by the smoke coordinator.
- Longbridge OAuth remains unchanged.
- v1.1.0 trading and risk behavior remains unchanged.
- ASCII validation passes.
- Both 1.1.1 release artifacts build.
- No real key, account, position, or order is committed.

## 23. Final Scope Rule

When implementation choices are ambiguous, choose the smaller change that securely supports multiple providers and models.

Do not turn v1.1.1 into a chat product or a redesign of Cytisus.
