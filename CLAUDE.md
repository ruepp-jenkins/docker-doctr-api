# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Packaging repository: builds the Docker image `ruepp/doctr-api` that runs [mindee/doctr](https://github.com/mindee/doctr)'s FastAPI template (`api/` folder upstream) as a ready-to-run OCR REST API. No docTR code lives here — it is cloned at build time from a release tag.

Languages: project content (code, comments, docs, commit messages) is **English**; the user may prompt in German or English.

Documentation split: `README.md` = what the image is + quick start; everything else in `docs/` (`usage.md`, `configuration.md`, `versions.md`, `building.md`, `ci.md`). Examples in docs/compose must use the published image (`ruepp/doctr-api:<tag>`), never `build:`. Keep the env var tables in `docs/configuration.md` in sync with the `ENV` block in the `Dockerfile` and `docker-entrypoint.sh`.

## Commands

`DOCTR_VERSION` (an upstream Git tag such as `v1.1.0`) is a required build arg everywhere. `./scripts/resolve_version.sh` prints the latest release (`v1.1.0 true`).

```bash
# Full image (runs the whole test suite first; fails if tests fail)
docker buildx build --build-arg DOCTR_VERSION=v1.1.0 --load -t doctr-api:local .
docker run --rm -p 8080:8080 doctr-api:local

# Test suite only, JUnit reports + exit-code into ./test-results (what CI does)
DOCTR_VERSION=v1.1.0 ./scripts/test.sh

# Single test: build the `test` stage once, then mount local sources over the baked-in ones
docker buildx build --build-arg DOCTR_VERSION=v1.1.0 --target test --load -t doctr-api:test .
docker run --rm -v "$PWD/tests:/opt/doctr-api/tests:ro" -v "$PWD/server:/opt/doctr-api/server:ro" \
  doctr-api:test python -m pytest -p no:cacheprovider tests/test_server.py::test_health
```

There is no local Python toolchain/venv; tests only run inside the image build. In the docker-code sandbox the inner Docker daemon's bridge DNS is broken — add `--network host` to `docker buildx build`/`docker run` there (environment quirk, not a project requirement; do not bake it into scripts).

Shell syntax check: `bash -n scripts/*.sh && sh -n docker-entrypoint.sh`.

## Architecture

**Release fidelity is the core invariant.** The image must contain exactly the upstream release tag, never `main`:
- `Dockerfile` stage `source` does `git clone --branch "${DOCTR_VERSION}"`; library (`pip install /src/doctr` with `BUILD_VERSION` stamping `doctr.__version__`), `api/app` and `api/tests` all come from that one checkout.
- Upstream's `api/pyproject.toml` pins `python-doctr@main` and has changed format between releases (poetry → PEP 621), so it is deliberately **not** used; API deps are in our `requirements.txt`.

**Upstream code is never patched.** `server/main.py` imports upstream's `app.main:app` and adds `/health`, optional CORS (`CORS_ALLOW_ORIGINS`), `/` → `/docs`, and `POST /ocr/text` (`server/text.py`: same params as `/ocr/`, returns only `Page.render()` text). `/ocr/text` uses `server/predictor.py`, which additionally accepts Hugging Face Hub repo ids as `reco_arch`, restricted to `ALLOWED_HUB_MODELS` (Hub checkpoints are pickles). Reason: all built-in recognition models use the `french` vocab (no ä/ö/ß); `Felix92/doctr-torch-parseq-multilingual-v1` handles German and is preloaded into `HF_HOME` (inside the cache dir). Generated test images need a real font (`fonts-dejavu-core`, test stage only) — Pillow's built-in font renders umlauts as boxes. The entrypoint runs `uvicorn server.main:app`. Upstream builds a predictor per request (slow, intentional to leave as-is) and defaults `DEBUG` to on — the image sets `DEBUG=False`.

**Dockerfile stage chain:** `base → source → build → models → test → test-results | verified → runtime`. `models` pre-downloads default weights (`db_resnet50`, `crnn_vgg16_bn`, orientation classifiers) into `DOCTR_CACHE_DIR=/opt/doctr/cache` via `scripts/preload_models.py`. `test` runs `scripts/image-tests.sh`, which **never fails** (so JUnit can always be exported) and writes `/out/exit-code`; `verified` fails on non-zero, and `runtime` `COPY --from=verified` to make the published image depend on green tests. Three suites: `upstream` (release's `api/tests`, needs internet), `image` (our `tests/`), `smoke` (real entrypoint + curl `/health`). Torch comes from the CPU wheel index (`TORCH_INDEX_URL`) — amd64 and arm64 both supported.

**CI (Jenkinsfile + scripts/), derived from a shared template used by other ruepp-jenkins repos:**
- `Prepare` resolves the version **once** (`resolve_version.sh` → `env.DOCTR_VERSION`, `env.DOCTR_IS_LATEST`) so both agents build the same release. Manual override via job parameter `DOCTR_VERSION_OVERRIDE` (named differently because Jenkins params shadow `env` assignments).
- `Build` runs amd64 (agent label `docker`) and arm64 (`oracle_docker`) natively in parallel; each pushes **by digest, untagged** (`start.sh`) and stashes `digest-<arch>.txt`. `docker_platforms.sh` verifies the agent's real arch against `EXPECTED_PLATFORM`.
- `Manifest` (`docker_manifest.sh`) joins the digests with `buildx imagetools create` — the only step that creates tags.
- Tags (`docker_tags.sh`): main/master → `ruepp/doctr-api:<upstream tag incl. v>` plus `latest` only when `DOCTR_IS_LATEST=true`; other branches → `ruepp/doctr-api-test:<branch>-<tag>`. Rebuilds overwrite the version tag.
- `URLTrigger` polls GitHub `releases/latest` (`$.tag_name`) and Docker Hub `python/tags/3.12-slim` (`$.digest`). The Python tag must match the Dockerfile's `PYTHON_VERSION` default — change both together.

## Conventions

- Comments explain *why* (often at length, especially in CI scripts); match that style.
- CI scripts deliberately avoid extra agent dependencies: parse JSON with `sed`, not `jq`. Agents need only Docker, git and curl.
- Registry credentials are bound with `withCredentials` only around the steps that log in; don't move them into the global `environment` block.
