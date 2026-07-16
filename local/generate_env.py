"""
Generate .env and credentials.txt for the local AI Observability stack.
Cross-platform (Windows / macOS / Linux) - only needs Python 3.8+.

Usage:  python3 generate_env.py
Then:   docker compose up -d --build
"""
import secrets
from pathlib import Path

HERE = Path(__file__).parent
ENV_FILE = HERE / ".env"
CREDS_FILE = HERE / "credentials.txt"

if ENV_FILE.exists():
    print(".env already exists - delete it first if you want fresh credentials.")
    raise SystemExit(0)

values = {
    "PUBLIC_IP": "localhost",
    "POSTGRES_PASSWORD": secrets.token_hex(16),
    "CLICKHOUSE_PASSWORD": secrets.token_hex(16),
    "REDIS_PASSWORD": secrets.token_hex(16),
    "MINIO_ROOT_PASSWORD": secrets.token_hex(16),
    "GRAFANA_PASSWORD": secrets.token_hex(8),
    "NEXTAUTH_SECRET": secrets.token_urlsafe(32),
    "SALT": secrets.token_urlsafe(32),
    "ENCRYPTION_KEY": secrets.token_hex(32),
    "ADMIN_EMAIL": "admin@example.com",
    "ADMIN_PASSWORD": secrets.token_hex(8),
    "LANGFUSE_PUBLIC_KEY": f"pk-lf-{secrets.token_hex(12)}",
    "LANGFUSE_SECRET_KEY": f"sk-lf-{secrets.token_hex(12)}",
}

ENV_FILE.write_text("\n".join(f"{k}={v}" for k, v in values.items()) + "\n")

CREDS_FILE.write_text(f"""==============================================================
 AI Observability Stack (local) - generated credentials
==============================================================
Langfuse UI ........ http://localhost:3000
  login email ...... {values['ADMIN_EMAIL']}
  login password ... {values['ADMIN_PASSWORD']}

Langfuse API keys (project: default-project)
  public key ....... {values['LANGFUSE_PUBLIC_KEY']}
  secret key ....... {values['LANGFUSE_SECRET_KEY']}

Grafana ............ http://localhost:3001
  user ............. admin
  password ......... {values['GRAFANA_PASSWORD']}
==============================================================
""")

print("Wrote .env and credentials.txt")
print(f"Langfuse login: {values['ADMIN_EMAIL']} / {values['ADMIN_PASSWORD']}")
print(f"Grafana login:  admin / {values['GRAFANA_PASSWORD']}")
print("\nNext: docker compose up -d --build   (first start takes a few minutes)")
