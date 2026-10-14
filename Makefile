IMAGE       ?= laya-serve
LAYA        := $(shell sed -n 's/^laya\[serve\]==//p' requirements.in)
TAG         ?= $(LAYA)
LAYA_MODELS ?= english,multilingual
PORT        ?= 8000

.PHONY: lock build build-en run smoke stop inspect

lock:  ## re-resolve requirements.lock (hash-pinned, CPU torch)
	uv pip compile requirements.in --universal --generate-hashes -p 3.12 \
	  --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple \
	  --index-strategy unsafe-best-match --no-header -o requirements.lock

build:
	docker build --build-arg LAYA_MODELS=$(LAYA_MODELS) -t $(IMAGE):$(TAG) .

build-en:  ## English-only variant, tagged <version>-en
	$(MAKE) build LAYA_MODELS=english TAG=$(LAYA)-en

inspect:  ## per-layer sizes and what the weights layer holds
	docker history --no-trunc=false --format '{{.Size}}\t{{.CreatedBy}}' $(IMAGE):$(TAG) | cut -c1-110
	docker run --rm --entrypoint sh $(IMAGE):$(TAG) -c 'du -ah -d 3 /opt/hf | sort -h | tail -12; du -sh /opt/venv'

run:
	docker run -d --rm --name laya-serve -p $(PORT):8000 $(IMAGE):$(TAG)

smoke:  ## needs a running server (make run); waits for it to become healthy
	@until [ "$$(docker inspect -f '{{.State.Health.Status}}' laya-serve 2>/dev/null)" = healthy ]; do sleep 3; done
	LAYA_API_BASE=http://127.0.0.1:$(PORT) python3 scripts/smoke.py

stop:
	docker stop laya-serve
