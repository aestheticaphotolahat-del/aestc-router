#!/usr/bin/env bash
set -euo pipefail

if [ -n "${ROUTER_ENV_FILE:-}" ]; then
  set -a
  . "$ROUTER_ENV_FILE"
  set +a
fi

BASE_URL="${ROUTER_BASE_URL:-http://127.0.0.1:20128}"
PASSWORD="${ROUTER_INITIAL_PASSWORD:-${INITIAL_PASSWORD:-}}"
NODE_NAME="${OPENAI_OAUTH_NODE_NAME:-ChatGPT OAuth}"
NODE_PREFIX="${OPENAI_OAUTH_NODE_PREFIX:-cgo}"
NODE_BASE_URL="${OPENAI_OAUTH_NODE_BASE_URL:-http://openai-oauth:10531/v1}"
CONNECTION_NAME="${OPENAI_OAUTH_CONNECTION_NAME:-ChatGPT OAuth Sidecar}"
DUMMY_KEY="${OPENAI_OAUTH_INTERNAL_KEY:-aestc-internal-sidecar}"

if [ -z "$PASSWORD" ]; then
  echo "ROUTER_INITIAL_PASSWORD or INITIAL_PASSWORD is required" >&2
  exit 1
fi

headers=$(mktemp)
body=$(mktemp)
trap 'rm -f "$headers" "$body"' EXIT

login_payload=$(python3 -c 'import json,sys; print(json.dumps({"password":sys.argv[1]}))' "$PASSWORD")
curl -fsS -D "$headers" -o "$body" -H 'content-type: application/json' --data-binary "$login_payload" "$BASE_URL/api/auth/login"
TOKEN=$(sed -n 's/^set-cookie: auth_token=\([^;]*\).*/\1/ip' "$headers" | head -n1)
if [ -z "$TOKEN" ]; then
  echo "dashboard_login=FAIL" >&2
  exit 1
fi
COOKIE="Cookie: auth_token=$TOKEN"

nodes=$(curl -fsS -H "$COOKIE" "$BASE_URL/api/provider-nodes")
node_id=$(printf '%s' "$nodes" | python3 -c 'import sys,json; d=json.load(sys.stdin); name=sys.argv[1]; base=sys.argv[2]; xs=d.get("nodes",[]); m=[x for x in xs if x.get("name")==name or x.get("baseUrl")==base]; print(m[0].get("id","") if m else "")' "$NODE_NAME" "$NODE_BASE_URL")

node_payload=$(python3 -c 'import json,sys; print(json.dumps({"name":sys.argv[1],"prefix":sys.argv[2],"apiType":"chat","baseUrl":sys.argv[3],"type":"openai-compatible"}))' "$NODE_NAME" "$NODE_PREFIX" "$NODE_BASE_URL")
if [ -z "$node_id" ]; then
  created=$(curl -fsS -H "$COOKIE" -H 'content-type: application/json' --data-binary "$node_payload" "$BASE_URL/api/provider-nodes")
  node_id=$(printf '%s' "$created" | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("node") or {}).get("id",""))')
else
  curl -fsS -X PUT -H "$COOKIE" -H 'content-type: application/json' --data-binary "$node_payload" "$BASE_URL/api/provider-nodes/$node_id" >/dev/null
fi

if [ -z "$node_id" ]; then
  echo "provider_node=FAIL" >&2
  exit 1
fi

connections=$(curl -fsS -H "$COOKIE" "$BASE_URL/api/providers")
connection_id=$(printf '%s' "$connections" | python3 -c 'import sys,json; d=json.load(sys.stdin); pid=sys.argv[1]; xs=d.get("connections",[]); m=[x for x in xs if x.get("provider")==pid]; print(m[0].get("id","") if m else "")' "$node_id")
if [ -z "$connection_id" ]; then
  connection_payload=$(python3 -c 'import json,sys; print(json.dumps({"provider":sys.argv[1],"apiKey":sys.argv[2],"name":sys.argv[3],"priority":1,"testStatus":"unknown"}))' "$node_id" "$DUMMY_KEY" "$CONNECTION_NAME")
  created_connection=$(curl -fsS -H "$COOKIE" -H 'content-type: application/json' --data-binary "$connection_payload" "$BASE_URL/api/providers")
  connection_id=$(printf '%s' "$created_connection" | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("connection") or {}).get("id",""))')
fi

if [ -z "$connection_id" ]; then
  echo "provider_connection=FAIL" >&2
  exit 1
fi

printf 'provider_node=PASS id=%s prefix=%s apiType=chat\n' "$node_id" "$NODE_PREFIX"
printf 'provider_connection=PASS id=%s\n' "$connection_id"
