"""Download the weights the API uses with its default request parameters.

Runs during the image build (Dockerfile stage `models`). Building the predictors is enough: docTR
stores every downloaded checkpoint in DOCTR_CACHE_DIR and reuses it from there afterwards.
"""

from doctr.models import kie_predictor, ocr_predictor

# Defaults of the upstream API schemas (api/app/schemas.py): db_resnet50 + crnn_vgg16_bn. Building
# the full OCR predictor also fetches the page and crop orientation classifiers.
ocr_predictor(det_arch="db_resnet50", reco_arch="crnn_vgg16_bn", pretrained=True)
kie_predictor(det_arch="db_resnet50", reco_arch="crnn_vgg16_bn", pretrained=True)

print("Default models downloaded")
