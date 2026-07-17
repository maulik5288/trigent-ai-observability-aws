#!/bin/bash
# ============================================================================
# AI Observability Stack - first boot provisioning
# Langfuse v3 + ClickHouse + Postgres + Redis + MinIO + Grafana + Eval hooks
# All secrets are generated at boot (AWS Marketplace: no hardcoded secrets).
# ============================================================================
set -euxo pipefail
exec > /var/log/ai-observability-bootstrap.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y docker.io docker-compose-v2 openssl curl python3
systemctl enable --now docker

APP=/opt/ai-observability
mkdir -p "$APP"/grafana/provisioning/datasources \
         "$APP"/grafana/provisioning/dashboards \
         "$APP"/grafana/dashboards \
         "$APP"/eval-hooks \
         "$APP"/state
cd "$APP"

# ----------------------------------------------------------------------------
# Public IP via IMDSv2 (for NEXTAUTH_URL)
# ----------------------------------------------------------------------------
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# ----------------------------------------------------------------------------
# Generate all secrets at boot
# ----------------------------------------------------------------------------
POSTGRES_PASSWORD=$(openssl rand -hex 16)
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
GRAFANA_PASSWORD=$(openssl rand -hex 12)
NEXTAUTH_SECRET=$(openssl rand -base64 32)
SALT=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)
ADMIN_EMAIL="admin@example.com"
ADMIN_PASSWORD=$(openssl rand -hex 10)
LANGFUSE_PUBLIC_KEY="pk-lf-$(openssl rand -hex 12)"
LANGFUSE_SECRET_KEY="sk-lf-$(openssl rand -hex 12)"

cat > .env <<EOF
PUBLIC_IP=${PUBLIC_IP}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
SALT=${SALT}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
LANGFUSE_PUBLIC_KEY=${LANGFUSE_PUBLIC_KEY}
LANGFUSE_SECRET_KEY=${LANGFUSE_SECRET_KEY}
EOF
chmod 600 .env

cat > credentials.txt <<EOF
==============================================================
 AI Observability Stack - generated credentials
==============================================================
Langfuse UI ........ http://${PUBLIC_IP}:3000
  login email ...... ${ADMIN_EMAIL}
  login password ... ${ADMIN_PASSWORD}

Langfuse API keys (project: default-project)
  public key ....... ${LANGFUSE_PUBLIC_KEY}
  secret key ....... ${LANGFUSE_SECRET_KEY}

Grafana ............ http://${PUBLIC_IP}:3001
  user ............. admin
  password ......... ${GRAFANA_PASSWORD}
==============================================================
EOF
chmod 600 credentials.txt

# ----------------------------------------------------------------------------
# Docker Compose - the full stack
# ----------------------------------------------------------------------------
cat > docker-compose.yml <<'EOF'
x-langfuse-env: &langfuse-env
  DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
  SALT: ${SALT}
  ENCRYPTION_KEY: ${ENCRYPTION_KEY}
  NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
  NEXTAUTH_URL: http://${PUBLIC_IP}:3000
  TELEMETRY_ENABLED: "false"
  CLICKHOUSE_MIGRATION_URL: clickhouse://clickhouse:9000
  CLICKHOUSE_URL: http://clickhouse:8123
  CLICKHOUSE_USER: clickhouse
  CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
  CLICKHOUSE_CLUSTER_ENABLED: "false"
  LANGFUSE_S3_EVENT_UPLOAD_BUCKET: langfuse
  LANGFUSE_S3_EVENT_UPLOAD_REGION: auto
  LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID: minio
  LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY: ${MINIO_ROOT_PASSWORD}
  LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT: http://minio:9000
  LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE: "true"
  REDIS_HOST: redis
  REDIS_PORT: "6379"
  REDIS_AUTH: ${REDIS_PASSWORD}
  # Headless init: org/project/user/API keys created on first start
  LANGFUSE_INIT_ORG_ID: default-org
  LANGFUSE_INIT_ORG_NAME: Default Org
  LANGFUSE_INIT_PROJECT_ID: default-project
  LANGFUSE_INIT_PROJECT_NAME: Default Project
  LANGFUSE_INIT_PROJECT_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY}
  LANGFUSE_INIT_PROJECT_SECRET_KEY: ${LANGFUSE_SECRET_KEY}
  LANGFUSE_INIT_USER_EMAIL: ${ADMIN_EMAIL}
  LANGFUSE_INIT_USER_NAME: Admin
  LANGFUSE_INIT_USER_PASSWORD: ${ADMIN_PASSWORD}

services:
  langfuse-web:
    image: langfuse/langfuse:3
    restart: always
    depends_on:
      postgres: { condition: service_healthy }
      clickhouse: { condition: service_healthy }
      redis: { condition: service_started }
      minio: { condition: service_started }
    ports:
      - "3000:3000"
    environment:
      <<: *langfuse-env

  langfuse-worker:
    image: langfuse/langfuse-worker:3
    restart: always
    depends_on:
      postgres: { condition: service_healthy }
      clickhouse: { condition: service_healthy }
      redis: { condition: service_started }
      minio: { condition: service_started }
    environment:
      <<: *langfuse-env

  postgres:
    image: postgres:16-alpine
    restart: always
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 20

  clickhouse:
    image: clickhouse/clickhouse-server:24.8
    restart: always
    user: "101:101"
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: clickhouse
      CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
    volumes:
      - clickhouse-data:/var/lib/clickhouse
      - clickhouse-logs:/var/log/clickhouse-server
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    healthcheck:
      test: ["CMD-SHELL", "clickhouse-client --user clickhouse --password $${CLICKHOUSE_PASSWORD} --query 'SELECT 1'"]
      interval: 5s
      timeout: 5s
      retries: 20

  redis:
    image: redis:7-alpine
    restart: always
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - redis-data:/data

  minio:
    image: minio/minio:latest
    restart: always
    entrypoint: sh
    command: -c 'mkdir -p /data/langfuse && minio server --address ":9000" --console-address ":9001" /data'
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - minio-data:/data

  grafana:
    image: grafana/grafana:11.2.0
    restart: always
    depends_on:
      clickhouse: { condition: service_healthy }
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
      GF_INSTALL_PLUGINS: grafana-clickhouse-datasource
      GF_USERS_ALLOW_SIGN_UP: "false"
      CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
      - grafana-data:/var/lib/grafana

  eval-worker:
    build: ./eval-hooks
    restart: always
    depends_on:
      - langfuse-web
    environment:
      LANGFUSE_HOST: http://langfuse-web:3000
      LANGFUSE_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY}
      LANGFUSE_SECRET_KEY: ${LANGFUSE_SECRET_KEY}
      POLL_INTERVAL_SECONDS: "60"
    volumes:
      - ./state:/state

volumes:
  postgres-data:
  clickhouse-data:
  clickhouse-logs:
  redis-data:
  minio-data:
  grafana-data:
EOF

# ----------------------------------------------------------------------------
# Grafana provisioning: ClickHouse datasource pointed at Langfuse analytics DB
# ----------------------------------------------------------------------------
cat > grafana/provisioning/datasources/clickhouse.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Langfuse-ClickHouse
    type: grafana-clickhouse-datasource
    uid: langfuse-ch
    isDefault: true
    jsonData:
      host: clickhouse
      port: 9000
      protocol: native
      username: clickhouse
      defaultDatabase: default
    secureJsonData:
      password: ${CLICKHOUSE_PASSWORD}
EOF

cat > grafana/provisioning/dashboards/dashboards.yml <<'EOF'
apiVersion: 1
providers:
  - name: ai-observability
    folder: LLM Observability
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

# ----------------------------------------------------------------------------
# The differentiator #1: pre-canned LLM cost dashboard
# Queries Langfuse's ClickHouse "observations" table directly.
# ----------------------------------------------------------------------------
cat > grafana/dashboards/llm-cost-dashboard.json <<'EOF'
{
  "uid": "llm-cost",
  "title": "LLM Cost & Usage",
  "timezone": "browser",
  "time": { "from": "now-24h", "to": "now" },
  "refresh": "1m",
  "panels": [
    {
      "id": 1, "type": "stat", "title": "Total LLM spend (USD)",
      "gridPos": { "h": 6, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "currencyUSD", "decimals": 4 }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 1,
        "rawSql": "SELECT sum(total_cost) AS total_spend FROM observations WHERE start_time >= $__fromTime AND start_time <= $__toTime"
      }]
    },
    {
      "id": 2, "type": "stat", "title": "Total tokens",
      "gridPos": { "h": 6, "w": 6, "x": 6, "y": 0 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "short" }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 1,
        "rawSql": "SELECT sum(usage_details['total']) AS total_tokens FROM observations WHERE start_time >= $__fromTime AND start_time <= $__toTime"
      }]
    },
    {
      "id": 3, "type": "stat", "title": "p95 latency (ms)",
      "gridPos": { "h": 6, "w": 6, "x": 12, "y": 0 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "ms" }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 1,
        "rawSql": "SELECT quantile(0.95)(date_diff('millisecond', start_time, end_time)) AS p95_ms FROM observations WHERE end_time IS NOT NULL AND start_time >= $__fromTime AND start_time <= $__toTime"
      }]
    },
    {
      "id": 4, "type": "stat", "title": "LLM calls",
      "gridPos": { "h": 6, "w": 6, "x": 18, "y": 0 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "short" }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 1,
        "rawSql": "SELECT count() AS calls FROM observations WHERE type = 'GENERATION' AND start_time >= $__fromTime AND start_time <= $__toTime"
      }]
    },
    {
      "id": 5, "type": "timeseries", "title": "Spend over time (USD)",
      "gridPos": { "h": 9, "w": 12, "x": 0, "y": 6 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "currencyUSD" }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 0,
        "rawSql": "SELECT $__timeInterval(start_time) AS time, sum(total_cost) AS spend FROM observations WHERE $__timeFilter(start_time) GROUP BY time ORDER BY time"
      }]
    },
    {
      "id": 6, "type": "piechart", "title": "Spend by model",
      "gridPos": { "h": 9, "w": 12, "x": 12, "y": 6 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "currencyUSD" }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 1,
        "rawSql": "SELECT coalesce(nullif(provided_model_name, ''), 'unknown') AS model, sum(total_cost) AS spend FROM observations WHERE $__timeFilter(start_time) GROUP BY model ORDER BY spend DESC LIMIT 10"
      }]
    },
    {
      "id": 7, "type": "timeseries", "title": "Tokens over time",
      "gridPos": { "h": 9, "w": 12, "x": 0, "y": 15 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": { "unit": "short" }, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 0,
        "rawSql": "SELECT $__timeInterval(start_time) AS time, sum(usage_details['input']) AS input_tokens, sum(usage_details['output']) AS output_tokens FROM observations WHERE $__timeFilter(start_time) GROUP BY time ORDER BY time"
      }]
    },
    {
      "id": 8, "type": "table", "title": "Most expensive traces",
      "gridPos": { "h": 9, "w": 12, "x": 12, "y": 15 },
      "datasource": { "type": "grafana-clickhouse-datasource", "uid": "langfuse-ch" },
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "targets": [{
        "refId": "A", "format": 1,
        "rawSql": "SELECT trace_id, coalesce(nullif(provided_model_name, ''), 'unknown') AS model, round(sum(total_cost), 6) AS cost_usd, sum(usage_details['total']) AS tokens FROM observations WHERE $__timeFilter(start_time) GROUP BY trace_id, model ORDER BY cost_usd DESC LIMIT 20"
      }]
    }
  ],
  "schemaVersion": 39,
  "version": 1
}
EOF

# ----------------------------------------------------------------------------
# The differentiator #2: eval hooks preset
# A worker that polls new Langfuse traces and attaches automatic eval scores.
# ----------------------------------------------------------------------------
cat > eval-hooks/Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY presets.yml eval_worker.py ./
CMD ["python", "-u", "eval_worker.py"]
EOF

cat > eval-hooks/requirements.txt <<'EOF'
requests==2.32.3
PyYAML==6.0.2
EOF

cat > eval-hooks/presets.yml <<'EOF'
# Eval hook presets - each hook attaches a score to every new trace.
# Extend this file with your own hooks; the worker picks them up on restart.
latency_slo:
  enabled: true
  threshold_ms: 5000        # trace slower than this -> score 0

cost_budget:
  enabled: true
  max_cost_usd: 0.05        # trace costing more than this -> score 0

refusal_detector:
  enabled: true
  patterns:
    - "i can't help"
    - "i cannot help"
    - "i'm sorry, but"
    - "as an ai"

empty_output:
  enabled: true
EOF

cat > eval-hooks/eval_worker.py <<'EOF'
"""
Eval hooks preset worker.

Polls the Langfuse public API for new traces and attaches automatic
evaluation scores (latency SLO, cost budget, refusal detection,
empty-output detection). Processed trace IDs are persisted to /state
so evals are not duplicated across restarts.
"""
import json
import os
import re
import time
from pathlib import Path

import requests
import yaml

HOST = os.environ["LANGFUSE_HOST"].rstrip("/")
AUTH = (os.environ["LANGFUSE_PUBLIC_KEY"], os.environ["LANGFUSE_SECRET_KEY"])
POLL = int(os.environ.get("POLL_INTERVAL_SECONDS", "60"))
STATE_FILE = Path("/state/processed_traces.json")

with open("presets.yml") as f:
    PRESETS = yaml.safe_load(f)


def load_state() -> set:
    if STATE_FILE.exists():
        return set(json.loads(STATE_FILE.read_text()))
    return set()


def save_state(processed: set) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    # keep the state file bounded
    STATE_FILE.write_text(json.dumps(sorted(processed)[-5000:]))


def post_score(trace_id: str, name: str, value: float, comment: str) -> None:
    r = requests.post(
        f"{HOST}/api/public/scores",
        auth=AUTH,
        json={"traceId": trace_id, "name": name, "value": value, "comment": comment},
        timeout=30,
    )
    r.raise_for_status()


def eval_trace(trace: dict) -> None:
    tid = trace["id"]

    # --- latency SLO -------------------------------------------------------
    cfg = PRESETS.get("latency_slo", {})
    if cfg.get("enabled") and trace.get("latency") is not None:
        latency_ms = float(trace["latency"]) * 1000
        ok = latency_ms <= cfg["threshold_ms"]
        post_score(tid, "latency_slo", 1.0 if ok else 0.0,
                   f"{latency_ms:.0f}ms vs SLO {cfg['threshold_ms']}ms")

    # --- cost budget -------------------------------------------------------
    cfg = PRESETS.get("cost_budget", {})
    if cfg.get("enabled") and trace.get("totalCost") is not None:
        cost = float(trace["totalCost"])
        ok = cost <= cfg["max_cost_usd"]
        post_score(tid, "cost_budget", 1.0 if ok else 0.0,
                   f"${cost:.5f} vs budget ${cfg['max_cost_usd']}")

    output_text = json.dumps(trace.get("output") or "").lower()

    # --- refusal detector --------------------------------------------------
    cfg = PRESETS.get("refusal_detector", {})
    if cfg.get("enabled"):
        hit = next((p for p in cfg.get("patterns", [])
                    if re.search(re.escape(p), output_text)), None)
        post_score(tid, "refusal_detected", 1.0 if hit else 0.0,
                   f"matched: {hit}" if hit else "no refusal patterns")

    # --- empty output ------------------------------------------------------
    cfg = PRESETS.get("empty_output", {})
    if cfg.get("enabled"):
        empty = output_text.strip('"').strip() in ("", "null", "none")
        post_score(tid, "empty_output", 1.0 if empty else 0.0,
                   "output empty" if empty else "output present")


def fetch_all_traces(max_pages: int = 50) -> list:
    """Paginate through the full trace list so every trace gets evaluated,
    regardless of batch size or back-dated timestamps."""
    traces = []
    for page in range(1, max_pages + 1):
        r = requests.get(
            f"{HOST}/api/public/traces",
            auth=AUTH,
            params={"limit": 100, "page": page, "orderBy": "timestamp.desc"},
            timeout=30,
        )
        r.raise_for_status()
        data = r.json().get("data", [])
        if not data:
            break
        traces.extend(data)
    return traces


def main() -> None:
    processed = load_state()
    print(f"[eval-worker] started; {len(processed)} traces already processed")
    while True:
        try:
            traces = fetch_all_traces()
            new = [t for t in traces if t["id"] not in processed]
            for trace in new:
                try:
                    eval_trace(trace)
                    processed.add(trace["id"])
                    print(f"[eval-worker] scored trace {trace['id']}")
                except Exception as exc:  # noqa: BLE001
                    print(f"[eval-worker] failed on {trace['id']}: {exc}")
            if new:
                save_state(processed)
        except Exception as exc:  # noqa: BLE001
            print(f"[eval-worker] poll error (Langfuse may still be booting): {exc}")
        time.sleep(POLL)


if __name__ == "__main__":
    main()
EOF

# ----------------------------------------------------------------------------
# Convenience: on-instance test-trace generator
# ----------------------------------------------------------------------------
cat > send_test_traces.py <<'EOF'
"""Send synthetic LLM traces with usage, cost and latency into Langfuse.
Usage (on the instance): python3 send_test_traces.py [count]
"""
import base64, datetime as dt, json, random, sys, urllib.request, uuid

env = dict(line.strip().split("=", 1) for line in open("/opt/ai-observability/.env") if "=" in line)
HOST = "http://localhost:3000"

PRICES = {  # USD per 1K tokens (input, output)
    "gpt-4o": (0.0025, 0.01),
    "gpt-4o-mini": (0.00015, 0.0006),
    "claude-sonnet-4-5": (0.003, 0.015),
    "amazon.nova-pro-v1:0": (0.0008, 0.0032),
}
OUTPUTS = [
    "Here is the summary you asked for...",
    "The capital of France is Paris.",
    "I'm sorry, but I can't help with that request.",
    "",
]

count = int(sys.argv[1]) if len(sys.argv) > 1 else 20
now = dt.datetime.now(dt.timezone.utc)
batch = []
for _ in range(count):
    trace_id = str(uuid.uuid4())
    start = now - dt.timedelta(minutes=random.randint(0, 600))
    latency_ms = random.choice([400, 900, 1500, 2500, 4000, 6500, 9000])
    end = start + dt.timedelta(milliseconds=latency_ms)
    model = random.choice(list(PRICES))
    inp, outp = random.randint(200, 6000), random.randint(50, 3000)
    pin, pout = PRICES[model]
    ic, oc = inp / 1000 * pin, outp / 1000 * pout
    output = random.choice(OUTPUTS)
    ts, te = start.isoformat(), end.isoformat()
    batch.append({"id": str(uuid.uuid4()), "type": "trace-create", "timestamp": ts,
                  "body": {"id": trace_id, "name": "chat-completion", "timestamp": ts,
                           "input": {"q": "demo question"}, "output": output}})
    batch.append({"id": str(uuid.uuid4()), "type": "generation-create", "timestamp": te,
                  "body": {"id": str(uuid.uuid4()), "traceId": trace_id, "name": "llm-call",
                           "model": model, "startTime": ts, "endTime": te,
                           "usage": {"input": inp, "output": outp},
                           "costDetails": {"input": ic, "output": oc, "total": ic + oc},
                           "input": {"q": "demo question"}, "output": output}})

req = urllib.request.Request(f"{HOST}/api/public/ingestion",
    data=json.dumps({"batch": batch}).encode(),
    headers={"Content-Type": "application/json"}, method="POST")
creds = base64.b64encode(f"{env['LANGFUSE_PUBLIC_KEY']}:{env['LANGFUSE_SECRET_KEY']}".encode()).decode()
req.add_header("Authorization", f"Basic {creds}")
print(urllib.request.urlopen(req).read().decode()[:300])
print(f"Sent {count} traces with cost + latency.")
EOF

# ----------------------------------------------------------------------------
# Launch
# ----------------------------------------------------------------------------
docker compose pull
docker compose build eval-worker
docker compose up -d

echo "Bootstrap complete. Credentials in $APP/credentials.txt"
