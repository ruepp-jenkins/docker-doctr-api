# Versions and tags

## Tags

| Tag | Contains |
| --- | --- |
| `v1.1.0`, `v1.0.1`, … | Exactly that [docTR release](https://github.com/mindee/doctr/releases), library and API template from the same Git tag |
| `latest` | The newest docTR release (GitHub's *latest release*: no drafts, no pre-releases) |

The image tag is the upstream release tag, unchanged — including the leading `v`.

Every tag is a multi-arch manifest for `linux/amd64` and `linux/arm64`; Docker picks the right one.

## When images are (re)built

- **New docTR release** — the CI checks GitHub every 30 minutes. A new release is built, tested and
  published under its tag and as `latest`.
- **New Python base image** — when `python:3.12-slim` is republished (security fixes), the current
  release is rebuilt and its tag is **overwritten** with the patched image.
- **Changes in this repository** — rebuild the current release, same tag.

So a tag always names the docTR version, while the image behind it can be refreshed. Pin by digest
(`ruepp/doctr-api@sha256:…`) if you need a byte-identical image.

Releases from before this image existed are not built automatically; they can be built on demand
(see [CI/CD → Building a specific release](ci.md#building-a-specific-release)). Very old releases
may not be compatible with the packaging.

## Which version is running?

```bash
curl -s http://localhost:8080/health
# {"status":"ok","doctr_version":"1.1.0","image_version":"v1.1.0"}

docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' ruepp/doctr-api:latest
```

The labels also carry the commit of this repository (`org.opencontainers.image.revision`) and the
build time (`org.opencontainers.image.created`).

## Contents of an image

| Component | Source |
| --- | --- |
| docTR library | `mindee/doctr` at the release tag, installed from source |
| API (`/ocr`, `/detection`, …) | `api/app` of the same tag, unchanged |
| Additions (`/ocr/text`, Hub models, `/health`, CORS, `/` redirect, entrypoint) | this repository, [`server/`](../server) |
| Multilingual recognition model | [`Felix92/doctr-torch-parseq-multilingual-v1`](https://huggingface.co/Felix92/doctr-torch-parseq-multilingual-v1), current at build time |
| PyTorch / torchvision | latest CPU wheels at build time |
| FastAPI, uvicorn, python-multipart | latest versions at build time (see [`requirements.txt`](../requirements.txt)) |
| Python | `python:3.12-slim` (Debian) |
