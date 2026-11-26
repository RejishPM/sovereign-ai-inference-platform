#!/usr/bin/env bash
# Read-only verification of the existing CPU inference PoC resource state.
# Does not call model inference, expose API keys, or change cluster resources.
set -euo pipefail
NS=inference
echo "== Kubernetes context =="
kubectl config current-context
echo "== Cluster nodes =="
kubectl get nodes
kubectl get nodes --no-headers | awk 'BEGIN{ok=0} $2=="Ready"{ok++} END{if(ok<1){print "FAIL: No Ready nodes"; exit 1}}'
echo "== CPU deployments =="
for dep in vllm-fast-qwen router-fast-epp router-reasoning-epp compliance-gateway; do
  kubectl -n "$NS" rollout status "deployment/$dep" --timeout=30s
done
echo "== Expected services =="
for svc in vllm-fast-qwen router-fast-epp router-reasoning-epp compliance-gateway; do
  kubectl -n "$NS" get "service/$svc" -o name
done
echo "== InferencePool selectors =="
for pool in router-fast router-reasoning; do
  selector="$(kubectl -n "$NS" get inferencepool "$pool" -o jsonpath='{.spec.selector.matchLabels.app}{.spec.selector.app}')"
  if [[ "$selector" != "vllm-fast-qwen" ]]; then
    echo "FAIL: InferencePool $pool selected [$selector], expected vllm-fast-qwen" >&2
    exit 1
  fi
  echo "PASS: $pool selects real CPU vLLM"
done
echo "RESOURCE CHECK PASSED (not an end-to-end inference test)"
