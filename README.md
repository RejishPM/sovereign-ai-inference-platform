# Sovereign AI Inference Platform

CPU-first engineering proof of concept for private LLM serving, scenario routing, gateway policy checks, Kubernetes, and observability. **GPU multi-replica intelligent routing is the next milestone, not yet implemented.**

## Verified CPU architecture

```text
Client
  |
  v
FastAPI Compliance Gateway (API-key check, scenario validation, regex PII redaction)
  |                          |
  | fast                     | reasoning
  v                          v
llm-d / Envoy fast          llm-d / Envoy reasoning
  |                          |
  +------------+-------------+
               v
         vLLM CPU (one replica)
         Qwen/Qwen2.5-0.5B-Instruct

Prometheus scrapes vLLM; Grafana dashboard configuration is included.
```

Both scenarios intentionally route to the **same single real CPU Qwen model**. This validates scenario-based gateway routing and llm-d/Envoy forwarding, **not** inference-aware selection among multiple replicas. The simulator deployments remain in the current cluster until cleanup has been separately approved and performed.

## Stack

- GCP Compute Engine VM, k3s, Helm
- vLLM CPU image with Qwen2.5-0.5B-Instruct
- llm-d standalone Endpoint Picker and Envoy
- FastAPI compliance gateway
- Prometheus / Grafana

## Evidence from November 23, 2026

The following observations were reported from the running GCP deployment:

- Both llm-d router endpoints individually returned **HTTP 200** with genuine Qwen output.
- Gateway `fast` and `reasoning` scenarios each returned **HTTP 200**.
- Both InferencePool selectors matched `app: vllm-fast-qwen` during acceptance testing.
- The real vLLM `request_success` counter increased by at least two across the two gateway scenario requests.
- Invalid gateway API key returned **HTTP 401**; invalid scenario returned **HTTP 400**.
- Synthetic email input was reported as redacted by gateway; no comprehensive PII leakage assessment was conducted.
- Prometheus vLLM target `monitoring/vllm-cpu` showed **UP**, and vLLM metric names were discovered.
- `scripts/finish-cpu-mvp.sh --check` completed successfully **without deleting simulators**.

These are functional acceptance results, not comparative performance results or production certification. Prometheus instant-query and Grafana dashboard values should be captured as separate final evidence if not already recorded.

## Installation and reproducibility

**[CPU VM installation and validation guide](docs/INSTALL_CPU.md)** — includes environment prerequisites, an existing-cluster workflow, a conditional fresh-VM workflow, verification commands and evidence boundaries. A fresh installation from scratch has **not yet** been independently reproduced; chart/CRD compatibility and exact version pins remain to be verified.

For an existing deployment, the read-only health check is:

```bash
bash scripts/verify-cpu-platform.sh
```

It checks Kubernetes resource health and pool selectors but does **not** establish end-to-end inference success. The full acceptance script is documented in the guide.

## Repository layout

- `deploy/k8s/vllm-fast-qwen.yaml` — actual CPU serving Deployment and Service
- `deploy/k8s/model-pools-reviewed.yaml` — original simulator manifests, retained for rollback/reference; **not part of the desired final production deployment**
- `router-fast-real-values.yaml` — fast llm-d route to real Qwen
- `router-reasoning-values.yaml` — reasoning llm-d route to real Qwen
- `stage3-compliance-gateway/` — gateway implementation, deployment and scripts
- `monitoring-values.yaml` and `vllm-podmonitor.yaml` — monitoring
- `dashboards/vllm-cpu.json` — Grafana dashboard definition
- `scripts/finish-cpu-mvp.sh` — guarded functional checks and optional simulator cleanup

## Deployment and acceptance

Reuse existing infrastructure; verify Kubernetes readiness and installed Helm releases before applying any change. After syncing the repository and reviewing the changes:

```bash
bash stage3-compliance-gateway/scripts/deploy.sh
kubectl -n inference rollout status deploy/compliance-gateway --timeout=240s
bash scripts/finish-cpu-mvp.sh --check
```

The check performs warmup and real inference calls and may take several minutes on CPU. It checks both InferencePool selectors, model responses, success-counter increments, negative gateway cases, and reported synthetic email redaction. It also records simulator objects as diagnostic YAML under the VM user's home directory. The backup contains Kubernetes-generated metadata and should **not** be treated as a directly re-applicable rollback. The original simulator manifests in `deploy/k8s/model-pools-reviewed.yaml` are the source reference for recovery.

**Do not run** `--delete-sims` unless the check passes, monitoring is validated, no active dependencies reference simulators, and the deletion is explicitly reviewed. The deletion mode prompts for typed confirmation and names only the simulator Deployments and Services in the `inference` namespace.

Never publish credentials, keys, raw sensitive prompts, internal IPs, usernames, or hostnames.

## Known limitations

- Single CPU vLLM replica shared by both gateway scenarios; **no two-GPU deployment yet**.
- No evidence yet of multi-replica KV/prefix-cache-aware load-balancing improvements, GPU autoscaling, or prefill/decode disaggregation.
- Gateway authentication and pattern-based redaction are demonstration controls, not comprehensive security guarantees.
- Not regulatory-certified, air-gapped, or production sovereign-ready.
- The simulator resources may still be present until the dedicated cleanup step is executed and verified.
- No production load or A/B benchmark has been completed in this Kubernetes environment.

## Next milestone — real GPU smart routing

1. Confirm GCP GPU quota, billing eligibility, and suitable GPU machine capacity.
2. Prepare two identical GPU vLLM replicas with the same model and serving configuration.
3. Use llm-d Endpoint Picker to route among both replicas and record endpoint selection under real traffic.
4. Compare **A: two replicas behind a standard Kubernetes Service** with **B: the same two replicas behind llm-d** on equivalent hardware and workload.
5. Observe actual prefix-cache reuse, KV-cache and queue metrics, and record outcomes and limitations. Publish GPU results only after verifying them.
