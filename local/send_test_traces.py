"""Send synthetic LLM traces with usage, cost and latency into Langfuse.
Usage (local): python3 send_test_traces.py [count]
"""
import base64, datetime as dt, json, random, sys, urllib.request, uuid

env = dict(line.strip().split("=", 1) for line in open(__file__.rsplit("/",1)[0] + "/.env") if "=" in line)
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
