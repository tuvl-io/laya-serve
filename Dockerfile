# syntax=docker/dockerfile:1
# Laya decision server (laya-serve, POST /v1/systemone) on CPU, with verified weights baked in.
ARG PYTHON_IMAGE=python:3.12-slim-bookworm@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258

FROM ${PYTHON_IMAGE} AS deps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
COPY requirements.lock /tmp/requirements.lock
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --require-hashes --no-deps \
      --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple \
      -r /tmp/requirements.lock
# Inference never touches C++ headers, test suites or type stubs, nor pip itself (torchgen stays: torch imports it).
RUN SP=/opt/venv/lib/python3.12/site-packages \
 && rm -rf "$SP/torch/include" "$SP/torch/share" \
 && find "$SP" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} + \
 && find "$SP" -name '*.pyi' -delete \
 && /opt/venv/bin/python -m pip uninstall -y pip \
 && du -sh "$SP" "$SP"/torch "$SP"/transformers

FROM deps AS weights
# Checkpoints to bake: english, multilingual, typed-decisions (comma-separated).
ARG LAYA_MODELS=english,multilingual
ENV HF_HOME=/opt/hf LAYA_MODELS=${LAYA_MODELS}
COPY scripts/fetch_weights.py /tmp/fetch_weights.py
# Keep only the verified snapshot: drop the Hub client's chunk cache and lock/partial files.
RUN /opt/venv/bin/python /tmp/fetch_weights.py \
 && rm -rf /opt/hf/xet /opt/hf/.cache /opt/hf/hub/.locks \
 && find /opt/hf -name '*.incomplete' -delete \
 && du -ah -d 4 /opt/hf | sort -h | tail -12

FROM ${PYTHON_IMAGE}
ARG LAYA_MODELS=english,multilingual
LABEL org.opencontainers.image.title="laya-serve" \
      org.opencontainers.image.description="Laya open-weight typed-decision model server over POST /v1/systemone (Jev-compatible). CPU-only, offline, with hash-verified weights baked in; runs as non-root." \
      org.opencontainers.image.vendor="tuvl" \
      org.opencontainers.image.url="https://tuvl.io" \
      org.opencontainers.image.documentation="https://tuvl.dev" \
      org.opencontainers.image.source="https://github.com/tuvl-io/laya-serve" \
      org.opencontainers.image.licenses="Apache-2.0"
RUN useradd --system --uid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin laya
COPY --from=deps /opt/venv /opt/venv
COPY --from=weights --chown=laya:laya /opt/hf /opt/hf
COPY scripts/healthcheck.py /usr/local/bin/healthcheck.py
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/opt/hf \
    HF_HUB_OFFLINE=1 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    LAYA_REVISION=reviewed \
    LAYA_MODELS=${LAYA_MODELS} \
    LAYA_PRELOAD=1 \
    LAYA_HOST=0.0.0.0 \
    LAYA_PORT=8000
USER laya
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --start-period=120s --retries=3 \
  CMD ["python", "/usr/local/bin/healthcheck.py"]
CMD ["laya-serve"]
