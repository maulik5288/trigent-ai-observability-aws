#!/bin/bash
# ============================================================================
# FIRST BOOT (customer launch): generate all secrets, write .env and
# credentials.txt, start the pre-baked stack. Runs once (guarded by
# /opt/ai-observability/.provisioned via the systemd unit condition).
# ============================================================================
set -euxo pipefail
exec > /var/log/ai-observability-firstboot.log 2>&1

APP=/opt/ai-observability
cd "$APP"

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


docker compose up -d
touch "$APP/.provisioned"
echo "First boot complete. Credentials in $APP/credentials.txt"
