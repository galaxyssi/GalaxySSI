"""Single-pass encoding for latency-sensitive remote display frames."""

from io import BytesIO
from typing import Any

from image_transport import TransportImage


MAX_SCREENSHOT_BYTES = 100_000
SCREENSHOT_MAX_DIMENSION = 960
SCREENSHOT_JPEG_QUALITY = 60


def encode_desktop_screenshot(source: Any) -> TransportImage | None:
    from PIL import Image

    image = source.convert("RGB")
    try:
        image.thumbnail(
            (SCREENSHOT_MAX_DIMENSION, SCREENSHOT_MAX_DIMENSION),
            Image.Resampling.BILINEAR,
            reducing_gap=2.0,
        )
        with BytesIO() as output:
            # A single baseline encode replaces repeated size/quality searches.
            image.save(output, format="JPEG", quality=SCREENSHOT_JPEG_QUALITY,
                       subsampling=2, optimize=False, progressive=False)
            data = output.getvalue()
        if len(data) > MAX_SCREENSHOT_BYTES:
            return None
        return TransportImage(data, image.width, image.height)
    finally:
        image.close()
