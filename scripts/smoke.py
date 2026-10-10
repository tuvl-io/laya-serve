"""Smoke test a running laya-serve: one choice question, checked against the Jev wire shape."""

import json
import os
import sys
import urllib.request

base = os.environ.get("LAYA_API_BASE", "http://127.0.0.1:8000").rstrip("/")
headers = {"content-type": "application/json"}
if os.environ.get("LAYA_API_KEY"):
    headers["authorization"] = f"Bearer {os.environ['LAYA_API_KEY']}"

body = {
    "state": {
        "subject": "Charged twice",
        "body": "I was billed twice this month, please refund.",
    },
    "questions": {
        "team": {
            "type": "choice",
            "instructions": "Which team should handle this support ticket?",
            "criteria": {
                "billing": "charges, refunds, invoices",
                "tech": "bugs, crashes, errors",
                "account": "login, profile, deletion",
            },
        }
    },
}
request = urllib.request.Request(
    f"{base}/v1/systemone",
    data=json.dumps(body).encode(),
    headers=headers,
    method="POST",
)
with urllib.request.urlopen(request, timeout=60) as resp:
    result = json.load(resp)

answer = result["answers"]["team"]
assert answer["type"] == "choice", answer
assert answer["choice"] in body["questions"]["team"]["criteria"], answer
assert 0.0 <= float(answer["confidence"]) <= 1.0, answer
assert set(answer["probabilities"]) == set(body["questions"]["team"]["criteria"]), (
    answer
)
print(
    json.dumps(result, indent=2)
    if "-v" in sys.argv
    else f"ok: team={answer['choice']} "
    f"confidence={answer['confidence']:.3f} model={result.get('model')}"
)
