# Building

You only need this to change the image itself. To run it, pull `ruepp/doctr-api` — see [Usage](usage.md).

## Requirements

- Docker with BuildKit / `docker buildx` (Docker 23+)
- Internet access during the build (GitHub, PyPI, download.pytorch.org, Mindee's model storage)
- About 10 GB free disk space for the build cache

## Build locally

`DOCTR_VERSION` is required — it is the docTR release tag to package:

```bash
docker buildx build \
  --build-arg DOCTR_VERSION=v1.1.0 \
  --load \
  -t doctr-api:local \
  .

docker run --rm -p 8080:8080 doctr-api:local
```

The default target (`runtime`) runs the full test suite first and refuses to produce an image when it
fails.

To find the current release: `./scripts/resolve_version.sh` (prints e.g. `v1.1.0 true`).

### Build arguments

| Argument | Default | Description |
| --- | --- | --- |
| `DOCTR_VERSION` | *(required)* | docTR Git tag, e.g. `v1.1.0`. Library and API template are both taken from it. |
| `PYTHON_VERSION` | `3.12` | Tag of the `python:<version>-slim` base image. The upstream API supports 3.11 and 3.12. Keep it in sync with the URLTrigger in the `Jenkinsfile`. |
| `TORCH_INDEX_URL` | `https://download.pytorch.org/whl/cpu` | Package index for torch/torchvision. A CUDA index (e.g. `…/whl/cu124`) gives a GPU-capable amd64 image. |
| `PRELOAD_MODELS` | `true` | Bake the default models into the image. `false` gives a smaller image that downloads them on the first request. |
| `VCS_REF`, `BUILD_DATE` | `unknown` | Only written into the OCI labels. Set by `scripts/start.sh`. |

## Dockerfile stages

```
base ──► source ──► build ──► models ──► test ──► test-results   (JUnit export)
                                  │          └──► verified ──┐
                                  └──────────────────────────┴──► runtime   (published image)
```

| Stage | Purpose |
| --- | --- |
| `base` | `python:3.12-slim` + system libraries for OpenCV + `curl` for the health check |
| `source` | Shallow clone of `mindee/doctr` at `DOCTR_VERSION` |
| `build` | Virtualenv: CPU torch, docTR from source, FastAPI/uvicorn, upstream `api/app`, this repo's `server/` |
| `models` | Downloads the default model weights into `DOCTR_CACHE_DIR`, the multilingual Hub model into `HF_HOME` |
| `test` | Runs the tests (see below). Never fails; writes the verdict to `/out/exit-code` |
| `test-results` | Only the JUnit reports, for `--output type=local` |
| `verified` | Fails when the verdict is not `0` |
| `runtime` | Final image: non-root user, venv, app, models, entrypoint, health check |

## Tests

`scripts/image-tests.sh` runs inside the `test` stage, against exactly the environment that ends up in
the image:

| Suite | Source | Checks |
| --- | --- | --- |
| `upstream` | `api/tests` of the docTR release | All four routes with real models, expected results from upstream |
| `image` | [`tests/`](../tests) | `/health`, `/` redirect, OpenAPI routes, version stamp, baked-in models, OCR round trip on a generated image, rejected file types, `/ocr/text` (JSON, plain, German with the multilingual model, Hub allowlist) |
| `smoke` | `scripts/image-tests.sh` | Starts the real entrypoint and waits for `/health` over HTTP |

Run them and collect the JUnit reports without building the final image:

```bash
DOCTR_VERSION=v1.1.0 ./scripts/test.sh
cat test-results/exit-code      # 0 = green
ls test-results/*.junit.xml
```

The upstream tests download two sample images from GitHub, so the build needs internet access.

## Repository layout

| Path | Content |
| --- | --- |
| `Dockerfile` | The image |
| `docker-entrypoint.sh` | Turns the environment variables into the uvicorn command line |
| `server/main.py` | Wraps upstream's `app.main:app`: `/health`, CORS, `/` redirect |
| `server/text.py` | `POST /ocr/text` |
| `server/predictor.py` | Predictor for `/ocr/text`, Hub models as `reco_arch` (allowlisted) |
| `requirements.txt` | API runtime dependencies (from upstream `api/pyproject.toml`) |
| `requirements-test.txt` | Test dependencies, `test` stage only |
| `scripts/preload_models.py` | Downloads the default models at build time |
| `scripts/image-tests.sh` | Test runner inside the build |
| `scripts/*.sh` (rest) | CI scripts — see [CI/CD](ci.md) |
| `tests/` | This repository's tests |
| `docker-compose.yml` | Example deployment using the published image |
