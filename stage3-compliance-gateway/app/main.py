"""Stage 3 CPU-lab gateway. Demonstrates policy checks, not regulatory compliance."""
import hmac
import json
import logging
import os
import re
import time
import uuid
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException, Request, Response

logging.basicConfig(level=logging.INFO, format='%(message)s')
audit = logging.getLogger('gateway.audit')
app = FastAPI(title='Sovereign AI Inference Gateway (PoC)', version='0.2.0')
ROUTES = {
    'fast': (os.getenv('ROUTER_FAST_URL', 'http://router-fast-epp.inference.svc.cluster.local:8081'), 'Qwen/Qwen2.5-0.5B-Instruct'),
    'reasoning': (os.getenv('ROUTER_REASONING_URL', 'http://router-reasoning-epp.inference.svc.cluster.local:8081'), 'Qwen2.5-0.5B'),
}
PATTERNS = [
    (re.compile(r'\b\d{3}-\d{2}-\d{4}\b'), '[REDACTED_SSN]'),
    (re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'), '[REDACTED_EMAIL]'),
    (re.compile(r'\b784-\d{4}-\d{7}-\d\b'), '[REDACTED_EMIRATES_ID]'),
]

def redact(value: Any) -> tuple[Any, int]:
    if isinstance(value, str):
        count = 0
        for pattern, label in PATTERNS:
            value, n = pattern.subn(label, value)
            count += n
        return value, count
    if isinstance(value, list):
        out, count = [], 0
        for item in value:
            clean, n = redact(item)
            out.append(clean)
            count += n
        return out, count
    if isinstance(value, dict):
        out, count = {}, 0
        for key, item in value.items():
            clean, n = redact(item)
            out[key] = clean
            count += n
        return out, count
    return value, 0

def log_event(request_id: str, decision: str, status: int, scenario: str, **fields: Any) -> None:
    audit.info(json.dumps({'kind':'gateway_audit','request_id':request_id,'decision':decision,'status':status,'scenario':scenario,**fields}, separators=(',', ':')))

@app.get('/healthz')
async def healthz():
    return {'status':'ok'}

@app.post('/v1/infer')
async def infer(request: Request,
                x_api_key: str | None = Header(None),
                x_inference_scenario: str = Header('fast')):
    request_id = str(uuid.uuid4())
    scenario = x_inference_scenario.strip().lower()
    configured_key = os.environ.get('GATEWAY_API_KEY', '')
    if not configured_key or not x_api_key or not hmac.compare_digest(x_api_key, configured_key):
        log_event(request_id, 'DENY_CREDENTIALS', 401, scenario)
        raise HTTPException(401, 'Invalid credentials')
    if scenario not in ROUTES:
        log_event(request_id, 'DENY_SCENARIO', 400, scenario)
        raise HTTPException(400, 'Unsupported inference scenario')
    if int(request.headers.get('content-length', '0') or '0') > 32768:
        raise HTTPException(413, 'Request too large')
    raw = await request.body()
    if len(raw) > 32768:
        raise HTTPException(413, 'Request too large')
    try:
        body = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise HTTPException(400, 'Invalid JSON')
    if not isinstance(body, dict) or not isinstance(body.get('messages'), list) or not body['messages']:
        raise HTTPException(422, 'messages must be a nonempty list')
    if any(not isinstance(m, dict) or not isinstance(m.get('content'), str) or m.get('role') not in {'system','user','assistant'} for m in body['messages']):
        raise HTTPException(422, 'Invalid chat message')
    max_tokens = body.get('max_tokens', 32)
    if type(max_tokens) is not int or not 1 <= max_tokens <= 128:
        raise HTTPException(422, 'max_tokens must be between 1 and 128')
    target, model = ROUTES[scenario]
    clean_messages, pii_count = redact(body['messages'])
    payload = {'model':model, 'messages':clean_messages, 'max_tokens':max_tokens}
    started = time.perf_counter()
    try:
        async with httpx.AsyncClient(timeout=180.0, trust_env=False) as client:
            upstream = await client.post(target + '/v1/chat/completions', json=payload, headers={'X-Request-ID':request_id})
    except httpx.RequestError:
        log_event(request_id, 'UPSTREAM_ERROR', 502, scenario, pii_redactions=pii_count)
        raise HTTPException(502, 'Inference router unavailable')
    elapsed = round((time.perf_counter()-started)*1000)
    pod = upstream.headers.get('x-inference-pod', 'unknown')
    decision = 'ALLOW' if 200 <= upstream.status_code < 300 else 'UPSTREAM_ERROR'
    log_event(request_id, decision, upstream.status_code, scenario, selected_pod=pod, pii_redactions=pii_count, duration_ms=elapsed)
    return Response(content=upstream.content,
                    status_code=upstream.status_code,
                    media_type='application/json',
                    headers={'X-Request-ID':request_id,'X-Inference-Scenario':scenario,
                             'X-Inference-Pod':pod,'X-PII-Redactions':str(pii_count)})
