# Stage 3 — FastAPI → llm-d (Envoy + EPP) → Simulator pools

A **functional lab**, not a sovereign-AI or regulatory-compliance certification. This stage performs synthetic inference only. Models are simulator labels, not loaded model weights.

## Prerequisites
- Existing namespace `inference`, both router Services `router-fast-epp` and `router-reasoning-epp` serving HTTP on 8081.
- kubectl configured for the k3s cluster; VM can pull `python:3.12-slim` and reach PyPI.
- `openssl` installed for an API key.

## On the VM
```bash
cd ~/sovereign-ai-inference-platform/stage3-compliance-gateway
chmod +x scripts/*.sh
./scripts/deploy.sh
./scripts/test.sh
kubectl logs -n inference deployment/compliance-gateway --tail=30
```

The deploy script creates a random API key in `~/.config/sovereign-ai/gateway-key` (0600) and a Kubernetes Secret, and mounts Python source from a ConfigMap. **Do not commit keys or raw logs.** `test.sh` port-forwards only inside the VM on localhost:18000.

## Simplifications and limitations
- `fast` / `reasoning` are client-provided scenarios checked against a strict allowlist. No semantic classifier is used.
- Model names are fixed by the gateway to the simulator names validated for each router.
- Basic regex redaction recognizes illustrative SSN, email and Emirates ID strings, not comprehensive PII detection.
- JSON audit logs report metadata, not prompt text. They are not durable or tamper-proof.
- Responses are buffered, not streamed; gateway duration is not TTFT.
- The quick deployment installs dependencies at container start. For reproducible production packaging use the provided Dockerfile, build in CI, pin its image digest and replace the image in the Deployment.
