"""Tests for what this image adds on top of the upstream API template."""

import os

import pytest

import doctr


@pytest.mark.asyncio
async def test_health(client):
    response = await client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["doctr_version"] == doctr.__version__


@pytest.mark.asyncio
async def test_root_redirects_to_docs(client):
    response = await client.get("/", follow_redirects=False)
    assert response.status_code in (302, 307)
    assert response.headers["location"].endswith("/docs")


@pytest.mark.asyncio
async def test_openapi_lists_upstream_and_image_routes(client):
    response = await client.get("/openapi.json")
    assert response.status_code == 200
    paths = response.json()["paths"]
    for path in ("/ocr/", "/ocr/text", "/detection/", "/recognition/", "/kie/", "/health"):
        assert path in paths, f"{path} missing from the OpenAPI schema"


def test_doctr_version_matches_build(cache_dir):
    expected = os.environ.get("DOCTR_VERSION", "").lstrip("v")
    if expected:
        assert doctr.__version__ == expected


def test_default_models_are_baked_in(cache_dir):
    models_dir = os.path.join(cache_dir, "models")
    assert os.path.isdir(models_dir), f"{models_dir} does not exist"
    checkpoints = os.listdir(models_dir)
    for prefix in ("db_resnet50", "crnn_vgg16_bn"):
        assert any(name.startswith(prefix) for name in checkpoints), f"{prefix} not preloaded: {checkpoints}"

    hub_dir = os.path.join(os.environ["HF_HOME"], "hub")
    assert os.path.isdir(os.path.join(hub_dir, "models--Felix92--doctr-torch-parseq-multilingual-v1")), (
        f"multilingual model not preloaded: {os.listdir(hub_dir) if os.path.isdir(hub_dir) else hub_dir}"
    )


@pytest.mark.asyncio
async def test_ocr_reads_generated_text(client, text_image):
    files = [("files", ("hello.png", text_image, "image/png"))]
    response = await client.post("/ocr", files=files)
    assert response.status_code == 200
    pages = response.json()
    assert len(pages) == 1
    words = [
        word["value"].upper()
        for block in pages[0]["items"][0]["blocks"]
        for line in block["lines"]
        for word in line["words"]
    ]
    assert "HELLO" in words and "WORLD" in words, words


@pytest.mark.asyncio
async def test_unsupported_file_is_rejected(client):
    files = [("files", ("note.txt", b"plain text", "text/plain"))]
    response = await client.post("/ocr", files=files)
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_ocr_text_json(client, text_image):
    files = [("files", ("hello.png", text_image, "image/png"))]
    response = await client.post("/ocr/text", files=files)
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"text", "pages"}
    assert "HELLO" in body["text"].upper() and "WORLD" in body["text"].upper(), body
    assert body["pages"] == [{"name": "hello.png", "page": 1, "text": body["text"]}]


@pytest.mark.asyncio
async def test_ocr_text_plain(client, text_image):
    files = [("files", ("hello.png", text_image, "image/png"))]
    response = await client.post("/ocr/text", params={"format": "plain"}, files=files)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "HELLO" in response.text.upper()


@pytest.mark.asyncio
async def test_ocr_text_numbers_pages_per_file(client, text_image):
    files = [
        ("files", ("a.png", text_image, "image/png")),
        ("files", ("b.png", text_image, "image/png")),
    ]
    response = await client.post("/ocr/text", files=files)
    assert response.status_code == 200
    pages = response.json()["pages"]
    assert [(p["name"], p["page"]) for p in pages] == [("a.png", 1), ("b.png", 1)]


@pytest.mark.asyncio
async def test_ocr_text_german_with_multilingual_model(client, german_image):
    files = [("files", ("de.png", german_image, "image/png"))]
    response = await client.post(
        "/ocr/text", params={"reco_arch": "Felix92/doctr-torch-parseq-multilingual-v1"}, files=files
    )
    assert response.status_code == 200
    text = response.json()["text"]
    assert "Müller" in text and "Übergröße" in text, text


@pytest.mark.asyncio
async def test_ocr_text_rejects_unlisted_hub_model(client, text_image):
    files = [("files", ("hello.png", text_image, "image/png"))]
    response = await client.post("/ocr/text", params={"reco_arch": "someone/untrusted-model"}, files=files)
    assert response.status_code == 400
    assert "not allowed" in response.json()["detail"]
