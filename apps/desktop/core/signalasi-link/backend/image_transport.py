"""Shared image encoding for bounded phone/Desktop transport."""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any


MAX_IMAGE_TRANSPORT_BYTES = 100_000
_PREFERRED_MIN_JPEG_QUALITY = 45
_MAX_JPEG_QUALITY = 92
_FALLBACK_JPEG_QUALITIES = (40, 34, 28, 22, 18)
_MAX_DIMENSIONS = (2400, 2160, 1920, 1680, 1440, 1280, 1120, 960, 800, 640, 480, 360)


@dataclass(frozen=True)
class TransportImage:
    data: bytes
    width: int
    height: int
    mime_type: str = "image/jpeg"


def compress_image_file(source: Path, byte_limit: int = MAX_IMAGE_TRANSPORT_BYTES) -> TransportImage | None:
    from PIL import Image, ImageOps

    with Image.open(source) as opened:
        oriented = ImageOps.exif_transpose(opened)
        try:
            return compress_pil_image(oriented, byte_limit)
        finally:
            if oriented is not opened:
                oriented.close()


def compress_pil_image(image: Any, byte_limit: int = MAX_IMAGE_TRANSPORT_BYTES) -> TransportImage | None:
    limit = min(max(1, int(byte_limit)), MAX_IMAGE_TRANSPORT_BYTES)
    normalized = _flatten_for_jpeg(image)
    try:
        seen_sizes: set[tuple[int, int]] = set()
        for max_dimension in _MAX_DIMENSIONS:
            resized = _fit_image(normalized, max_dimension)
            try:
                size = tuple(resized.size)
                if size in seen_sizes:
                    continue
                seen_sizes.add(size)
                candidate = _best_jpeg_within_limit(
                    resized,
                    limit,
                    _PREFERRED_MIN_JPEG_QUALITY,
                    _MAX_JPEG_QUALITY,
                )
                if candidate:
                    return TransportImage(candidate, size[0], size[1])
            finally:
                if resized is not normalized:
                    resized.close()

        smallest = _fit_image(normalized, _MAX_DIMENSIONS[-1])
        try:
            for quality in _FALLBACK_JPEG_QUALITIES:
                candidate = _encode_jpeg(smallest, quality)
                if len(candidate) <= limit:
                    return TransportImage(candidate, smallest.width, smallest.height)
        finally:
            if smallest is not normalized:
                smallest.close()
        return None
    finally:
        normalized.close()


def _flatten_for_jpeg(image: Any):
    from PIL import Image

    if image.mode == "RGB":
        return image.copy()
    if image.mode == "L":
        return image.convert("RGB")
    converted = image.convert("RGBA")
    background = Image.new("RGB", converted.size, "white")
    background.paste(converted, mask=converted.getchannel("A"))
    converted.close()
    return background


def _fit_image(image: Any, max_dimension: int):
    from PIL import Image

    width, height = image.size
    largest = max(width, height)
    if largest <= max_dimension:
        return image
    scale = max_dimension / float(largest)
    target = (max(1, round(width * scale)), max(1, round(height * scale)))
    return image.resize(target, Image.Resampling.LANCZOS)


def _best_jpeg_within_limit(image: Any, limit: int, minimum_quality: int, maximum_quality: int) -> bytes:
    low = minimum_quality
    high = maximum_quality
    best = b""
    while low <= high:
        quality = (low + high) // 2
        candidate = _encode_jpeg(image, quality)
        if len(candidate) <= limit:
            best = candidate
            low = quality + 1
        else:
            high = quality - 1
    return best


def _encode_jpeg(image: Any, quality: int) -> bytes:
    output = BytesIO()
    image.save(output, format="JPEG", quality=quality, optimize=True, progressive=True)
    return output.getvalue()
