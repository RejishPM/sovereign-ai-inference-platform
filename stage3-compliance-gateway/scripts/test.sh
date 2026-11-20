#!/usr/bin/env bash
set -euo pipefail
KEY_FILE="$HOME/.config/sovereign-ai/gateway-key"
if [ ! -f "$KEY_FILE" ]; then echo 'Missing locally stored test key; retrieve it securely from your secret-management workflow.' >&2; exit 1; fi
KEY=$(cat "$KEY_FILE")
PORT=18000
kubectl -n inference port-forward svc/compliance-gateway "$PORT:8000" >/tmp/sovereign-gateway-portforward.log 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break; sleep 1; done
for SCENARIO in fast reasoning; do
  echo "=== $SCENARIO ==="
  curl -si --max-time 70 "http://127.0.0.1:$PORT/v1/infer" \
    -H "X-API-Key: $KEY" -H "X-Inference-Scenario: $SCENARIO" \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Explain Kubernetes in one sentence."}],"max_tokens":32}' \
    | grep -Ei '^HTTP/|^x-inference-scenario:|^x-inference-pod:|^x-pii-redactions:'
done
echo '=== Unauthorized (expect 401) ==='
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$PORT/v1/infer" -H 'X-API-Key: wrong' -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"Hi"}]}'
echo '=== Invalid scenario (expect 400) ==='
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$PORT/v1/infer" -H "X-API-Key: $KEY" -H 'X-Inference-Scenario: unknown' -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"Hi"}]}'
echo '=== Synthetic PII (expect 2 redactions) ==='
curl -si "http://127.0.0.1:$PORT/v1/infer" -H "X-API-Key: $KEY" -H 'X-Inference-Scenario: fast' -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"alice@example.com and 123-45-6789"}]}' | grep -Ei '^HTTP/|^x-pii-redactions:'
