"""OCR predictor for ``/ocr/text``, with optional recognition models from the Hugging Face Hub.

The default docTR recognition models are trained on the ``french`` vocabulary, which lacks ä, ö, ß
(and their capitals): German text comes back with those letters replaced or dropped. docTR's
maintainers publish multilingual models on the Hub, but upstream's ``init_predictor`` only accepts
built-in architecture names. Passing a Hub repository id as ``reco_arch`` is what this module adds.

Only repositories listed in ``ALLOWED_HUB_MODELS`` are loaded: a Hub checkpoint is a pickle, and an
API that downloads and unpickles whatever a request names would run arbitrary code.
"""

import os
from collections.abc import Callable

from app.schemas import OCRIn
from app.vision import _move_to_device, init_predictor
from doctr.models import from_hub, ocr_predictor

MULTILINGUAL_RECO_MODEL = "Felix92/doctr-torch-parseq-multilingual-v1"

ALLOWED_HUB_MODELS = frozenset(
    repo.strip()
    for repo in os.environ.get("ALLOWED_HUB_MODELS", MULTILINGUAL_RECO_MODEL).split(",")
    if repo.strip()
)


def is_hub_model(arch: str) -> bool:
    return "/" in arch


def build_ocr_predictor(request: OCRIn) -> Callable:
    """Upstream's ``init_predictor``, plus Hub repository ids as ``reco_arch``."""
    if not is_hub_model(request.reco_arch):
        return init_predictor(request)

    if request.reco_arch not in ALLOWED_HUB_MODELS:
        allowed = ", ".join(sorted(ALLOWED_HUB_MODELS)) or "none"
        raise ValueError(f"Hub model '{request.reco_arch}' is not allowed (ALLOWED_HUB_MODELS: {allowed})")

    params = request.model_dump()
    bin_thresh = params.pop("bin_thresh")
    box_thresh = params.pop("box_thresh")
    params["reco_arch"] = from_hub(params["reco_arch"])

    predictor = ocr_predictor(pretrained=True, **params)
    predictor.det_predictor.model.postprocessor.bin_thresh = bin_thresh
    predictor.det_predictor.model.postprocessor.box_thresh = box_thresh
    return _move_to_device(predictor)
