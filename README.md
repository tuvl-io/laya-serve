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
make build                     # laya-serve:0.4.7 with english + multilingual checkpoints
make build-en                  # laya-serve:0.4.7-en, english only (about 0.7 GB smaller)
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

## Images

| Tag | Checkpoints | Use |
|---|---|---|
| `<version>-en` | english | English-only traffic; the smaller image and about half the memory |
| `<version>` | english + multilingual | Mixed-language traffic, or `model: auto` |

An `-en` image has no multilingual weights and runs offline, so a request routed to `multilingual`
(non-English text with `model: auto`, or `model: multilingual`) fails with HTTP 500
`inference failed`. Pin `model: english` with `-en`, and use the full tag otherwise. The English
image uses about 2 GiB of memory against about 3.5 GiB for the full one.

## Checkpoints

Chosen at build time with `LAYA_MODELS` (`make build LAYA_MODELS=english`):

| Checkpoint | Size | Use |
|---|---|---|
| `english` | ~0.9 GB | English text (ModernBERT-large) |
| `multilingual` | ~0.7 GB | 100+ languages (mmBERT); Laya routes non-English text here |
| `typed-decisions` | ~0.9 GB | Fine-tuned on four specific workflows; only used when asked for explicitly |

The default (`english,multilingual`) builds a ~2.7 GB image and uses ~3.5 GB of memory with both
checkpoints loaded. `LAYA_MODELS=english` (the `-en` image) keeps one checkpoint resident.
`make inspect` prints the per-layer sizes and what the weights layer holds.

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

## Publishing

CI builds and smoke-tests the image on native amd64 and arm64 runners for every push and pull
request. Pushing a `v*` tag (e.g. `v0.4.7`) also publishes both architectures to Docker Hub as one
tag per variant, `<namespace>/laya-serve:<version>` and `<version>-en`, plus `:latest` and
`:latest-en` unless the version is a pre-release.

The image version is the Laya version it serves, which also pins the weights. A rebuild of the same
Laya version (a base-image or dependency fix) adds a build number: `v0.4.7-1`, `v0.4.7-2`; it moves
`:latest` too. `-alpha`, `-beta` and `-rc` tags are pre-releases and never do. The
repository needs the secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (a Read & Write access
token), and optionally the variable `DOCKERHUB_NAMESPACE` when publishing to an organization.

## Licence

MIT for this repository's build files; the image redistributes Apache-2.0 Laya code and weights.
See [NOTICE](NOTICE).
