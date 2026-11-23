#!/usr/bin/env bash
set -euo pipefail
NS=inference
MODE="$1"
[[ "$MODE" == "--check" || "$MODE" == "--delete-sims" ]] || { echo "Usage: bash scripts/finish-cpu-mvp.sh --check|--delete-sims"; exit 2; }
mkdir -p "$HOME/sovereign-mvp-backup"
chmod 700 "$HOME/sovereign-mvp-backup"
for d in vllm-fast-qwen router-fast-epp router-reasoning-epp compliance-gateway; do
  kubectl -n "$NS" rollout status "deploy/$d" --timeout=90s >/dev/null
  echo "READY $d"
done
for p in router-fast router-reasoning; do
  selector=$(kubectl -n "$NS" get inferencepool "$p" -o jsonpath='{.spec.selector.matchLabels.app}{.spec.selector.app}')
  [[ "$selector" == "vllm-fast-qwen" ]] || { echo "BLOCK: $p selects $selector"; exit 1; }
  echo "PASS $p selects real vLLM"
done
backup="$HOME/sovereign-mvp-backup/simulators-$(date -u +%Y%m%dT%H%M%SZ).yaml"
kubectl -n "$NS" get deployment/sim-fast deployment/sim-reasoning service/sim-fast service/sim-reasoning -o yaml > "$backup"
chmod 600 "$backup"
echo "Backup recorded locally: $backup (restore from source manifests, not this generated YAML)"

# Within gateway container. No secrets or full request bodies printed.
kubectl -n "$NS" exec -i deploy/compliance-gateway -- python - <<'PY'
import os,sys,httpx
sys.path.insert(0,"/src")
from main import ROUTES,redact
model="Qwen/Qwen2.5-0.5B-Instruct"
assert all(ROUTES[s][1]==model for s in ("fast","reasoning")), "Wrong gateway model"
assert redact("demo@example.com")[0]=="[REDACTED_EMAIL]"
key=os.environ.get("GATEWAY_API_KEY")
assert key, "Missing key"
url="http://127.0.0.1:8000/v1/infer"
def send(c,scenario,prompt,auth=key):
 return c.post(url,headers={"X-API-Key":auth,"X-Inference-Scenario":scenario},
  json={"messages":[{"role":"user","content":prompt}],"max_tokens":8})
with httpx.Client(timeout=320,trust_env=False) as c:
 r=send(c,"fast","Say hello.")
 assert r.status_code==200, f"Warmup failed {r.status_code}"
 print("PASS warmup",flush=True)
 for s in ("fast","reasoning"):
  r=send(c,s,"Say hello.")
  assert r.status_code==200 and r.json().get("choices"), f"Failed {s}: {r.status_code}"
  print("PASS gateway scenario",s,flush=True)
 assert send(c,"fast","Hi",auth="invalid-test-key").status_code==401
 print("PASS 401",flush=True)
 assert send(c,"invalid","Hi").status_code==400
 print("PASS 400",flush=True)
 r=send(c,"fast","Synthetic contact demo@example.com")
 assert r.status_code==200 and int(r.headers.get("x-pii-redactions","0"))>=1
 print("PASS synthetic email redaction reported",flush=True)
PY
kubectl -n "$NS" exec deploy/vllm-fast-qwen -- python - <<'PY'
import urllib.request,re
metrics=urllib.request.urlopen("http://127.0.0.1:8000/metrics",timeout=15).read().decode()
names=set(re.findall(r'(?m)^([A-Za-z_:][A-Za-z0-9_:]*request_success[A-Za-z0-9_:]*)',metrics))
assert names, "No request-success metric exposed"
print("PASS vLLM success metric present",",".join(sorted(names)))
PY

refs=$(mktemp)
trap 'rm -f "$refs"' EXIT
kubectl -n "$NS" get inferencepool,httproute,configmap -o yaml | grep -nE 'sim-(fast|reasoning)' > "$refs" || true
kubectl -n "$NS" get deployment/compliance-gateway -o yaml | grep -nE 'sim-(fast|reasoning)' >> "$refs" || true
if kubectl api-resources -o name | grep -qx 'podmonitors.monitoring.coreos.com'; then
  kubectl -n "$NS" get podmonitor,servicemonitor -o yaml | grep -nE 'sim-(fast|reasoning)' >> "$refs" || true
fi
if [[ -s "$refs" ]]; then
  echo "BLOCK: active configuration still references simulators:"
  cat "$refs"
  exit 1
fi
echo "PASS no simulator references found in checked configurations"
if [[ "$MODE" == "--check" ]]; then
  echo "CHECK PASSED (no deletion). Validate Prometheus target UP and metric query before cleanup."
  exit 0
fi
echo "DELETE ONLY: inference deployments/sim-fast,sim-reasoning and services/sim-fast,sim-reasoning"
read -r -p "Type DELETE-SIMS to proceed: " answer
[[ "$answer" == "DELETE-SIMS" ]] || { echo "Cancelled"; exit 1; }
kubectl -n "$NS" delete deployment/sim-fast deployment/sim-reasoning service/sim-fast service/sim-reasoning --wait=true
kubectl -n "$NS" get pods,svc,inferencepool
