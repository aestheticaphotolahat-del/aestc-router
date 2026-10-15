import { describe, expect, it } from "vitest";

import {
  assertSiwcConnectedAppRequest,
  getSiwcBoundaryConfig,
  SIWC_CONNECTED_APP_CONTRACT,
  SiwcBoundaryError,
} from "../../src/lib/aestc/siwcBoundary.js";

const enabledConfig = {
  enabled: true,
  appId: "aestc-ai-workspace",
};

const validRequest = {
  appId: "aestc-ai-workspace",
  purpose: "aestc-ai-workspace",
  transport: "connected-app",
  userAuthorized: true,
  credentialLocation: "user-local",
  pooledAccounts: 0,
};

function expectBoundaryCode(fn, code) {
  expect(fn).toThrow(SiwcBoundaryError);
  try {
    fn();
  } catch (error) {
    expect(error.code).toBe(code);
  }
}

describe("AESTC SIWC connected-app boundary", () => {
  it("is disabled by default", () => {
    expect(getSiwcBoundaryConfig({})).toEqual({ enabled: false, appId: "" });
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest(validRequest, { enabled: false, appId: "aestc-ai-workspace" }),
      "siwc_disabled",
    );
  });

  it("requires a configured connected-app id when enabled", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest(validRequest, { enabled: true, appId: "" }),
      "siwc_config_invalid",
    );
  });

  it("rejects the wrong application", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest({ ...validRequest, appId: "other-app" }, enabledConfig),
      "siwc_app_mismatch",
    );
  });

  it("rejects requests outside AESTC AI Workspace purpose", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest({ ...validRequest, purpose: "generic-router" }, enabledConfig),
      "siwc_purpose_invalid",
    );
  });

  it("rejects general-purpose provider/proxy transport", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest({ ...validRequest, transport: "provider" }, enabledConfig),
      "siwc_generic_proxy_forbidden",
    );
  });

  it("requires explicit user authorization", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest({ ...validRequest, userAuthorized: false }, enabledConfig),
      "siwc_user_authorization_required",
    );
  });

  it("requires persistent credential ownership to remain local", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest({ ...validRequest, credentialLocation: "vps" }, enabledConfig),
      "siwc_credential_location_invalid",
    );
  });

  it("rejects account pooling or rotation", () => {
    expectBoundaryCode(
      () => assertSiwcConnectedAppRequest({ ...validRequest, pooledAccounts: 1 }, enabledConfig),
      "siwc_account_pool_forbidden",
    );
  });

  it("accepts only the scoped connected-app request", () => {
    expect(assertSiwcConnectedAppRequest(validRequest, enabledConfig)).toEqual(validRequest);
    expect(SIWC_CONNECTED_APP_CONTRACT).toEqual({
      purpose: "aestc-ai-workspace",
      transport: "connected-app",
      credentialLocation: "user-local",
    });
  });
});
