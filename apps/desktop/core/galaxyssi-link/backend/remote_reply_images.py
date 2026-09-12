"""Materialize explicit reply images as scoped, replayable task artifacts."""
from __future__ import annotations

import hashlib
import io
import json
import os
import re
import tempfile
import threading
import time
import warnings
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

from markdown_it import MarkdownIt
from markdown_it.rules_inline import image as image_rule
from PIL import Image

from remote_image_transport import ImageDownloadError, MAX_IMAGE_BYTES, PublicImageTransport, remaining
from task_workspace import task_artifact_path, task_workspace

MAX_IMAGES = 8
MAX_PIXELS = 32_000_000
DOWNLOAD_SECONDS = 30.0
_POOL = ThreadPoolExecutor(max_workers=4, thread_name_prefix="reply-image")
_SLOTS = threading.BoundedSemaphore(12)
_LOCKS = [threading.Lock() for _ in range(64)]
_CONTENT_LOCKS = [threading.Lock() for _ in range(64)]
_FORMATS = {"JPEG": ("jpg", "image/jpeg"), "PNG": ("png", "image/png"),
            "WEBP": ("webp", "image/webp"), "GIF": ("gif", "image/gif"), "AVIF": ("avif", "image/avif")}


@dataclass(frozen=True)
class PreparedReplyImages:
    content: str
    files: tuple[dict, ...] = ()
    failures: tuple[dict, ...] = ()

    def include_files(self, output_files):
        files = {item["relative_path"]: dict(item) for item in output_files}
        files.update({item["relative_path"]: dict(item) for item in self.files})
        return list(files.values())


def _digest(value: str | bytes) -> str:
    return hashlib.sha256(value.encode() if isinstance(value, str) else value).hexdigest()


def _image_with_position(state, silent):
    start, count = state.pos, len(state.tokens)
    found = image_rule(state, silent)
    if found and not silent and len(state.tokens) > count:
        state.tokens[-1].meta["reply_image_span"] = (start, state.pos)
    return found


def _image_spans(source):
    parser = MarkdownIt("commonmark")
    parser.inline.ruler.at("image", _image_with_position)
    offsets, total = [0], 0
    for line in source.splitlines(keepends=True):
        total += len(line)
        offsets.append(total)
    for block in parser.parse(source):
        if block.type != "inline" or not block.map:
            continue
        start, end = offsets[block.map[0]], offsets[min(block.map[1], len(offsets) - 1)]
        # Locate each normalized inline line inside its original block, preserving list/quote prefixes.
        positions, cursor = [], start
        for line in block.content.splitlines(keepends=True):
            text = line.rstrip("\n")
            at = source.find(text, cursor, end)
            if at < 0:
                positions = []
                break
            positions.extend(range(at, at + len(text)))
            cursor = at + len(text)
            if line.endswith("\n"):
                newline = source.find("\n", cursor, end)
                if newline < 0:
                    positions = []
                    break
                positions.append(newline)
                cursor = newline + 1
        for token in block.children or []:
            span = token.meta.get("reply_image_span") if token.type == "image" else None
            url = token.attrGet("src") or ""
            if span and positions and span[1] <= len(positions) and url.lower().startswith(("http://", "https://")):
                yield positions[span[0]], positions[span[1] - 1] + 1, url, token.content or "Image"


def _validate_image(data):
    if not 0 < len(data) <= MAX_IMAGE_BYTES:
        raise ImageDownloadError("image_too_large")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                if image.format not in _FORMATS or image.width * image.height > MAX_PIXELS:
                    raise ImageDownloadError("unsupported_image")
                extension, mime = _FORMATS[image.format]
                image.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
        return extension, mime
    except (OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
        if isinstance(error, ImageDownloadError):
            raise
        raise ImageDownloadError("invalid_image_data") from error


def _explicit_documents(source):
    from rich_output import _is_image_uri
    offsets = [0]
    for line in source.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    for token in MarkdownIt("commonmark").parse(source):
        if token.type != "fence" or token.info.strip().lower() != "galaxyssi-rich" or not token.map:
            continue
        try:
            document = json.loads(token.content)
            blocks = document.get("blocks", []) if isinstance(document, dict) else document
            if not isinstance(blocks, list):
                continue
            expanded = []
            for block in blocks:
                if not isinstance(block, dict) or block.get("type") != "gallery":
                    expanded.append(block)
                    continue
                rows = ([ [block["uri"], block.get("title", "Image")] ] if block.get("uri") else [])
                rows += [row for row in block.get("rows", []) if isinstance(row, list) and row]
                remote, local = [], []
                for row in rows:
                    if str(row[0]).startswith(("https://", "http://")):
                        remote.append({"type": "image", "uri": row[0],
                                       "title": row[1] if len(row) > 1 else block.get("title", "Image")})
                    else:
                        local.append(row)
                if remote:
                    expanded.extend(remote)
                    if local:
                        expanded.append({**block, "uri": "", "rows": local})
                else:
                    expanded.append(block)
            blocks[:] = expanded
            images = [block for block in blocks if isinstance(block, dict)
                      and (block.get("type") == "image" or (block.get("type") in ("file", "webpage")
                           and _is_image_uri(str(block.get("uri", "")), str(block.get("mime_type", "")))))
                      and not block.get("data_b64") and str(block.get("uri", "")).startswith(("https://", "http://"))]
            if images:
                yield offsets[token.map[0]], offsets[token.map[1]], document, images
        except (ValueError, TypeError):
            continue


def image_link_preview(content: str) -> str:
    """Progress may expose source links, but must not ask the phone to fetch image bytes."""
    if "![" not in content and "galaxyssi-rich" not in content:
        return content
    source = content.replace("\r\n", "\n")
    edits = [(start, start + 1, "") for start, _, _, _ in _image_spans(source)]
    for start, end, document, blocks in _explicit_documents(source):
        for block in blocks:
            block["type"] = "link"
            block.pop("mime_type", None)
        edits.append((start, end, "```galaxyssi-rich\n" + json.dumps(document, ensure_ascii=False) + "\n```\n"))
    for start, end, replacement in sorted(edits, reverse=True):
        source = source[:start] + replacement + source[end:]
    return source


def _failure_text(code, chinese):
    if code.startswith("image_http_"):
        return ("\u56fe\u7247\u6765\u6e90\u62d2\u7edd\u8bbf\u95ee" if chinese else "Image source rejected the request") + f" ({code.rsplit('_', 1)[-1]})"
    if "timeout" in code or "busy" in code:
        return "\u56fe\u7247\u4e0b\u8f7d\u8d85\u65f6\u6216\u670d\u52a1\u7e41\u5fd9\uff0c\u8bf7\u91cd\u8bd5" if chinese else "Image download timed out or is busy; retry later"
    return "\u56fe\u7247\u4e0b\u8f7d\u6216\u9a8c\u8bc1\u5931\u8d25" if chinese else "Image download or validation failed"


def _atomic_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, prefix=".", delete=False) as file:
        temporary = Path(file.name)
        json.dump(value, file, ensure_ascii=True)
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _download(task_id, scope_key, url, label, deadline, transport):
    key = _digest(scope_key + url)
    lock = _LOCKS[int(key[:8], 16) % len(_LOCKS)]
    if not lock.acquire(timeout=remaining(deadline)):
        raise ImageDownloadError("image_download_timeout")
    try:
        # Resolve existing directories under a short lock; Windows non-strict
        # resolution can change path prefixes while another worker creates them.
        with _CONTENT_LOCKS[int(_digest(task_id)[:8], 16) % len(_CONTENT_LOCKS)]:
            root = task_workspace(task_id).resolve(strict=True)
            directory = root
            for component in ("outputs", "web-images", scope_key):
                directory = directory / component
                if directory.is_symlink():
                    raise ImageDownloadError("unsafe_image_output")
                directory.mkdir(exist_ok=True)
                if not directory.resolve(strict=True).is_relative_to(root):
                    raise ImageDownloadError("unsafe_image_output")
        record_path = directory / ("." + key + ".json")
        if record_path.exists():
            record = json.loads(record_path.read_text(encoding="utf-8"))
            source = task_artifact_path(task_id, record["relative_path"])
            if (record.get("source_url") != url or source is None
                    or source.stat().st_size > MAX_IMAGE_BYTES or _digest(source.read_bytes()) != record["sha256"]):
                raise ImageDownloadError("image_source_changed")
            return record
        data = transport.fetch(url, deadline=deadline, max_bytes=MAX_IMAGE_BYTES)
        extension, mime = _validate_image(data)
        remaining(deadline)
        digest = _digest(data)
        destination = directory / (digest + "." + extension)
        with _CONTENT_LOCKS[int(digest[:8], 16) % len(_CONTENT_LOCKS)]:
            if destination.exists():
                if destination.is_symlink() or destination.stat().st_size != len(data) or _digest(destination.read_bytes()) != digest:
                    raise ImageDownloadError("image_source_changed")
            else:
                with tempfile.NamedTemporaryFile(dir=directory, prefix=".", delete=False) as file:
                    temporary = Path(file.name)
                    file.write(data)
                try:
                    os.replace(temporary, destination)
                finally:
                    temporary.unlink(missing_ok=True)
        name = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", label).strip()[:80] or "Image"
        record = {"name": name + "." + extension, "relative_path": destination.relative_to(root).as_posix(),
                  "category": "outputs", "size": len(data), "mime_type": mime, "sha256": digest,
                  "source_url": url}
        _atomic_json(record_path, record)
        return record
    finally:
        lock.release()


def prepare_reply_images(task_id: str, content: str, *, scope: dict, transport=None,
                         budget_seconds=DOWNLOAD_SECONDS) -> PreparedReplyImages:
    source = str(content or "").replace("\r\n", "\n")
    if "![" not in source and "galaxyssi-rich" not in source:
        return PreparedReplyImages(content)
    if (not task_id or scope.get("task_id") != task_id
            or any(not scope.get(key) for key in ("client_route_id", "conversation_id", "turn_id", "source_message_id"))
            or type(scope.get("execution_generation")) is not int or scope["execution_generation"] < 1):
        return PreparedReplyImages(image_link_preview(content), failures=({"error_code": "missing_image_delivery_scope"},))
    source_spans = list(_image_spans(source))
    documents = list(_explicit_documents(source))
    candidates = [(url, label) for _, _, url, label in source_spans]
    candidates += [(str(block["uri"]), str(block.get("title") or "Image"))
                   for _, _, _, blocks in documents for block in blocks]
    if not candidates:
        return PreparedReplyImages(content)
    scope_key = _digest(json.dumps(scope, sort_keys=True) + _digest(source))[:32]
    deadline = time.monotonic() + max(0.1, min(budget_seconds, 60))
    downloader = transport or PublicImageTransport()
    futures, outcomes, failures = {}, {}, {}
    for url, label in dict(candidates).items():
        if len(futures) >= MAX_IMAGES:
            failures[url] = "image_count_limit"
            continue
        if not _SLOTS.acquire(timeout=max(0, deadline - time.monotonic())):
            failures[url] = "image_download_busy"
            continue
        try:
            future = _POOL.submit(_download, task_id, scope_key, url, label, deadline, downloader)
            future.add_done_callback(lambda _: _SLOTS.release())
            futures[url] = future
        except BaseException:
            _SLOTS.release()
            raise
    for url, future in futures.items():
        try:
            outcomes[url] = future.result(timeout=0 if future.done() else remaining(deadline))
        except (ImageDownloadError, FutureTimeout, OSError, ValueError, KeyError) as error:
            future.cancel()
            failures[url] = error.code if isinstance(error, ImageDownloadError) else "image_download_failed"
    chinese = any("\u4e00" <= char <= "\u9fff" for char in source)
    edits = []
    seen = set()
    for start, end, url, label in source_spans:
        record = outcomes.get(url)
        if record:
            replacement = "" if url in seen else f"![Image]({record['relative_path']})"
        else:
            clean_label = label.replace("[", "").replace("]", "")
            reason = _failure_text(failures.get(url, "image_download_failed"), chinese)
            replacement = f"{reason}: [{clean_label}](<{url}>)"
        edits.append((start, end, replacement))
        seen.add(url)
    for start, end, document, blocks in documents:
        for block in blocks:
            url = block["uri"]
            record = outcomes.get(url)
            if record:
                block["type"] = "image"
                block["uri"] = f"galaxyssi-artifact://{quote(task_id, safe='')}/{record['relative_path']}"
                block["mime_type"] = record["mime_type"]
                block["metadata"] = {"source_url": url}
            else:
                block.clear()
                block.update(type="link", uri=url, title=_failure_text(failures[url], chinese))
        edits.append((start, end, "```galaxyssi-rich\n" + json.dumps(document, ensure_ascii=False) + "\n```\n"))
    for start, end, replacement in sorted(edits, reverse=True):
        source = source[:start] + replacement + source[end:]
    files = {record["relative_path"]: record for record in outcomes.values()}
    return PreparedReplyImages(source, tuple(files.values()), tuple({"source_url": url, "error_code": code}
                                                                  for url, code in failures.items()))
