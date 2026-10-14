#!/usr/bin/env bash
set -euo pipefail

if [ -n "${ROUTER_ENV_FILE:-}" ]; then
  set -a
  . "$ROUTER_ENV_FILE"
  set +a
fi

BASE_URL="${ROUTER_BASE_URL:-http://127.0.0.1:20128}"
PASSWORD="${ROUTER_INITIAL_PASSWORD:-${INITIAL_PASSWORD:-}}"
NODE_PREFIX="${OPENAI_OAUTH_NODE_PREFIX:-cgo}"
MODEL="${OPENAI_OAUTH_CANARY_MODEL:-${NODE_PREFIX}/gpt-5.6-sol}"
CONNECTION_NAME="${OPENAI_OAUTH_CONNECTION_NAME:-ChatGPT OAuth Sidecar}"
EXPECTED="${OPENAI_OAUTH_CANARY_EXPECTED:-AESTC_9ROUTER_OPENAI_OAUTH_OK}"

if [ -z "$PASSWORD" ]; then
  echo "ROUTER_INITIAL_PASSWORD or INITIAL_PASSWORD is required" >&2
  exit 1
fi

headers=$(mktemp)
login_body=$(mktemp)
models_body=$(mktemp)
public_models_body=$(mktemp)
resp_body=$(mktemp)
chat_body=$(mktemp)
key_id=''
TOKEN=''

cleanup() {
  if [ -n "$key_id" ] && [ -n "$TOKEN" ]; then
    curl -fsS -X DELETE -H "Cookie: auth_token=$TOKEN" "$BASE_URL/api/keys/$key_id" >/dev/null 2>&1 || true
  fi
  rm -f "$headers" "$login_body" "$models_body" "$public_models_body" "$resp_body" "$chat_body"
}
trap cleanup EXIT

login_payload=$(python3 -c 'import json,sys; print(json.dumps({"password":sys.argv[1]}))' "$PASSWORD")
curl -fsS -D "$headers" -o "$login_body" -H 'content-type: application/json' --data-binary "$login_payload" "$BASE_URL/api/auth/login"
TOKEN=$(sed -n 's/^set-cookie: auth_token=\([^;]*\).*/\1/ip' "$headers" | head -n1)
[ -n "$TOKEN" ] || { echo 'dashboard_login=FAIL'; exit 1; }
COOKIE="Cookie: auth_token=$TOKEN"

nodes=$(curl -fsS -H "$COOKIE" "$BASE_URL/api/provider-nodes")
node_id=$(printf '%s' "$nodes" | python3 -c 'import sys,json; d=json.load(sys.stdin); prefix=sys.argv[1]; xs=d.get("nodes",[]); m=[x for x in xs if x.get("prefix")==prefix]; print(m[0].get("id","") if m else "")' "$NODE_PREFIX")
[ -n "$node_id" ] || { echo 'provider_node=FAIL'; exit 1; }

connections=$(curl -fsS -H "$COOKIE" "$BASE_URL/api/providers")
connection_id=$(printf '%s' "$connections" | python3 -c 'import sys,json; d=json.load(sys.stdin); pid=sys.argv[1]; name=sys.argv[2]; xs=d.get("connections",[]); m=[x for x in xs if x.get("provider")==pid or x.get("name")==name]; print(m[0].get("id","") if m else "")' "$node_id" "$CONNECTION_NAME")
[ -n "$connection_id" ] || { echo 'provider_connection=FAIL'; exit 1; }

curl -fsS -H "$COOKIE" "$BASE_URL/api/providers/$connection_id/models" -o "$models_body"
python3 - "$models_body" <<'PY'
import json,sys
xs=json.load(open(sys.argv[1])).get('models',[])
print(f'provider_models_status=PASS count={len(xs)}')
for item in xs:
    if isinstance(item,dict) and item.get('id'):
        print('provider_model='+str(item['id']))
PY

canary_name="aestc-openai-oauth-canary-$(date +%s)-$$"
key_payload=$(python3 -c 'import json,sys; print(json.dumps({"name":sys.argv[1]}))' "$canary_name")
key_json=$(curl -fsS -H "$COOKIE" -H 'content-type: application/json' --data-binary "$key_payload" "$BASE_URL/api/keys")
key_id=$(printf '%s' "$key_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
api_key=$(printf '%s' "$key_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("key",""))')
[ -n "$key_id" ] && [ -n "$api_key" ] || { echo 'canary_key=FAIL'; exit 1; }

curl -fsS -H "Authorization: Bearer $api_key" "$BASE_URL/v1/models" -o "$public_models_body"
python3 - "$public_models_body" "$MODEL" "$NODE_PREFIX" <<'PY'
import json,sys
payload=json.load(open(sys.argv[1]))
model=sys.argv[2]
prefix=sys.argv[3]+'/'
ids=[str(x.get('id')) for x in payload.get('data',[]) if isinstance(x,dict) and str(x.get('id','')).startswith(prefix)]
print(f'public_models_status=PASS count={len(ids)}')
for item in ids: print('public_model='+item)
if model not in ids:
    raise SystemExit(f'expected model missing from public catalog: {model}')
PY

resp_payload=$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"input":"Reply exactly "+sys.argv[2],"stream":False}))' "$MODEL" "$EXPECTED")
resp_status=$(curl -sS -o "$resp_body" -w '%{http_code}' -H 'content-type: application/json' -H "Authorization: Bearer $api_key" --data-binary "$resp_payload" "$BASE_URL/v1/responses")
resp_text=$(python3 - "$resp_body" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print(''); raise SystemExit
if isinstance(d.get('output_text'),str): print(d['output_text']); raise SystemExit
parts=[]
for item in d.get('output',[]) or []:
    if not isinstance(item,dict): continue
    for c in item.get('content',[]) or []:
        if isinstance(c,dict) and isinstance(c.get('text'),str): parts.append(c['text'])
print('\n'.join(parts))
PY
)
printf 'responses_status=%s output=%s\n' "$resp_status" "$resp_text"

chat_payload=$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":"Reply exactly "+sys.argv[2]}],"stream":False}))' "$MODEL" "$EXPECTED")
chat_status=$(curl -sS -o "$chat_body" -w '%{http_code}' -H 'content-type: application/json' -H "Authorization: Bearer $api_key" --data-binary "$chat_payload" "$BASE_URL/v1/chat/completions")
chat_text=$(python3 - "$chat_body" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print(''); raise SystemExit
try: print(d['choices'][0]['message']['content'])
except Exception: print('')
PY
)
printf 'chat_status=%s output=%s\n' "$chat_status" "$chat_text"

[ "$resp_status" = "200" ] && [ "$resp_text" = "$EXPECTED" ] || exit 1
[ "$chat_status" = "200" ] && [ "$chat_text" = "$EXPECTED" ] || exit 1
printf 'AESTC_9ROUTER_OPENAI_OAUTH_CANARY_PASS\n'
