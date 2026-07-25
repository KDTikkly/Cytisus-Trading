# Model Providers

Cytisus v1.1.1 lets users configure their own model API providers. Cytisus does not supply, resell, proxy, or pay for model access. Provider usage may incur charges from the selected provider.

Model-provider authorization is separate from Longbridge OAuth:

- A model API key authorizes only the configured model endpoint.
- The key is never passed to Longbridge CLI.
- A working model does not authorize a brokerage account.
- A working Longbridge login does not provide a model.
- Deterministic v1.1.0 Local Paper behavior remains available without a model.

## Supported protocols

- OpenAI Compatible
- Anthropic Compatible
- Gemini Compatible

Each named provider profile stores only metadata: provider ID, display name, protocol, Base URL, enabled state, timeout, sanitized test status, timestamps, and a secure-storage reference.

The application database has no API-key column.

## Secure storage

macOS stores provider keys in Keychain Services with a device-local, after-first-unlock accessibility policy.

Windows stores provider keys in a CurrentUser DPAPI-protected blob. The file name is derived from a one-way digest of the secret reference. Plaintext is available only in process memory while a provider request is constructed.

The UI:

- Uses a masked key field.
- Shows only whether a key is saved.
- Supports key replacement.
- Has no full-key reveal action.
- Deletes the secure item with the provider.

Never include an API key in an issue, log, screenshot, diagnostic export, or bug report.

## Base URL policy

- HTTPS is accepted.
- HTTP is accepted without an extra warning only for localhost, 127.0.0.1, and ::1.
- Other HTTP endpoints require explicit confirmation.
- URL parsing and endpoint construction stay inside protocol-specific code.
- Arbitrary scripts, shell commands, request templates, and custom authentication programs are not supported.

## Provider setup

1. Open Settings and locate Model Providers.
2. Select Add Provider.
3. Enter a unique name, protocol, Base URL, request timeout, and API key.
4. Save. A new provider starts as Not Verified and disabled.
5. Fetch models when the protocol and endpoint support discovery, or add a model ID manually.
6. Select one model and run Test Connection.
7. Enable the provider and model only after a successful test.
8. Set one enabled model as Primary.
9. Optionally add enabled models as ordered Fallback entries.

Discovered models are never enabled automatically. Tool use requires an explicit Supported capability; Unknown is treated as not supported.

## Connectivity results

Tests are user-triggered and use a minimal non-sensitive generation request. Sanitized results map to:

- Ready
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

No connectivity test invokes Longbridge trading or account-mutation commands.

## Primary and fallback behavior

The role store contains one Primary assignment and zero or more ordered Fallback assignments. Disabled, unavailable, or unverified providers and models are skipped.

Fallback is limited to transport or provider-availability failure. It must not bypass:

- A valid refusal.
- A safety rejection.
- A confirmation requirement.
- A Longbridge risk rejection.
- A valid no-action response.

## Read-only Longbridge smoke boundary

The model integration exposes only typed read-only decisions:

- Quote
- MarketStatus
- SymbolLookup

The coordinator maps an allowlisted decision to a typed gateway method. A model never receives Longbridge credentials, never creates raw CLI arguments, and never executes a process. Trading and account-mutation tool names are rejected.

The existing strategy runtime and execution gateway remain the only trading-policy path. Live Longbridge submission remains a rejecting boundary pending the separate v1.1.3 authentication and verified command-mapping work.

## Persistence

Schema version 6 adds logical stores for:

- model_providers
- provider_models
- model_role_assignments
- provider_test_events

Provider test events contain IDs, timestamps, a result category, a sanitized message, and optional latency. They contain no request headers or API keys.

## Offline validation

Repository fixtures cover model discovery, minimal text generation, a structured Quote decision, and a read-only quote result. Focused tests use an in-memory secret store and synthetic HTTP responses. They require no provider network, real key, Longbridge account, or order.

## Release note

The source version is 1.1.1. Per the repository owner's packaging plan, no v1.1.1 DMG, Windows installer, release tag, or GitHub Release is produced. Cross-platform packaging resumes at v1.1.3.
