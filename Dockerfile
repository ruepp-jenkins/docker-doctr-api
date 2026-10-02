# syntax=docker/dockerfile:1
#
# docTR packaged as a ready-to-run OCR REST API.
#
# Upstream (https://github.com/mindee/doctr) ships the library and, in its api/ folder, a FastAPI
# template that is meant to be built and run from a checkout. This image takes both from one
# release tag, installs them CPU-only and starts the API on container start.
#
# Stages:
#   source        upstream checkout of DOCTR_VERSION
#   build         virtualenv with torch (CPU), docTR and the API dependencies
#   models        the default pretrained weights, downloaded once at build time
#   test          upstream API tests + this repository's tests; never fails, writes a verdict
#   test-results  only the JUnit report, exported by scripts/test.sh
#   verified      refuses to continue when the verdict is not 0
#   runtime       the published image (default target)

ARG PYTHON_VERSION=3.12

# ---------------------------------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS base

# libgl1 + libglib2.0-0: required by opencv-python, which docTR depends on (the headless variant does
# not satisfy that requirement). curl: used by the HEALTHCHECK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    DOCTR_CACHE_DIR=/opt/doctr/cache \
    HF_HOME=/opt/doctr/cache/huggingface

# ---------------------------------------------------------------------------------------------------
FROM base AS source

ARG DOCTR_VERSION
RUN test -n "${DOCTR_VERSION}" || (echo "DOCTR_VERSION build arg is required, e.g. v1.1.0" >&2; exit 1)

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${DOCTR_VERSION}" https://github.com/mindee/doctr.git /src/doctr

# ---------------------------------------------------------------------------------------------------
FROM base AS build

ARG DOCTR_VERSION
# CPU wheels only. The default PyPI torch wheel for amd64 bundles CUDA and adds several GB the
# image cannot use without a GPU runtime anyway. The CPU index serves amd64 and arm64 alike.
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu

RUN python -m venv "${VIRTUAL_ENV}" \
    && pip install --upgrade pip setuptools wheel

RUN pip install --index-url "${TORCH_INDEX_URL}" torch torchvision

# BUILD_VERSION is how upstream's setup.py stamps doctr.__version__; without it every release would
# report the development version of the branch it was cut from.
COPY --from=source /src/doctr /src/doctr
RUN BUILD_VERSION="${DOCTR_VERSION#v}" pip install /src/doctr

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

# The API template of the very same tag, so routes and library always match.
RUN mkdir -p /opt/doctr-api \
    && cp -r /src/doctr/api/app /opt/doctr-api/app
COPY server /opt/doctr-api/server

# ---------------------------------------------------------------------------------------------------
FROM build AS models

# Downloads the weights of the predictors the API builds with its default parameters, so the first
# request does not have to fetch them and the container works without internet access for them.
# Anything else (other architectures, layout/table models) is downloaded on first use.
ARG PRELOAD_MODELS=true
COPY scripts/preload_models.py /tmp/preload_models.py
RUN mkdir -p "${DOCTR_CACHE_DIR}" \
    && if [ "${PRELOAD_MODELS}" = "true" ]; then python /tmp/preload_models.py; fi

# ---------------------------------------------------------------------------------------------------
FROM models AS test

# A font with umlauts for the generated test images: Pillow's built-in font draws boxes for ä, ö, Ä, Ö.
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-test.txt /tmp/requirements-test.txt
RUN pip install -r /tmp/requirements-test.txt

COPY --from=source /src/doctr/api/tests /opt/doctr-api/upstream-tests
COPY tests /opt/doctr-api/tests
COPY scripts/image-tests.sh /usr/local/bin/image-tests.sh
COPY docker-entrypoint.sh /opt/doctr-api/docker-entrypoint.sh

ARG DOCTR_VERSION
WORKDIR /opt/doctr-api
ENV DEBUG=False \
    DOCTR_VERSION=${DOCTR_VERSION} \
    PYTHONPATH=/opt/doctr-api
RUN sh /usr/local/bin/image-tests.sh /out

# ---------------------------------------------------------------------------------------------------
FROM scratch AS test-results
COPY --from=test /out/ /

# ---------------------------------------------------------------------------------------------------
FROM base AS verified
COPY --from=test /out/exit-code /exit-code
RUN status="$(cat /exit-code)"; \
    if [ "${status}" != "0" ]; then \
        echo "Test suite failed (exit code ${status}); refusing to build the image." >&2; \
        exit 1; \
    fi

# ---------------------------------------------------------------------------------------------------
FROM base AS runtime

ARG DOCTR_VERSION
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="doctr-api" \
      org.opencontainers.image.description="docTR OCR as a ready-to-run REST API (FastAPI, CPU)" \
      org.opencontainers.image.source="https://github.com/ruepp-jenkins/docker-doctr-api" \
      org.opencontainers.image.url="https://hub.docker.com/r/ruepp/doctr-api" \
      org.opencontainers.image.version="${DOCTR_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="Apache-2.0"

# Ties the runtime image to a green test suite: BuildKit only builds what the target depends on,
# and this COPY is the dependency.
COPY --from=verified /exit-code /tmp/tests-passed

RUN groupadd --system --gid 1000 doctr \
    && useradd --system --uid 1000 --gid doctr --home-dir /opt/doctr --shell /usr/sbin/nologin doctr

COPY --from=build /opt/venv /opt/venv
COPY --from=build /opt/doctr-api /opt/doctr-api
COPY --from=models --chown=doctr:doctr /opt/doctr/cache /opt/doctr/cache
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENV DOCTR_VERSION=${DOCTR_VERSION} \
    PYTHONPATH=/opt/doctr-api \
    HOME=/opt/doctr \
    DEBUG=False \
    HOST=0.0.0.0 \
    PORT=8080 \
    WORKERS=1 \
    LOG_LEVEL=info \
    ROOT_PATH="" \
    FORWARDED_ALLOW_IPS="127.0.0.1" \
    CORS_ALLOW_ORIGINS="" \
    ALLOWED_HUB_MODELS="Felix92/doctr-torch-parseq-multilingual-v1" \
    DOCTR_MULTIPROCESSING_DISABLE=FALSE

WORKDIR /opt/doctr-api
USER doctr
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
