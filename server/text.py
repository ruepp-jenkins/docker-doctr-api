"""``POST /ocr/text``: the upstream OCR route, reduced to the recognized text.

Upstream's ``/ocr/`` answers with the full document tree (blocks, lines, words, geometries, scores),
which is what you want for layout work and far too much when all you need is the text — e.g. in an
n8n or Zapier workflow. This route takes the same files and the same query parameters, runs the same
predictor, and lets docTR render the text itself (``Page.render()``, reading order included).

``reco_arch`` additionally accepts allowed Hugging Face Hub models — see ``server/predictor.py``.
"""

from enum import Enum

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from app.schemas import OCRIn
from app.utils import get_documents
from server.predictor import build_ocr_predictor

router = APIRouter()

# Between two pages (or two files) in the combined `text`.
PAGE_BREAK = "\n\n"


class TextFormat(str, Enum):
    json = "json"
    plain = "plain"


class PageText(BaseModel):
    name: str = Field(..., examples=["scan.pdf"])
    page: int = Field(..., description="1-based page number within its file", examples=[1])
    text: str = Field(..., examples=["Invoice 2026\nTotal: 42.00 EUR"])


class TextOut(BaseModel):
    text: str = Field(..., description="Text of all pages of all files", examples=["Invoice 2026\nTotal: 42.00 EUR"])
    pages: list[PageText]


@router.post(
    "/text",
    response_model=TextOut,
    summary="Perform OCR, return only the text",
    responses={200: {"content": {"text/plain": {"example": "Invoice 2026\nTotal: 42.00 EUR"}}}},
)
async def ocr_text(
    request: OCRIn = Depends(),
    files: list[UploadFile] = [File(...)],
    format: TextFormat = Query(TextFormat.json, description="`json` (default) or `plain` for text/plain"),
):
    """Runs the same OCR as `/ocr/` and returns only the recognized text, per page and combined.

    For German (ä, ö, ß) and other non-French Latin scripts set
    `reco_arch=Felix92/doctr-torch-parseq-multilingual-v1`.
    """
    try:
        content, filenames = await get_documents(files)
        predictor = build_ocr_predictor(request)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # The predictor is CPU-bound and synchronous; off the event loop, /health keeps answering while
    # a large PDF is processed.
    out = await run_in_threadpool(predictor, content)

    pages: list[PageText] = []
    page_in_file: dict[str, int] = {}
    for name, page in zip(filenames, out.pages):
        page_in_file[name] = page_in_file.get(name, 0) + 1
        pages.append(PageText(name=name, page=page_in_file[name], text=page.render().strip()))

    text = PAGE_BREAK.join(p.text for p in pages if p.text)

    if format is TextFormat.plain:
        return PlainTextResponse(text)
    return TextOut(text=text, pages=pages)
