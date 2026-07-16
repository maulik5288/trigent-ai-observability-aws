# AI Observability Stack — AWS test deployment

One-command Terraform deployment of the AI Observability product (the pre-AMI prototype):
**Langfuse v3** (LLM traces, prompts, evals) + **Grafana LLM cost dashboards** (pre-provisioned,
querying Langfuse's ClickHouse directly) + **eval hooks preset** (auto-scoring worker) —
all on a single EC2 instance via Docker Compose.

```
├── terraform/
│   ├── main.tf                  # VPC lookup, security group, EC2 instance
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── user_data.sh             # Bootstrap: writes the entire app stack at boot
│                                #  - docker-compose.yml (Langfuse v3 + CH + PG + Redis + MinIO)
│                                #  - Grafana provisioning + LLM cost dashboard JSON
│                                #  - eval-hooks worker (Dockerfile + presets.yml + eval_worker.py)
│                                #  - send_test_traces.py (synthetic data generator)
└── scripts/
    └── send_test_traces_reference.py   # Same generator, for reference
```

All secrets (DB passwords, Langfuse keys, admin login, Grafana password) are **generated at
first boot** and never stored in code — the same pattern AWS Marketplace requires of AMIs.

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with credentials (`aws sts get-caller-identity` should work)
- An existing EC2 key pair in your region (recommended, to read generated credentials)

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars:
#   allowed_cidr_blocks = ["<your-ip>/32"]   (curl ifconfig.me)
#   key_name            = "<your-keypair>"

terraform init
terraform apply
```

First boot takes **5–8 minutes** (Docker images pull + ClickHouse migrations).
Watch progress if you like:

```bash
ssh -i <key.pem> ubuntu@<public_ip> 'sudo tail -f /var/log/ai-observability-bootstrap.log'
```

## Get credentials

```bash
ssh -i <key.pem> ubuntu@<public_ip> 'sudo cat /opt/ai-observability/credentials.txt'
```

| Service  | URL (from terraform output) | Login |
|----------|------------------------------|-------|
| Langfuse | `http://<ip>:3000`           | admin@example.com / generated password |
| Grafana  | `http://<ip>:3001`           | admin / generated password |

## Generate test data

On the instance:

```bash
ssh -i <key.pem> ubuntu@<public_ip>
cd /opt/ai-observability && sudo python3 send_test_traces.py 50
```

Then check:

1. **Langfuse → Traces**: 50 synthetic chat-completion traces.
2. **Langfuse → Scores** (within ~60s): the eval worker attaches `latency_slo`,
   `cost_budget`, `refusal_detected`, `empty_output` scores to each trace.
3. **Grafana → LLM Observability → LLM Cost & Usage**: spend, tokens, p95 latency,
   spend-by-model, most-expensive-traces — populated from ClickHouse.

To point a real app at it, use the Langfuse SDK with host `http://<ip>:3000` and the
generated `pk-lf-...` / `sk-lf-...` keys.

## Customize the eval hooks

Edit `/opt/ai-observability/eval-hooks/presets.yml` on the instance
(thresholds, refusal patterns, or add new hooks in `eval_worker.py`), then:

```bash
cd /opt/ai-observability && sudo docker compose up -d --build eval-worker
```

## Notes & known tweaks

- Dashboard SQL targets Langfuse v3's ClickHouse schema (`observations` table,
  `total_cost`, `usage_details` map). If a future Langfuse release changes columns,
  adjust the queries in `grafana/dashboards/llm-cost-dashboard.json`.
- Everything runs over plain HTTP — fine for testing behind an IP allowlist,
  not for production. Production path: ALB + ACM cert, or Caddy on-instance.
- Rough cost: t3.large ≈ $0.08–0.10/hr + 60 GB gp3 EBS. **Destroy when done.**

## Teardown

```bash
terraform destroy
```

## Path to the Marketplace AMI

This Terraform deployment is the functional prototype. To productize:

1. Convert `user_data.sh` into a Packer build (bake images with `docker compose pull`
   at build time; keep secret generation in a first-boot systemd unit).
2. Build the AMI in **us-east-1**, harden per the AWS Marketplace security checklist
   (no hardcoded secrets, SSH password auth disabled — Ubuntu default already complies).
3. Run the Marketplace "Test Add Version" scan and submit the product load form.

## Local version (free, no AWS)

The `local/` folder runs the identical stack on your laptop with Docker Desktop —
see `local/README.md`. Recommended for iterating on dashboards and eval hooks;
use the Terraform deployment for AWS-specific testing (boot automation, sizing, AMI path).
