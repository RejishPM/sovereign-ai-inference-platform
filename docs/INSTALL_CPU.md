# Installation and verification guide (CPU inference PoC)

> **Status:** The existing GCP k3s installation passed functional acceptance testing in November 2026. A **fresh VM installation from this repository has NOT yet been independently reproduced**. Do not describe the repository as a one-command clean install.
>
> **GPU:** Not required for this guide. Multi-GPU, cache-aware endpoint selection and GPU performance are **not** demonstrated.

## 0. What you are installing

```text
Client -> FastAPI compliance-gateway -> llm-d/Envoy fast or reasoning router
                                         -> ONE real CPU vLLM Qwen replica
Prometheus PodMonitor -> vLLM /metrics; optional Grafana dashboard
```

Both scenarios use the *same* real model `Qwen/Qwen2.5-0.5B-Instruct`. The original simulation manifests are included for reference but are not required for the real-CPU inference route. The repository's reasoning router values now select `app: vllm-fast-qwen`.

This is a **demonstration** of model serving, gateway policy checks and actual llm-d request forwarding—not proof of cache-aware scheduling among replicas, production compliance or improved latency.

## 1. VM sizing and prerequisites

Validated baseline infrastructure (historical, not a guaranteed minimum):

- Ubuntu 22.04 LTS, x86_64 VM, 4 vCPU / 16 GiB RAM, 50 GiB disk.
- k3s server, with default Traefik disabled in the original deployment; local `kubectl` and `helm`.
- Kubernetes `inference` and `monitoring` namespaces.
- k3s/Kubernetes version last observed: `v1.37.2+k3s1` (verify compatibility for your own installation).
- CPU vLLM image currently referenced: `vllm/vllm-openai-cpu:v0.33.0-x86_64` (tag, **not digest pinned**).
- Qwen `Qwen/Qwen2.5-0.5B-Instruct`, model revision **not pinned**.
- llm-d standalone chart historically installed from `oci://ghcr.io/llm-d/charts/llm-d-router-standalone`, chart version `v0`. Chart version and deployment-time CRD version must be verified against installed releases and upstream documentation; this is **not a known-stable reproducible version pin**.
- Gateway uses `python:3.12-slim` and installs Python requirements at startup, so external package network access is needed.

**Network/access:** Model weights, container images, chart registries and Python packages must be reachable. Have enough free memory/disk for model loading. Don't publicly expose the gateway or Kubernetes API; use private access and SSH tunneling.

## 2. Choose one setup path

### Path A — Existing working k3s VM (historically tested)

On your VM, in a terminal with working Kubernetes context:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
helm list -A
kubectl get inferencepools -n inference
kubectl get runtimeclass
free -h
df -h
```

Stop if the Kubernetes context is wrong, node not `Ready`, resources insufficient, or an unexpected release is installed. **Do not reinstall k3s/Helm or overwrite running routers.**

Clone or fast-forward the repository:

```bash
git clone https://github.com/RejishPM/sovereign-ai-inference-platform.git
cd sovereign-ai-inference-platform
# For an existing clone, use: git pull --ff-only
```

**Note:** Repository visibility/authentication must permit cloning. For a private repo use authorized GitHub credentials; no token in commands or logs.

Run the safe, read-only resource smoke check:

```bash
bash scripts/verify-cpu-platform.sh
```

This check confirms Kubernetes resource presence/health **without sending inference requests**, changing deployments or removing simulator resources. A passing check alone **does not prove** real inference.

### Path B — New Ubuntu VM (installation steps; NOT end-to-end verified)

Use a dedicated VM and budget authorization before creating any paid instance. Install k3s and Helm using their official maintained installation instructions, with versions compatible with your chosen llm-d/GAIE release. See:

- k3s installation: https://docs.k3s.io/quick-start
- k3s advanced/container runtime guidance: https://docs.k3s.io/advanced
- Helm installation: https://helm.sh/docs/intro/install/
- Gateway API release/CRDs: https://gateway-api.sigs.k8s.io/guides/
- Inference Extension (GAIE) CRDs: https://gateway-api-inference-extension.sigs.k8s.io/
- llm-d router and chart: https://github.com/llm-d/llm-d and https://github.com/llm-d/llm-d-infra

**Stop gate — versions required:** Record the exact k3s server version, Helm version, Gateway API CRD release, GAIE CRD release, llm-d chart version **and its values schema**, image digests, Qwen model revision in `docs/VERSIONS.md` or your deployment notes. Do not paste arbitrary "latest" CRD URLs or charts. Inspect `helm show values` on the pinned chart and validate `router-*-values.yaml` against it before installation. Current repository alone does **not** contain enough proven version pins to promise a from-zero repeatable llm-d installation.

Once the prerequisite components are installed and validated, use the following **conditional** commands; do not apply them before the version gate.

```bash
kubectl create namespace inference --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f deploy/k8s/vllm-fast-qwen.yaml
kubectl -n inference rollout status deployment/vllm-fast-qwen --timeout=900s
kubectl -n inference get pods,svc -l app=vllm-fast-qwen
```

CPU model downloading and warming can take several minutes. If the pod is not Ready, stop and inspect `kubectl -n inference describe pod -l app=vllm-fast-qwen` and `kubectl -n inference logs deployment/vllm-fast-qwen --tail=80`. Do not proceed while it is failing.

**llm-d router installation:** This is the main unresolved fresh-install step. After confirming the current official chart schema and CRD compatibility, install **two** standalone router releases in `inference` with the checked-in values, `router-fast-real-values.yaml` and `router-reasoning-values.yaml`. Historical release names are `router-fast` and `router-reasoning`. Do **not** blindly run `helm upgrade --install` with the historically observed `v0` chart: a successful historical configuration is not a proven clean-install procedure. Record the tested exact command and pinned version once independently reproduced.

Confirm the router Services and InferencePools actually exist, and that **both** selectors target the real CPU backend:

```bash
kubectl -n inference get deployments,services,inferencepools
kubectl -n inference get inferencepool router-fast -o yaml
kubectl -n inference get inferencepool router-reasoning -o yaml
```

Both InferencePools must select `app: vllm-fast-qwen`; ensure `router-fast-epp` and `router-reasoning-epp` Services exist before deploying the gateway.

### Deploy gateway (after both routers are ready)

```bash
bash stage3-compliance-gateway/scripts/deploy.sh
kubectl -n inference rollout status deployment/compliance-gateway --timeout=240s
```

The script checks for both router Services, creates a random API-key Secret if one does not exist, creates/updates a ConfigMap from the gateway code, and applies/restarts the gateway. **It mutates the live cluster; review it before running.** It does not print the key. If credentials are present in Kubernetes but the local key file is missing, do not overwrite the Secret—recover/update credentials through an approved procedure.

### Monitoring (optional after serving works)

The repo provides `monitoring-values.yaml`, `vllm-podmonitor.yaml` and `dashboards/vllm-cpu.json`. An already-installed `kube-prometheus-stack` release was historically named `kube-prom` in `monitoring`. **The exact chart version/install command is not recorded here; verify a supported chart and its CRDs first.** Once the Prometheus Operator PodMonitor CRD exists:

```bash
kubectl api-resources | grep -i podmonitors
kubectl apply -f vllm-podmonitor.yaml
kubectl -n monitoring get podmonitor vllm-cpu
```

In Prometheus, verify the actual vLLM target is UP and an instant query returns real samples. Merely seeing `/metrics` or imported dashboard JSON isn't proof of a valid dashboard.

## 3. Functional verification on a deployed cluster

First:

```bash
bash scripts/verify-cpu-platform.sh
```

Then run the **existing acceptance test** (makes real inference calls; can take minutes on CPU):

```bash
bash scripts/finish-cpu-mvp.sh --check
```

This check requires the named simulator objects to exist because it backs them up before testing. **If simulators have already been removed, the script fails before tests; this is a known test-script limitation, not necessarily an inference failure.** Do not reinstall simulation backends just to satisfy a test gate.

Acceptance evidence from the historical deployment (2026-11-23):

| Check | Observed outcome |
| --- | --- |
| vLLM, two router deployments, gateway | Ready |
| Both InferencePool selectors | `app: vllm-fast-qwen` |
| Fast route | HTTP 200 real Qwen response |
| Reasoning route | HTTP 200 real Qwen response |
| vLLM success counter | Increased after real gateway requests |
| Invalid API key | HTTP 401 |
| Unsupported scenario | HTTP 400 |
| Synthetic email input | Redaction reported |
| Prometheus scrape | vLLM target UP; metric names discovered |

**Evidence boundary:** These observations confirm the existing deployment, not a new reader's fresh clone. Screenshots/outputs are not included as complete raw test artifacts. The historical success does not establish GPU scheduling, load-aware multi-replica benefits, prefix-cache locality routing, or production sovereignty.

## 4. Troubleshooting

```bash
kubectl -n inference get pods,svc,inferencepools -o wide
kubectl -n inference describe deploy vllm-fast-qwen
kubectl -n inference logs deployment/vllm-fast-qwen --tail=80
kubectl -n inference logs deployment/compliance-gateway --tail=80
helm list -A
```

- **vLLM startup timeout:** allow model download and loading; inspect resource pressure and logs before modifying timeouts.
- **Router returns 503/timeout:** check EPP and Envoy container status, Service ports, Pod and InferencePool label selectors. Check the official llm-d chart for the installed version.
- **Gateway HTTP 401:** requires the `X-API-Key` matching Kubernetes Secret `gateway-secrets`. Never print a live key in evidence.
- **Gateway HTTP 400:** `X-Inference-Scenario` must be `fast` or `reasoning`.
- **PodMonitor missing:** Prometheus Operator CRDs are not installed or the monitoring release differs.
- **OOMEviction / OOMKilled:** check memory/CPU limits and actual VM capacity; CPU vLLM needs significant memory.
- **Gateway startup requires internet:** the PoC gateway installs Python packages at startup; build an offline/pinned image before any air-gapped deployment.

## 5. Do not destroy existing workloads

Do **not** run `scripts/finish-cpu-mvp.sh --delete-sims` as part of installation. It deletes simulator Deployments and Services, and must be treated as a separate approved maintenance action. Do not delete Kubernetes namespaces or the VM during verification.

## 6. Evidence to save for reproducibility

On **your own VM**, save sanitized text logs in a local evidence directory; review them before committing:

```bash
mkdir -p evidence-local
kubectl version > evidence-local/kubernetes-version.txt
kubectl get nodes -o wide > evidence-local/nodes.txt
helm list -A > evidence-local/helm-releases.txt
bash scripts/verify-cpu-platform.sh > evidence-local/resource-check.txt 2>&1
# Run acceptance explicitly, only if simulator objects exist:
# bash scripts/finish-cpu-mvp.sh --check > evidence-local/acceptance.txt 2>&1
```

Do **not** commit `evidence-local/` blindly; it can contain internal node names, IPs, config or sensitive operational metadata. Never publish API keys, k3s join tokens or billing identifiers.

### What still needs independent confirmation

- Full first-time k3s/Helm/GAIE/llm-d/monitoring install on a clean VM.
- Pinned image and Helm digests, compatible exact CRD versions, pinned model revision.
- Independent copy-and-run acceptance and sanitized logs from a clean clone.

Until these are completed, call the repository a **working, historically validated CPU inference PoC with partial setup documentation**, not a universally verified turnkey installer.
