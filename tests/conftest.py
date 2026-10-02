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


# Installed in the Dockerfile's test stage. Pillow's built-in font has no glyphs for ä, ö, Ä, Ö.
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def _render(text: str, width: int = 1100) -> bytes:
    image = Image.new("RGB", (width, 200), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, 56)
    draw.text((40, 60), text, fill="black", font=font)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.fixture(scope="session")
def text_image() -> bytes:
    """A clean, generated document image, so the suite does not depend on external downloads."""
    return _render("HELLO WORLD")


@pytest.fixture(scope="session")
def german_image() -> bytes:
    """Letters the default `french` vocabulary lacks (no l/I-ambiguous words: sans-serif makes them identical)."""
    return _render("Müller GmbH, Übergröße")


@pytest.fixture(scope="session")
def cache_dir() -> str:
    return os.environ["DOCTR_CACHE_DIR"]
