# Configuration

Everything is configured through environment variables. None is required — the defaults start the API
on port `8080`.

## Environment variables

### Server

| Variable | Default | Description |
| --- | --- | --- |
| `HOST` | `0.0.0.0` | Address uvicorn binds to inside the container. |
| `PORT` | `8080` | Port uvicorn listens on. Change the published port (`-p 9000:8080`) rather than this, unless you need to. The health check follows this value. |
| `WORKERS` | `1` | Number of uvicorn worker processes. Each one loads its own models — plan the memory accordingly. |
| `LOG_LEVEL` | `info` | uvicorn log level: `critical`, `error`, `warning`, `info`, `debug`, `trace`. |
| `ROOT_PATH` | *(empty)* | Path prefix when running behind a reverse proxy that strips it, e.g. `/doctr`. Used for the URLs in Swagger UI and OpenAPI. |
| `FORWARDED_ALLOW_IPS` | `127.0.0.1` | Proxies whose `X-Forwarded-*` headers are trusted. Set it to the proxy's IP, or `*` on a private network. |
| `CORS_ALLOW_ORIGINS` | *(empty)* | Comma-separated origins allowed to call the API from a browser, e.g. `https://app.example.com,https://admin.example.com`. Empty disables CORS; `*` allows every origin. |
| `ALLOWED_HUB_MODELS` | `Felix92/doctr-torch-parseq-multilingual-v1` | Comma-separated Hugging Face Hub repositories `/ocr/text` accepts as `reco_arch`. Hub checkpoints are pickles — only list repositories you trust. Empty disables Hub models. |
| `DEBUG` | `False` | FastAPI debug mode (tracebacks in error responses). The upstream template defaults to *on*; the image switches it off. Only set it to `True` for debugging. |

### docTR

| Variable | Default | Description |
| --- | --- | --- |
| `DOCTR_CACHE_DIR` | `/opt/doctr/cache` | Where docTR stores downloaded model weights. The baked-in default models live here. |
| `HF_HOME` | `/opt/doctr/cache/huggingface` | Cache of models loaded from the Hugging Face Hub. Inside the cache volume on purpose. |
| `HF_TOKEN` | *(unset)* | Optional Hugging Face token. Only raises the Hub's rate limits; the baked-in model needs none. |
| `DOCTR_MULTIPROCESSING_DISABLE` | `FALSE` | `TRUE` disables docTR's internal multiprocessing (useful with a small `/dev/shm` or strict memory limits). |

### Informational (set by the image, do not change)

| Variable | Example | Description |
| --- | --- | --- |
| `DOCTR_VERSION` | `v1.1.0` | docTR release the image was built from. Also reported by `/health`. |

## Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| `8080` | HTTP | REST API, Swagger UI, health check |

There is no TLS in the container. Terminate HTTPS at a reverse proxy.

## Models and cache

The image contains the weights the API needs for its **default** parameters:

- detection `db_resnet50`
- recognition `crnn_vgg16_bn`
- page and crop orientation classifiers
- the multilingual recognition model `Felix92/doctr-torch-parseq-multilingual-v1` (Hugging Face Hub,
  stored under `HF_HOME`) — see [Usage → German](usage.md#german-and-other-languages-umlauts-ß)

Anything else — another `det_arch`/`reco_arch`, `detect_layout`, `detect_tables`, … — is downloaded
from Mindee's model storage on its first use and stored in `DOCTR_CACHE_DIR`. Without a volume those
downloads are lost when the container is recreated.

Mount a **named volume** at `/opt/doctr/cache`:

```bash
docker run -d -p 8080:8080 -v doctr-cache:/opt/doctr/cache ruepp/doctr-api
```

On first use Docker copies the baked-in models into an empty named volume, so nothing is downloaded
again.

A **bind mount** (`-v ./models:/opt/doctr/cache`) hides the baked-in models instead; they are then
downloaded on the first request. The directory has to be writable by UID `1000`:

```bash
mkdir -p models && sudo chown 1000:1000 models
```

Note: when you update to a newer image, an existing named volume keeps its old content. docTR
identifies checkpoints by file name including a hash, so newer releases simply add files; delete the
volume occasionally if you want to reclaim the space.

### Offline operation

With the default parameters the container needs no internet access at runtime. Requests that need a
model that is not in the cache fail when the download is impossible.

## User and permissions

The API runs as user `doctr` (UID/GID `1000`), not as root. `docker run --user` works as long as the
cache directory is writable by that user, or as long as only the baked-in models are used.

## Resources

Rough guide for the default models on CPU:

| | |
| --- | --- |
| Memory | ~1.5 GB per worker under load; more for large PDFs or layout/table detection |
| CPU | Uses all available cores per request; limit with `--cpus` if the host is shared |
| `/dev/shm` | The Docker default (64 MB) is usually enough; raise `--shm-size` or set `DOCTR_MULTIPROCESSING_DISABLE=TRUE` if workers crash on large batches |

## GPU

The image ships CPU-only PyTorch and does not use a GPU, even with `--gpus`. The upstream code would
pick CUDA up automatically, so a GPU variant only needs a different `TORCH_INDEX_URL` at build time —
see [Building](building.md#build-arguments).
