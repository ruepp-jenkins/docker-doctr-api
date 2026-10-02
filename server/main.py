"""Entry point of the image.

Wraps the upstream FastAPI template (``app.main:app`` from doctr's ``api/`` folder) without changing
it, and adds what a long-running container needs on top:

* ``GET /health`` for the Docker HEALTHCHECK and orchestrators,
* optional CORS, configured through ``CORS_ALLOW_ORIGINS``,
* a redirect from ``/`` to the Swagger UI,
* ``POST /ocr/text``, the OCR result as plain text (see ``server/text.py``).
"""

import os

import doctr
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

from app.main import app
from server import text

IMAGE_VERSION = os.environ.get("DOCTR_VERSION", doctr.__version__)


app.include_router(text.router, prefix="/ocr", tags=["ocr"])


@app.get("/health", tags=["health"], summary="Liveness probe")
async def health() -> dict[str, str]:
    """Answers as soon as the server accepts requests. Does not load any model."""
    return {"status": "ok", "doctr_version": doctr.__version__, "image_version": IMAGE_VERSION}


@app.get("/", include_in_schema=False)
async def root() -> RedirectResponse:
    return RedirectResponse(url=app.docs_url or "/docs")


_origins = [origin.strip() for origin in os.environ.get("CORS_ALLOW_ORIGINS", "").split(",") if origin.strip()]
if _origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["X-Process-Time"],
    )

# The upstream template caches its OpenAPI schema on first access; routes added here are registered
# before any request arrives, so they are part of it.
__all__ = ["app"]
