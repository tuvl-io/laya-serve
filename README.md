# laya-serve

A container image for [Laya](https://pypi.org/project/laya/), the open-weight typed-decision model,
served over the `POST /v1/systemone` protocol (the same wire format as TypeSafe's Jev API). tuvl's
`decide` agents use it as a decision model; anything that speaks `/v1/systemone` can.

- CPU-only PyTorch; no GPU or CUDA needed.
- Weights are baked in and verified at build time against the Hub's hashes for Laya's own reviewed
  commit. At runtime the image is offline (`HF_HUB_OFFLINE=1`) and loads only those files.
- Dependencies are hash-locked (`requirements.lock`); the base image is pinned by digest.
- Runs as a non-root user, with a `/health` probe wired to the Docker `HEALTHCHECK`.

## Run it

```bash
make build                     # laya-serve:0.4.1 with english + multilingual checkpoints
make run && make smoke         # starts on 127.0.0.1:8000 and asks one question
```

Or with Compose: `docker compose up -d`.

```bash
curl -s localhost:8000/v1/systemone -H 'content-type: application/json' -d '{
  "state": {"body": "I was billed twice this month, please refund."},
  "questions": {"team": {"type": "choice", "instructions": "Which team handles this?",
    "criteria": {"billing": "charges, refunds", "tech": "bugs, crashes", "account": "login, profile"}}}
}'
```

Each answer carries the `choice`, a `probabilities` map, `confidence` (1 − normalised entropy) and
`answer_confidence` (the calibrated probability of the chosen value).

## Checkpoints

Chosen at build time with `LAYA_MODELS` (`make build LAYA_MODELS=english`):

| Checkpoint | Size | Use |
|---|---|---|
| `english` | ~0.9 GB | English text (ModernBERT-large) |
| `multilingual` | ~0.7 GB | 100+ languages (mmBERT); Laya routes non-English text here |
| `typed-decisions` | ~0.9 GB | Fine-tuned on four specific workflows; only used when asked for explicitly |

The default (`english,multilingual`) builds a ~2.7 GB image and uses ~3.5 GB of memory with both
checkpoints loaded. Build with `LAYA_MODELS=english` for English-only traffic.

## Configuration

All runtime settings are `laya-serve` environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `LAYA_API_KEY` | (none) | Require `Authorization: Bearer <key>` |
| `LAYA_THREADS` | torch default | CPU threads; keep ≤ physical cores |
| `LAYA_MAX_CONCURRENT` | 16 | Requests in flight before 503 |
| `LAYA_JEV_STRICT` | 0 | Return only the strict Jev response fields |

The image sets `LAYA_REVISION=reviewed`, `LAYA_PRELOAD=1` and `HF_HUB_OFFLINE=1`; overriding them
defeats the pinning. `/opt/hf/laya-weights.json` inside the image lists every file and its SHA-256.

## With tuvl

`tuvl init` offers Laya as a decision model and writes the AgentModel, `.env` entries and a Compose
file for local development. `tuvl ship` adds a Laya Deployment and Service to the Helm chart when the
project uses it (or with `--with-laya`). See the tuvl docs: Decide → Decision models.

## Updating

1. Bump `laya[serve]==…` in `requirements.in`, then `make lock`.
2. `make build && make run && make smoke`.
3. The reviewed weight commit comes from the `laya` package (`laya.revisions.PINNED_REVISIONS`), so a
   package bump also moves the weights — check the build log's `verified … @<commit>` line.

## Licence

MIT for this repository's build files; the image redistributes Apache-2.0 Laya code and weights.
See [NOTICE](NOTICE).
