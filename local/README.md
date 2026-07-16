# Local version — run the whole stack on your laptop (free)

Identical stack to the AWS deployment (Langfuse v3 + ClickHouse + Postgres + Redis +
MinIO + Grafana cost dashboards + eval-hooks worker), running on Docker Desktop.
Use this for iterating on dashboards, eval hooks, and Langfuse config without any AWS cost.

## Requirements

- Docker Desktop (Windows/macOS) or Docker Engine + compose plugin (Linux)
- ~8 GB RAM available to Docker (Docker Desktop → Settings → Resources)
- Python 3.8+

## Run

```bash
cd local
python3 generate_env.py          # creates .env + credentials.txt (on Windows: python generate_env.py)
docker compose up -d --build     # first start pulls images + runs migrations: 3-5 min
```

Then open:

| Service  | URL | Login |
|----------|-----|-------|
| Langfuse | http://localhost:3000 | see `credentials.txt` |
| Grafana  | http://localhost:3001 | admin / see `credentials.txt` |

## Test data

```bash
python3 send_test_traces.py 50
```

- Langfuse → Traces: synthetic traces appear immediately.
- Langfuse → Scores: eval worker attaches `latency_slo`, `cost_budget`,
  `refusal_detected`, `empty_output` within ~60 seconds.
- Grafana → LLM Observability → **LLM Cost & Usage**: spend/tokens/latency panels.

## Iterate on the product

- **Eval hooks**: edit `eval-hooks/presets.yml` or add hooks in `eval-hooks/eval_worker.py`,
  then `docker compose up -d --build eval-worker`.
- **Cost dashboards**: edit panels live in the Grafana UI, then export the JSON back into
  `grafana/dashboards/llm-cost-dashboard.json` so it's version-controlled and ships in the AMI.
- **Point a real app at it**: Langfuse SDK with host `http://localhost:3000` and the
  `pk-lf-...` / `sk-lf-...` keys from `credentials.txt`.

## Useful commands

```bash
docker compose ps                    # health of all services
docker compose logs -f langfuse-web  # watch Langfuse boot / migrations
docker compose logs -f eval-worker   # watch evals being applied
docker compose down                  # stop (data kept in volumes)
docker compose down -v               # stop and DELETE all data
```

Anything you build and verify here transfers 1:1 to the AWS deployment — the AWS
bootstrap (`terraform/user_data.sh`) writes this exact same stack at instance boot.
