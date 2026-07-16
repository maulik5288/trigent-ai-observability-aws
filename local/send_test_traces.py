"""Send synthetic LLM traces into the LOCAL Langfuse so dashboards/evals have data.
Usage: python3 send_test_traces.py [count]
"""
import base64
import datetime as dt
import json
import random
import sys
import urllib.request
import uuid
from pathlib import Path

env = {}
for line in (Path(__file__).parent / ".env").read_text().splitlines():
    if "=" in line:
        k, v = line.split("=", 1)
        env[k] = v

HOST = "http://localhost:3000"
MODELS = ["gpt-4o-mini", "gpt-4o", "claude-sonnet-4-5", "amazon.nova-pro-v1:0"]
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
    ts = (now - dt.timedelta(minutes=random.randint(0, 600))).isoformat()
    model = random.choice(MODELS)
    inp, outp = random.randint(200, 3000), random.randint(50, 1500)
    output = random.choice(OUTPUTS)
    batch.append({"id": str(uuid.uuid4()), "type": "trace-create", "timestamp": ts,
                  "body": {"id": trace_id, "name": "chat-completion", "timestamp": ts,
                           "input": {"q": "demo question"}, "output": output}})
    batch.append({"id": str(uuid.uuid4()), "type": "generation-create", "timestamp": ts,
                  "body": {"id": str(uuid.uuid4()), "traceId": trace_id, "name": "llm-call",
                           "model": model, "startTime": ts, "endTime": ts,
                           "usage": {"input": inp, "output": outp},
                           "input": {"q": "demo question"}, "output": output}})

req = urllib.request.Request(
    f"{HOST}/api/public/ingestion",
    data=json.dumps({"batch": batch}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
creds = base64.b64encode(
    f"{env['LANGFUSE_PUBLIC_KEY']}:{env['LANGFUSE_SECRET_KEY']}".encode()
).decode()
req.add_header("Authorization", f"Basic {creds}")
print(urllib.request.urlopen(req).read().decode())
print(f"Sent {count} synthetic traces. Open http://localhost:3000 (traces) and http://localhost:3001 (cost dashboard).")
