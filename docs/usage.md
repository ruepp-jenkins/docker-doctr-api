# Usage

## Running the container

```bash
docker run -d \
  --name doctr-api \
  -p 8080:8080 \
  -v doctr-cache:/opt/doctr/cache \
  --restart unless-stopped \
  ruepp/doctr-api:latest
```

The API listens on port `8080`. The volume is optional — see [Configuration → Models and cache](configuration.md#models-and-cache).

Pin a release instead of `latest` for reproducible deployments:

```bash
docker run -d -p 8080:8080 ruepp/doctr-api:v1.1.0
```

## Docker Compose

```yaml
services:
  doctr-api:
    image: ruepp/doctr-api:latest
    container_name: doctr-api
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      WORKERS: "1"
      LOG_LEVEL: info
    volumes:
      - doctr-cache:/opt/doctr/cache

volumes:
  doctr-cache:
```

The same file is in the repository root as [`docker-compose.yml`](../docker-compose.yml).

### Behind a reverse proxy (sub-path)

When the proxy serves the API under a prefix such as `https://example.com/doctr/` **and strips that
prefix** before forwarding, set `ROOT_PATH` so the Swagger UI and the OpenAPI schema use the right URLs:

```yaml
    environment:
      ROOT_PATH: /doctr
      FORWARDED_ALLOW_IPS: "*"   # or the proxy's address
```

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/ocr/` | Full OCR: detection + recognition, optional orientation, language, layout and tables |
| `POST` | `/ocr/text` | Same OCR, **only the text** (JSON or `text/plain`) — added by this image |
| `POST` | `/detection/` | Text detection only (boxes or polygons) |
| `POST` | `/recognition/` | Text recognition of pre-cropped word images |
| `POST` | `/kie/` | Key information extraction (detected text grouped by class) |
| `GET` | `/health` | Liveness probe: `{"status":"ok","doctr_version":"…","image_version":"…"}` |
| `GET` | `/docs` | Swagger UI (`/` redirects here) |
| `GET` | `/openapi.json` | OpenAPI schema |

The four processing routes come unchanged from upstream's
[API template](https://github.com/mindee/doctr/tree/main/api). Their paths end with a slash; without it
the server answers with a `307` redirect, which `curl` only follows with `-L`. `/ocr/text` has no
trailing slash.

### Input

- Files are sent as `multipart/form-data`, in one or more fields named `files`.
- Supported content types: `image/jpeg`, `image/png`, `application/pdf` (every PDF page becomes one
  result). Anything else is answered with `400`.
- Model parameters are **query parameters**, e.g. `?det_arch=db_resnet50&detect_orientation=true`.
  All of them are listed with defaults in the Swagger UI.

Commonly used parameters of `/ocr/`:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `det_arch` | `db_resnet50` | Detection model, e.g. `fast_base`, `linknet_resnet18`, `db_mobilenet_v3_large` |
| `reco_arch` | `crnn_vgg16_bn` | Recognition model, e.g. `parseq`, `vitstr_small`, `crnn_mobilenet_v3_small` |
| `assume_straight_pages` | `true` | `false` returns rotated polygons instead of boxes |
| `detect_orientation` | `false` | Detect the page orientation |
| `straighten_pages` | `false` | Rotate pages upright before recognition |
| `detect_language` | `false` | Detect the page language |
| `detect_layout` / `detect_tables` | `false` | Layout regions / table structure (downloads extra models on first use) |
| `resolve_lines` / `resolve_blocks` | `true` / `false` | Group words into lines / blocks |
| `bin_thresh` / `box_thresh` | `0.1` / `0.1` | Detection thresholds. The API's `0.1` finds faint text but can also turn specks into stray characters; docTR's own default is `0.3`. |

Only the default `det_arch`/`reco_arch` and the multilingual Hub model (see
[German and other languages](#german-and-other-languages-umlauts-ß)) are baked into the image. Any other model is downloaded on its
first use — keep the cache volume so this happens only once.

## Text only: `/ocr/text`

`/ocr/` returns the full document tree — blocks, lines, words, geometries, scores. When you only need
the text (n8n, Zapier, scripts), use `POST /ocr/text`. It takes the same files and the same query
parameters, runs the same OCR, and lets docTR render the text in reading order.

```bash
curl -X POST "http://localhost:8080/ocr/text" -F "files=@scan.png;type=image/png"
```

```json
{
  "text": "Rechnung Nr. 4711\nMüller GmbH",
  "pages": [
    {"name": "scan.png", "page": 1, "text": "Rechnung Nr. 4711\nMüller GmbH"}
  ]
}
```

- `text`: all pages of all files, separated by a blank line
- `pages`: one entry per page; `page` counts within each file (a 3-page PDF gives pages 1–3)
- Lines are separated by `\n`, blocks by a blank line.

With `?format=plain` the answer is the bare text as `text/plain`:

```bash
curl -X POST "http://localhost:8080/ocr/text?format=plain" -F "files=@scan.pdf;type=application/pdf"
```

## German and other languages (umlauts, ß)

docTR has **no language parameter for recognition**. `detect_language=true` only *reports* the detected
language in the `/ocr/` response; it does not change what is recognized.

What decides which characters can be recognized is the recognition model. All built-in models
(`crnn_vgg16_bn`, `parseq`, `vitstr_*`, …) are trained on docTR's `french` vocabulary, which has no
`ä ö Ä Ö ß`. German text then comes back as `Muller GmbH, UbergroBe`.

docTR's maintainers publish a multilingual recognition model on the Hugging Face Hub that covers
German and most Latin-script European languages. It is baked into the image and can be selected on
`/ocr/text` via `reco_arch`:

```bash
curl -X POST "http://localhost:8080/ocr/text?reco_arch=Felix92/doctr-torch-parseq-multilingual-v1" \
  -F "files=@rechnung.pdf;type=application/pdf"
```

Measured on the same test image:

| Model | Result |
| --- | --- |
| `crnn_vgg16_bn` (default) | `Muller GmbH, UbergroBe` |
| `Felix92/doctr-torch-parseq-multilingual-v1` | `Müller GmbH, Übergröße` |

For German documents, always pass this `reco_arch`. Hub models work on `/ocr/text` only; the upstream
routes (`/ocr/`, `/recognition/`, …) accept built-in architectures only. Which Hub models may be
loaded is restricted by [`ALLOWED_HUB_MODELS`](configuration.md#server).

## n8n

**HTTP Request** node:

| Field | Value |
| --- | --- |
| Method | `POST` |
| URL | `http://doctr-api:8080/ocr/text` |
| Send Query Parameters | `reco_arch` = `Felix92/doctr-torch-parseq-multilingual-v1` (for German) |
| Send Body | on |
| Body Content Type | `Form-Data` |
| Parameter Type | `n8n Binary File` |
| Name | `files` |
| Input Data Field Name | `data` (the binary property holding the file) |
| Options → Timeout | e.g. `120000` ms — large PDFs take a while |

The result is one item; the text is in `{{ $json.text }}`.

- The binary's MIME type must be `image/jpeg`, `image/png` or `application/pdf`; anything else
  (e.g. `application/octet-stream`) is rejected with `400 Unsupported file format`.
- Only have Base64? Put a **Convert to File** node (operation *Move Base64 String to File*, option
  *MIME Type* set correctly, output field `data`) in front. Strip a `data:image/png;base64,` prefix
  first, e.g. with `{{ $json.image.split(',').pop() }}`.

### Examples

OCR of an image:

```bash
curl -X POST "http://localhost:8080/ocr/" \
  -H "accept: application/json" \
  -F "files=@scan.jpg;type=image/jpeg"
```

OCR of a PDF with orientation detection and rotated text:

```bash
curl -X POST "http://localhost:8080/ocr/?detect_orientation=true&assume_straight_pages=false" \
  -F "files=@contract.pdf;type=application/pdf"
```

Several files in one request:

```bash
curl -X POST "http://localhost:8080/ocr/" \
  -F "files=@page1.png;type=image/png" \
  -F "files=@page2.png;type=image/png"
```

Text detection only:

```bash
curl -X POST "http://localhost:8080/detection/?det_arch=db_resnet50" \
  -F "files=@scan.jpg;type=image/jpeg"
```

Python:

```python
import requests

with open("scan.jpg", "rb") as f:
    response = requests.post(
        "http://localhost:8080/ocr/",
        params={"detect_orientation": True},
        files=[("files", ("scan.jpg", f, "image/jpeg"))],
    )
response.raise_for_status()

for page in response.json():
    for block in page["items"][0]["blocks"]:
        for line in block["lines"]:
            print(" ".join(word["value"] for word in line["words"]))
```

### Response

`/ocr/` returns one object per page:

```json
[
  {
    "name": "scan.jpg",
    "orientation": {"value": null, "confidence": null},
    "language": {"value": null, "confidence": null},
    "dimensions": [1024, 768],
    "layout": [],
    "tables": [],
    "items": [
      {
        "blocks": [
          {
            "geometry": [0.12, 0.08, 0.53, 0.11],
            "objectness_score": 0.97,
            "lines": [
              {
                "geometry": [0.12, 0.08, 0.53, 0.11],
                "objectness_score": 0.97,
                "words": [
                  {
                    "value": "Invoice",
                    "geometry": [0.12, 0.08, 0.24, 0.11],
                    "objectness_score": 0.98,
                    "confidence": 0.99,
                    "crop_orientation": {"value": 0, "confidence": null}
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
]
```

Geometries are relative to the page size (`0.0`–`1.0`): `[xmin, ymin, xmax, ymax]` for straight
boxes, four `x, y` points for polygons (`assume_straight_pages=false`). Every response carries the
processing time in seconds in the `X-Process-Time` header.

## Performance notes

- The upstream template builds the predictor **per request** (loading the weights from the local
  cache). Expect a few seconds of overhead per call; this is upstream behaviour and kept unchanged.
- The image is CPU-only. Throughput scales with CPU cores; raise `WORKERS` for parallel requests —
  each worker holds its own models in memory (roughly 1–2 GB per busy worker with the defaults).
- Large PDFs are processed in one request. Put a request timeout on your reverse proxy that allows for
  that (minutes, not seconds).

## Health check

The image defines a Docker `HEALTHCHECK` against `GET /health`:

```bash
docker inspect --format '{{.State.Health.Status}}' doctr-api
```

For Kubernetes, use the same path for liveness and readiness probes.
