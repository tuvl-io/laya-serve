IMAGE       ?= laya-serve
LAYA        := $(shell sed -n 's/^laya\[serve\]==//p' requirements.in)
TAG         ?= $(LAYA)
LAYA_MODELS ?= english,multilingual
PORT        ?= 8000

.PHONY: lock build run smoke stop

lock:  ## re-resolve requirements.lock (hash-pinned, CPU torch)
	uv pip compile requirements.in --universal --generate-hashes -p 3.12 \
	  --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple \
	  --index-strategy unsafe-best-match --no-header -o requirements.lock

build:
	docker build --build-arg LAYA_MODELS=$(LAYA_MODELS) -t $(IMAGE):$(TAG) .

run:
	docker run -d --rm --name laya-serve -p $(PORT):8000 $(IMAGE):$(TAG)

smoke:  ## needs a running server (make run); waits for it to become healthy
	@until [ "$$(docker inspect -f '{{.State.Health.Status}}' laya-serve 2>/dev/null)" = healthy ]; do sleep 3; done
	LAYA_API_BASE=http://127.0.0.1:$(PORT) python3 scripts/smoke.py

stop:
	docker stop laya-serve
