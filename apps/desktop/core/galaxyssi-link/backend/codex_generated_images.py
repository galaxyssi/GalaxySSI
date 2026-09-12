"""Turn-scoped native Codex images materialized for the existing artifact transport."""
from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import re
import tempfile
import warnings
from pathlib import Path

from PIL import Image

from task_workspace import task_artifact_path, task_workspace

MAX_IMAGE_BYTES = 12 * 1024 * 1024
MAX_PIXELS = 32_000_000
MAX_IMAGES = 8
_ID = re.compile(r"[A-Za-z0-9_-]{1,160}\Z")
_FORMATS = {"PNG": "png", "JPEG": "jpg", "WEBP": "webp"}


class GeneratedImageError(ValueError):
    pass


def is_generated_image(item: dict) -> bool:
    return item.get("type") == "imageGeneration" or (
        item.get("type") == "Extension" and item.get("kind") == "image_gen.generation"
    )


def _identity(task_id, thread_id, turn_id, item_id):
    values = (task_id, thread_id, turn_id, item_id)
    if not all(isinstance(value, str) and _ID.fullmatch(value) for value in values):
        raise GeneratedImageError("invalid_image_identity")
    return dict(zip(("task_id", "thread_id", "turn_id", "item_id"), values))


def _image_extension(data):
    if not 0 < len(data) <= MAX_IMAGE_BYTES:
        raise GeneratedImageError("image_size_limit")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                extension = _FORMATS.get(image.format)
                if not extension or image.width * image.height > MAX_PIXELS:
                    raise GeneratedImageError("unsupported_image")
                image.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
        return extension
    except GeneratedImageError:
        raise
    except Exception as exc:
        raise GeneratedImageError("invalid_image") from exc


def _read_image(item, thread_id, item_id, codex_home):
    encoded = item.get("result")
    if isinstance(encoded, str) and encoded:
        if len(encoded) > ((MAX_IMAGE_BYTES + 2) // 3) * 4 + 64:
            raise GeneratedImageError("image_size_limit")
        if encoded.startswith("data:"):
            header, separator, encoded = encoded.partition(",")
            if not separator or header not in (
                "data:image/png;base64", "data:image/jpeg;base64", "data:image/webp;base64"
            ):
                raise GeneratedImageError("invalid_image_encoding")
        try:
            return base64.b64decode(encoded, validate=True)
        except ValueError as exc:
            raise GeneratedImageError("invalid_image_encoding") from exc
    saved_path = item.get("savedPath")
    if not isinstance(saved_path, str) or not saved_path:
        raise GeneratedImageError("generated_image_missing")
    root = (Path(codex_home) / "generated_images" / thread_id).resolve()
    source = Path(saved_path)
    # A tool-supplied path is not authority to read another turn's or user's file.
    if source.is_symlink() or source.resolve().parent != root or source.stem != item_id:
        raise GeneratedImageError("generated_image_path_out_of_scope")
    if source.suffix.lower().lstrip(".") not in _FORMATS.values():
        raise GeneratedImageError("unsupported_image")
    try:
        with source.open("rb") as stream:
            return stream.read(MAX_IMAGE_BYTES + 1)
    except OSError as exc:
        raise GeneratedImageError("generated_image_missing") from exc


def _atomic_write(path, data):
    if path.is_symlink():
        raise GeneratedImageError("image_output_path_out_of_scope")
    descriptor, temporary = tempfile.mkstemp(prefix=".image-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def capture_image(task_id: str, thread_id: str, turn_id: str, item: dict,
                  *, codex_home: str | Path) -> dict:
    scope = _identity(task_id, thread_id, turn_id, str(item.get("id") or ""))
    if not is_generated_image(item):
        raise GeneratedImageError("not_generated_image")
    if item.get("failure") or str(item.get("status") or "completed").lower() != "completed":
        raise GeneratedImageError("image_generation_failed")
    data = _read_image(item, thread_id, scope["item_id"], codex_home)
    extension = _image_extension(data)
    digest = hashlib.sha256(data).hexdigest()
    key = hashlib.sha256(json.dumps(scope, sort_keys=True).encode()).hexdigest()[:24]
    workspace = task_workspace(task_id, "codex")
    outputs = workspace / "outputs"
    if outputs.is_symlink() or outputs.resolve().parent != workspace.resolve():
        raise GeneratedImageError("image_output_path_out_of_scope")
    filename = f"generated-image-{key}.{extension}"
    target = outputs / filename
    if target.is_symlink():
        raise GeneratedImageError("image_output_path_out_of_scope")
    if (not target.exists() or target.stat().st_size != len(data)
            or hashlib.sha256(target.read_bytes()).hexdigest() != digest):
        _atomic_write(target, data)
    receipt = {**scope, "relative_path": f"outputs/{filename}", "name": filename,
               "category": "outputs", "size": len(data), "sha256": digest}
    _atomic_write(workspace / f".codex-image-{key}.json",
                  json.dumps(receipt, sort_keys=True).encode("utf-8"))
    return receipt


def verified_images(task_id: str, thread_id: str, turn_id: str) -> list[dict]:
    _identity(task_id, thread_id, turn_id, "receipt")
    workspace = task_workspace(task_id, "codex")
    images = []
    for path in sorted(workspace.glob(".codex-image-*.json"))[:256]:
        try:
            if path.is_symlink() or path.stat().st_size > 4096:
                continue
            receipt = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(receipt, dict):
                continue
            _identity(receipt.get("task_id"), receipt.get("thread_id"),
                      receipt.get("turn_id"), receipt.get("item_id"))
            if any(receipt.get(key) != value for key, value in (
                ("task_id", task_id), ("thread_id", thread_id), ("turn_id", turn_id)
            )):
                continue
            source = task_artifact_path(task_id, receipt.get("relative_path", ""))
            if source is None or not 0 < source.stat().st_size <= MAX_IMAGE_BYTES:
                continue
            data = source.read_bytes()
            if len(data) != receipt.get("size") or hashlib.sha256(data).hexdigest() != receipt.get("sha256"):
                continue
            _image_extension(data)
            images.append(receipt)
            if len(images) >= MAX_IMAGES:
                break
        except (OSError, ValueError, TypeError):
            continue
    return images


def capture_run_image(run, item, codex_home):
    key = str(item.get("id") or "missing")
    try:
        if key not in run.generated_images and len(run.generated_images) >= MAX_IMAGES:
            raise GeneratedImageError("image_count_limit")
        # Replayed terminal events may omit bytes, but must refer to a verified receipt.
        if key in run.generated_images and not item.get("result") and not item.get("savedPath"):
            if item.get("failure") or str(item.get("status") or "completed") != "completed":
                raise GeneratedImageError("image_generation_failed")
            run.generated_image_errors.pop(key, None)
            return
        run.generated_images[key] = capture_image(
            run.task_id, run.thread_id, run.turn_id, item, codex_home=codex_home)
        run.generated_image_errors.pop(key, None)
    except (GeneratedImageError, OSError) as exc:
        run.generated_image_errors[key] = str(exc) if isinstance(exc, GeneratedImageError) else "image_save_failed"


def finalize_run_images(run, turn, codex_home) -> str:
    for item in turn.get("items") or []:
        if isinstance(item, dict) and is_generated_image(item):
            capture_run_image(run, item, codex_home)
    if not run.generated_images and not run.generated_image_errors:
        return ""
    images = []
    # A controlled replan may change turn_id within the same task. Verify the
    # original turn binding of each captured result, never another task's files.
    try:
        for turn_id in sorted({item["turn_id"] for item in run.generated_images.values()}):
            images.extend(verified_images(run.task_id, run.thread_id, turn_id))
    except (OSError, GeneratedImageError):
        run.generated_image_errors["verification"] = "image_verification_failed"
    expected = {(item["turn_id"], item["item_id"], item["sha256"])
                for item in run.generated_images.values()}
    images = [item for item in images if (item["turn_id"], item["item_id"], item["sha256"]) in expected]
    # Receipt filenames are hashes, not the order in which the images were created.
    order = {(item["turn_id"], item["item_id"]): index
             for index, item in enumerate(run.generated_images.values())}
    images.sort(key=lambda item: order[(item["turn_id"], item["item_id"])])
    if run.generated_image_errors or len(images) != len(expected):
        message = ("\u56fe\u7247\u751f\u6210\u7ed3\u679c\u672a\u80fd\u4fdd\u5b58\u4e3a\u53ef\u4ea4\u4ed8\u9644\u4ef6\uff0c\u8bf7\u91cd\u8bd5\u3002" if run.prefers_chinese else
                   "The generated image could not be saved as a deliverable attachment. Please retry.")
        run.final_text = message
        return message
    links = []
    seen = set()
    for item in images:
        if item["sha256"] in seen:
            continue
        seen.add(item["sha256"])
        target = f"galaxyssi-artifact://{run.task_id}/{item['relative_path']}"
        if target not in run.final_text:
            label = "\u751f\u6210\u7684\u56fe\u7247" if run.prefers_chinese else "Generated image"
            links.append(f"![{label}]({target})")
    if links:
        run.final_text = "\n\n".join(filter(None, [run.final_text, *links]))
    return ""
