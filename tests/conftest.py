import io
import os

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from PIL import Image, ImageDraw, ImageFont

from server.main import app


@pytest_asyncio.fixture(scope="function")
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test", follow_redirects=True) as ac:
        yield ac


@pytest.fixture(scope="session")
def text_image() -> bytes:
    """A clean, generated document image, so the suite does not depend on external downloads."""
    image = Image.new("RGB", (800, 200), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=64)
    draw.text((40, 60), "HELLO WORLD", fill="black", font=font)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.fixture(scope="session")
def cache_dir() -> str:
    return os.environ["DOCTR_CACHE_DIR"]
