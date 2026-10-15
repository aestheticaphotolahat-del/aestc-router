const REQUIRED_PURPOSE = "aestc-ai-workspace";
const REQUIRED_TRANSPORT = "connected-app";
const REQUIRED_CREDENTIAL_LOCATION = "user-local";

export class SiwcBoundaryError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "SiwcBoundaryError";
    this.code = code;
  }
}

export function getSiwcBoundaryConfig(env = process.env) {
  return {
    enabled: env.AESTC_SIWC_CONNECTED_APP_ENABLED === "true",
    appId: env.AESTC_SIWC_CONNECTED_APP_ID?.trim() || "",
  };
}

export function assertSiwcConnectedAppRequest(request, config = getSiwcBoundaryConfig()) {
  if (!config.enabled) {
    throw new SiwcBoundaryError("siwc_disabled", "AESTC SIWC connected-app transport is disabled.");
  }

  if (!config.appId) {
    throw new SiwcBoundaryError("siwc_config_invalid", "AESTC SIWC connected-app ID is not configured.");
  }

  if (!request || typeof request !== "object") {
    throw new SiwcBoundaryError("siwc_request_invalid", "AESTC SIWC request metadata is required.");
  }

  if (request.appId !== config.appId) {
    throw new SiwcBoundaryError("siwc_app_mismatch", "AESTC SIWC request does not match the connected application.");
  }

  if (request.purpose !== REQUIRED_PURPOSE) {
    throw new SiwcBoundaryError("siwc_purpose_invalid", "AESTC SIWC request is outside the connected application's purpose.");
  }

  if (request.transport !== REQUIRED_TRANSPORT) {
    throw new SiwcBoundaryError("siwc_generic_proxy_forbidden", "AESTC SIWC cannot be used as a general-purpose provider or proxy.");
  }

  if (request.userAuthorized !== true) {
    throw new SiwcBoundaryError("siwc_user_authorization_required", "AESTC SIWC request requires explicit user authorization.");
  }

  if (request.credentialLocation !== REQUIRED_CREDENTIAL_LOCATION) {
    throw new SiwcBoundaryError("siwc_credential_location_invalid", "Persistent SIWC credentials must remain on the user-controlled local runtime.");
  }

  if (request.pooledAccounts !== 0) {
    throw new SiwcBoundaryError("siwc_account_pool_forbidden", "AESTC SIWC does not allow account pooling or rotation.");
  }

  return {
    appId: request.appId,
    purpose: REQUIRED_PURPOSE,
    transport: REQUIRED_TRANSPORT,
    userAuthorized: true,
    credentialLocation: REQUIRED_CREDENTIAL_LOCATION,
    pooledAccounts: 0,
  };
}

export const SIWC_CONNECTED_APP_CONTRACT = Object.freeze({
  purpose: REQUIRED_PURPOSE,
  transport: REQUIRED_TRANSPORT,
  credentialLocation: REQUIRED_CREDENTIAL_LOCATION,
});
