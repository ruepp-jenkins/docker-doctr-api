# doctr-api

[docTR](https://github.com/mindee/doctr) by Mindee as a **ready-to-run OCR REST API** in a Docker image.

Upstream docTR is a Python library; its `api/` folder contains a FastAPI template you are expected to
check out and build yourself. This image does that for you: it packages a docTR release together with
the API template of the same release and starts the API as soon as the container runs.

- **Image:** [`ruepp/doctr-api`](https://hub.docker.com/r/ruepp/doctr-api)
- **Source:** [ruepp-jenkins/docker-doctr-api](https://github.com/ruepp-jenkins/docker-doctr-api)
- **Platforms:** `linux/amd64`, `linux/arm64`
- **Tags:** the upstream release tag (e.g. `v1.1.0`) and `latest`

## What you get

- The upstream API template, unchanged: `/ocr`, `/detection`, `/recognition`, `/kie`
- `/ocr/text` — the same OCR, but only the text (JSON or plain), e.g. for n8n
- German (ä, ö, ü, ß) and other Latin scripts via a baked-in multilingual model
- Interactive API docs (Swagger UI) at `/docs`, OpenAPI schema at `/openapi.json`
- `GET /health` and a Docker `HEALTHCHECK`
- Default models (`db_resnet50`, `crnn_vgg16_bn`, orientation classifiers) baked in — the first
  request does not download anything
- CPU-only PyTorch, running as an unprivileged user (UID 1000)
- Configuration through environment variables (port, workers, CORS, reverse-proxy path, …)
- Automatic rebuilds on every new docTR release and every new Python base image

## Quick start

```bash
docker run -d --name doctr-api -p 8080:8080 ruepp/doctr-api:latest
```

Open <http://localhost:8080/docs>, or send a document:

```bash
# Full result with geometries
curl -X POST http://localhost:8080/ocr/ -F "files=@invoice.pdf;type=application/pdf"

# Only the text, German umlauts included
curl -X POST "http://localhost:8080/ocr/text?format=plain&reco_arch=Felix92/doctr-torch-parseq-multilingual-v1" \
  -F "files=@rechnung.pdf;type=application/pdf"
```

With Docker Compose, use the [`docker-compose.yml`](docker-compose.yml) in this repository:

```bash
docker compose up -d
```

## Documentation

| Topic | |
| --- | --- |
| [Usage](docs/usage.md) | Running the container, Compose, endpoints, `/ocr/text`, German text, n8n |
| [Configuration](docs/configuration.md) | Environment variables, ports, volumes, models |
| [Versions and tags](docs/versions.md) | Which tag contains what, how releases are picked up |
| [Building](docs/building.md) | Building the image locally, the test suite |
| [CI/CD](docs/ci.md) | The Jenkins pipeline, release monitoring, multi-arch publishing |

## License

docTR and its API template are licensed under the
[Apache License 2.0](https://github.com/mindee/doctr/blob/main/LICENSE) by Mindee. This repository
only contains the packaging around it.
