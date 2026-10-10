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

FROM deps AS weights
# Checkpoints to bake: english, multilingual, typed-decisions (comma-separated).
ARG LAYA_MODELS=english,multilingual
ENV HF_HOME=/opt/hf LAYA_MODELS=${LAYA_MODELS}
COPY scripts/fetch_weights.py /tmp/fetch_weights.py
RUN /opt/venv/bin/python /tmp/fetch_weights.py

FROM ${PYTHON_IMAGE}
ARG LAYA_MODELS=english,multilingual
LABEL org.opencontainers.image.title="laya-serve" \
      org.opencontainers.image.description="Laya typed-decision server (POST /v1/systemone), CPU, pinned weights" \
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
