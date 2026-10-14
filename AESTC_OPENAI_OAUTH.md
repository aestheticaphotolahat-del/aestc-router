# AESTC ChatGPT OAuth sidecar

This AESTC integration keeps 9Router as the public AI gateway while using `EvanZhouDev/openai-oauth` as a private OpenAI-compatible upstream backed by a ChatGPT account.

## Flow

```text
AESTC apps -> 9Router -> OpenAI-compatible node (prefix: cgo)
                     -> openai-oauth:10531/v1
                     -> ChatGPT OAuth credentials (~/.codex/auth.json)
```

The sidecar is intentionally not published on a host port. Only containers on the 9Router Compose network can reach it.

## Responsibility split

`openai-oauth` owns ChatGPT OAuth credential loading, refresh, account-aware model discovery, and the compatible upstream transport. 9Router continues to own application API keys, routing, aliases, usage accounting, fallbacks, and request/response translation.

## Deployment

Build the pinned sidecar image:

```bash
docker build -t aestc-openai-oauth:2.0.0 -f Dockerfile.openai-oauth .
```

Run 9Router with the overlay:

```bash
docker compose -f docker-compose.yml -f docker-compose.openai-oauth.yml up -d
```

`AESTC_OPENAI_OAUTH_CODEX_HOME` may override the host Codex home mounted into the sidecar. The directory must contain a valid `auth.json` and must be writable so refreshed credentials can be persisted.

## Register the provider node

The bootstrap script is idempotent. It creates or updates an OpenAI-compatible node named `ChatGPT OAuth` with prefix `cgo`, API type `chat`, and internal base URL `http://openai-oauth:10531/v1`.

```bash
export ROUTER_BASE_URL=http://127.0.0.1:20128
export ROUTER_INITIAL_PASSWORD='...'
./scripts/aestc-openai-oauth-bootstrap.sh
```

9Router v0.5.95 requires an API-key value for OpenAI-compatible connections. The sidecar does not use that internal placeholder for authentication, so security depends on the sidecar remaining private to the Docker network.

## Verification gate

Before use, verify:

- sidecar `/v1/models` returns the account-discovered model set;
- 9Router provider model discovery returns the same models;
- 9Router public `/v1/models` exposes the text models under `cgo/*`;
- 9Router `/v1/responses` succeeds with `cgo/<model>`;
- 9Router `/v1/chat/completions` succeeds with `cgo/<model>`;
- the sidecar has no published host port.

AESTC staging was verified with `cgo/gpt-5.6-sol` and a synthetic exact-response canary. `gpt-image-2` is discovered and may appear in the public model catalog, but it is not valid for this text chat/responses route and must not be selected as a text model. Production remains a separate approval gate.
