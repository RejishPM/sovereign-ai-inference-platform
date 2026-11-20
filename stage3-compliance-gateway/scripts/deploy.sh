#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl get namespace inference >/dev/null
kubectl get service router-fast-epp router-reasoning-epp -n inference >/dev/null
# Secret is created once, never printed, never committed.
if ! kubectl get secret gateway-secrets -n inference >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/sovereign-ai"
  umask 077
  if [ ! -f "$HOME/.config/sovereign-ai/gateway-key" ]; then
    openssl rand -hex 24 > "$HOME/.config/sovereign-ai/gateway-key"
  fi
  kubectl create secret generic gateway-secrets -n inference \
    --from-literal="GATEWAY_API_KEY=$(cat "$HOME/.config/sovereign-ai/gateway-key")"
fi
kubectl create configmap compliance-gateway-code -n inference \
  --from-file=main.py=app/main.py --from-file=requirements.txt \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/gateway.yaml
kubectl rollout restart deployment/compliance-gateway -n inference
kubectl rollout status deployment/compliance-gateway -n inference --timeout=240s
kubectl get pods,svc -n inference -l app=compliance-gateway
