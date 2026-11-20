# Sovereign AI Inference Platform

A CPU-first proof of concept for enterprise LLM inference routing,
policy enforcement, Kubernetes deployment, and observability.

## Architecture

Client
  |
  v
FastAPI Compliance Gateway
  |-- API key authentication
  |-- Scenario validation
  |-- Pattern-based PII redaction
  |
  +--> fast --> llm-d / Envoy --> vLLM CPU
  |                            Qwen2.5-0.5B-Instruct
  |
  +--> reasoning --> llm-d / Envoy --> Simulator pool

Observability: Prometheus + Grafana

## Technology Stack

- Google Cloud Compute Engine
- k3s / Kubernetes
- Helm
- vLLM CPU
- Qwen2.5-0.5B-Instruct
- llm-d standalone router and Envoy
- FastAPI / Python
- Prometheus / Grafana

## Demonstrated Functionality

- Two independent inference routing scenarios
- Real CPU-based Qwen text generation
- Real model invocation through llm-d and Envoy
- FastAPI single-entry gateway
- API-key authentication and scenario validation
- Pattern-based PII redaction
- Kubernetes health and readiness checks
- Prometheus scraping of live vLLM metrics
- Grafana dashboard provisioning

## Validation Evidence

Functional tests completed:

- Fast scenario: HTTP 200
- Reasoning scenario: HTTP 200
- Invalid API key: HTTP 401
- Invalid scenario: HTTP 400
- Synthetic PII test: 2 redactions
- Direct Qwen inference: successful
- llm-d-to-Qwen inference: successful
- Prometheus vLLM scrape target: up = 1

## Observability

The Grafana dashboard includes:

- Generated tokens per second
- Prompt tokens per second
- KV-cache utilization
- P95 time to first token

Dashboard: dashboards/vllm-cpu.json

## Deployment Components

- deploy/k8s/: Model deployments and simulator pools
- router-*-values.yaml: llm-d Helm configurations
- stage3-compliance-gateway/: FastAPI gateway
- monitoring-values.yaml: Monitoring Helm configuration
- vllm-podmonitor.yaml: Prometheus scrape configuration
- dashboards/: Grafana dashboard definitions

## Important Limitations

This is an engineering proof of concept, not a production-certified
sovereign or regulatory-compliant platform.

- The real model runs on CPU, not GPU.
- The reasoning backend currently uses a simulator.
- No production load benchmark has been performed.
- Authentication and PII redaction are demonstration controls.
- Regulatory compliance and data residency have not been certified.
- GPU autoscaling, distributed prefill/decode, and advanced
  KV-cache-aware scheduling have not been validated.

## Development Approach

The platform was built CPU-first to validate deployment,
routing, integration and observability while controlling
infrastructure costs.

GPU deployment, more advanced inference scheduling,
security hardening and performance evaluation are future work.
