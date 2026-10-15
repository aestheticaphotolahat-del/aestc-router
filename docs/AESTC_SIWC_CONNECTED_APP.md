# AESTC SIWC connected-app boundary

Status: design gate only. Disabled by default. No production enablement.

## Goal

Prepare AESTC Router for a future OpenAI-approved Sign in with ChatGPT (SIWC) commercial/private integration without turning SIWC into a general-purpose provider, account pool, or generic `/v1` proxy.

The connected application is **AESTC AI Workspace**. 9Router may be used internally as transport infrastructure, but SIWC traffic must remain scoped to that connected application and to requests initiated or explicitly authorized by its signed-in user.

## Current approval gate

AESTC has submitted the commercial/private SIWC interest form. Until OpenAI provides the applicable approval/client registration:

- SIWC stays disabled.
- No VPS-hosted SIWC OAuth flow is activated.
- No SIWC access token or refresh token is persisted on the VPS.
- No new SIWC request is sent from staging or production.
- Existing `cgo/*` / openai-oauth behavior remains unchanged.

The earlier local canary was a one-off validation on a user-controlled Windows runtime. It is not the production architecture.

## Clean-room rule

Production AESTC code must be independently authored. Do not copy or modify code from the OpenAI Sign in with ChatGPT DevKit, whose source is distributed under a noncommercial license.

Protocol behavior may be implemented only from applicable public standards, OpenAI documentation/terms, and credentials or registration details OpenAI provides for AESTC.

## Mandatory boundary

A SIWC request is eligible only when all of the following are true:

1. The feature flag is explicitly enabled.
2. A single configured connected-app ID matches the request's app ID.
3. The request declares the `aestc-ai-workspace` purpose.
4. The transport is `connected-app`, never a generic provider/proxy path.
5. The request is initiated or explicitly authorized by the signed-in user.
6. Persistent credentials remain on the user-controlled local runtime.
7. No account pooling/rotation is involved.

The boundary must fail closed.

## Explicit non-goals

- No `csiwc/*` public provider family.
- No generic OpenAI-compatible endpoint backed by SIWC plan usage.
- No use from arbitrary Claude/Codex/third-party tools merely because they can call 9Router.
- No shared account pool, token rotation, quota bypass, or failover between ChatGPT accounts.
- No server-side refresh-token vault for SIWC.
- No fallback from SIWC to browser automation or private ChatGPT web endpoints.

## Intended architecture after approval

```text
User-controlled AESTC AI Workspace runtime
  - explicit user action / authorized automation
  - local encrypted SIWC credential owner
          |
          | app-scoped request, no persistent credential transfer
          v
AESTC connected-app transport boundary
          |
          | approved OpenAI SIWC mechanism
          v
OpenAI Responses API
```

Remote infrastructure may carry app-scoped request data only if the approved SIWC deployment model permits it. The exact credential handoff/refresh design remains blocked on OpenAI's commercial/private registration details.

## Environment contract

- `AESTC_SIWC_CONNECTED_APP_ENABLED` — must equal `true` to enable the boundary. Default is disabled.
- `AESTC_SIWC_CONNECTED_APP_ID` — stable AESTC connected-app identifier. Required when enabled.

No SIWC secrets belong in these variables.

## Phase-1 PASS criteria

This design-only phase passes when:

- policy is default-off;
- wrong/missing app IDs fail closed;
- generic proxy usage fails closed;
- requests without explicit user authorization fail closed;
- non-local persistent credential ownership fails closed;
- account pooling fails closed;
- a correctly scoped AESTC AI Workspace request passes policy validation;
- no existing provider registry or runtime route is changed.

## Activation gate

Do not wire this policy into a live route until OpenAI returns the commercial/private SIWC approval/client registration and its deployment requirements are reviewed against this document.
