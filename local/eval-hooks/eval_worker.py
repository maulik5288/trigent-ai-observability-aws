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
