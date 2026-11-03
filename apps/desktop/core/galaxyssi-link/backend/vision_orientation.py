"""Bounded, in-memory orientation evidence; never alters or replaces the source image."""

import base64
import io
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

CAPTION = (
    "Orientation reference for source image 1, NOT additional user photos. "
    "The four panels show the SAME image at 0, 90, 180 and 270 degrees clockwise. "
    "Compare them before choosing a reading; use the original image for fine detail. "
    "Read connected content in its natural direction, not isolated strokes. "
    "Interpret handwriting by the complete expression, spacing and conventional notation; "
    "a curved numeral is not necessarily a parenthesis. Do not claim cropping or missing "
    "content when the strokes and surrounding page margins are fully visible. "
    "If alternatives remain plausible, state the ambiguity rather than inventing a transcription. "
    "Use historical images only when relevant to the latest request. Check orientation internally; "
    "do not prefix replies with orientation, rotation angles, or a reading report unless the user "
    "asks or a specific ambiguity matters to the answer."
)
MAX_BYTES = 100_000
MAX_SOURCE_BYTES = 20 * 1024 * 1024
MAX_SOURCE_PIXELS = 48_000_000
TILE = 640
HEADER = 32


def reference_sheet(path: str) -> bytes | None:
    source = Path(path)
    if not source.is_file() or source.stat().st_size > MAX_SOURCE_BYTES:
        return None
    with Image.open(source) as image:
        if image.width * image.height > MAX_SOURCE_PIXELS or getattr(image, "is_animated", False):
            return None
        image.draft("RGB", (TILE, TILE))
        with ImageOps.exif_transpose(image) as oriented:
            oriented.thumbnail((TILE, TILE), Image.Resampling.LANCZOS)
            with Image.new("RGB", (TILE * 2, (TILE + HEADER) * 2), "white") as sheet:
                draw = ImageDraw.Draw(sheet)
                for index, angle in enumerate((0, 90, 180, 270)):
                    x, y = index % 2 * TILE, index // 2 * (TILE + HEADER)
                    draw.text((x + 12, y + 10), f"Source 1 / {angle} deg clockwise", fill="black")
                    with oriented.rotate(-angle, expand=True) as view:
                        sheet.paste(view, (x + (TILE - view.width) // 2,
                                           y + HEADER + (TILE - view.height) // 2))
                for quality in (80, 60, 40, 25):
                    with io.BytesIO() as output:
                        sheet.save(output, "JPEG", quality=quality)
                        if output.tell() <= MAX_BYTES:
                            return output.getvalue()
    return None


def supplementary_input(image_paths: list[str]) -> list[dict]:
    if len(image_paths) != 1:
        return []
    try:
        encoded = reference_sheet(image_paths[0])
    except (OSError, ValueError, Image.DecompressionBombError):
        return []
    if not encoded:
        return []
    return [
        {"type": "text", "text": CAPTION, "text_elements": []},
        {"type": "image", "url": "data:image/jpeg;base64," + base64.b64encode(encoded).decode("ascii"),
         "detail": "original"},
    ]
