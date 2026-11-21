# 01 — GCP VM and Ubuntu setup

> **Status:** Configuration observed on the working VM. The exact original VM creation command and disk size were not recorded. This guide is a reconstructed fresh-install path, not a verbatim shell history.

## Purpose
Create an inexpensive CPU-only node for the Sovereign AI Inference Platform.

## Recorded environment

| Item | Value |
|---|---|
| Provider | Google Cloud Compute Engine |
| VM name | `sovereign-llm-node` |
| Region / zone | `asia-south1` (Mumbai) / `asia-south1-a` |
| Machine type | `e2-standard-4`: 4 vCPU, 16 GiB RAM |
| OS | Ubuntu 22.04 LTS |
| GPU | None |
| Storage | VM boot disk; no separate model-data disk or PVC |

Create this VM in the Google Cloud Console, choosing an Ubuntu 22.04 image and a boot disk large enough for OS, k3s, large inference container images and downloaded model files. **The exact provisioned disk size still needs confirming.** Keep network access limited; do not expose model, Prometheus or Grafana Services publicly.

## Connect and inspect
Connect through Google Cloud browser SSH, then:

```bash
cat /etc/os-release
uname -m
nproc
free -h
df -h /
lsblk
```

## Basic packages (reconstructed bootstrap)
```bash
sudo apt-get update
sudo apt-get install -y curl git ca-certificates openssl python3
```

These are host tools. **FastAPI, Python 3.12 and vLLM run inside Kubernetes containers**; installing those packages into the host Python is unnecessary.

## Verify
```bash
curl --version
git --version
openssl version
```

## Notes
- The project was deliberately built CPU-first; there is no CUDA or NVIDIA setup.
- VM charges may accrue even if there is no GPU. Stop or delete unused resources deliberately.
- Do not include SSH keys, GCP service-account tokens, kubeconfig or cloud credentials in the repository.

**Next:** [02 — k3s and Helm](02-k3s-kubernetes-helm.md).
