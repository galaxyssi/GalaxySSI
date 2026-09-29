"""Render task-local Office originals without reconstructing their layout."""

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import uuid
import zipfile
from pathlib import Path
from xml.etree import ElementTree

from task_workspace import task_workspace

TOOL = "galaxyssi_office_preview"
_SLOT = threading.BoundedSemaphore(1)
_MAIN = {".docx": "word/document.xml", ".xlsx": "xl/workbook.xml", ".pptx": "ppt/presentation.xml"}


def tool_spec():
    return {"type": "function", "name": TOOL,
            "description": "Render a saved DOCX/XLSX/PPTX in this task to PDF and PNG pages using an installed Office renderer. By default also publishes the unchanged editable original in outputs. Returns deliverable paths, hashes and page coverage. Use instead of writing ad-hoc Office export scripts. Never describes an unavailable render as verified.",
            "inputSchema": {"type": "object", "properties": {
                "path": {"type": "string", "description": "Absolute or task-relative path to the saved Office file."},
                "max_pages": {"type": "integer", "minimum": 1, "maximum": 20, "default": 8},
                "include_original": {"type": "boolean", "default": True,
                                     "description": "Keep true when native Office delivery is requested. Set false for preview-only or PDF-only output; this does not remove a source already in outputs."}},
                "required": ["path"], "additionalProperties": False}}


def _validated_source(root: Path, raw: str) -> Path:
    path = Path(raw)
    source = (path if path.is_absolute() else root / path).resolve(strict=True)
    if not source.is_relative_to(root) or source.suffix.lower() not in _MAIN or not source.is_file():
        raise ValueError("Office source must be a DOCX/XLSX/PPTX inside the current task workspace")
    if not 0 < source.stat().st_size <= 64 * 1024 * 1024:
        raise ValueError("Office source is empty or exceeds the preview size limit")
    with zipfile.ZipFile(source) as archive:
        names = archive.namelist()
        if len({name.casefold() for name in names}) != len(names):
            raise ValueError("Ambiguous duplicate Office container entries")
        if len(names) > 10000 or sum(i.file_size for i in archive.infolist()) > 256 * 1024 * 1024:
            raise ValueError("Office container exceeds preview expansion limits")
        if _MAIN[source.suffix.lower()] not in names or "[Content_Types].xml" not in names:
            raise ValueError("Invalid Office container")
        from office_chart_safety import passive_chart_workbooks
        passive_workbooks = passive_chart_workbooks(archive, source.suffix.lower())
        for name in names:
            lowered = name.lower()
            if (any(x in lowered for x in ("vbaproject", "/activex/")) or lowered == "xl/connections.xml"
                    or ("/embeddings/" in lowered and name not in passive_workbooks)):
                raise ValueError("Active or connected Office content is not supported by the preview worker")
            if lowered.endswith(".rels"):
                if archive.getinfo(name).file_size > 2 * 1024 * 1024:
                    raise ValueError("Office relationships exceed preview limits")
                data = archive.read(name)
                if len(data) > 2 * 1024 * 1024 or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
                    raise ValueError("Unsafe Office relationships")
                for relation in ElementTree.fromstring(data):
                    if relation.get("TargetMode", "").lower() == "external" and not relation.get("Type", "").endswith("/hyperlink"):
                        raise ValueError("External Office resources must be embedded before preview")
    return source


def _digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _convert(source: Path, pdf: Path, scratch: Path) -> str:
    libreoffice = shutil.which("soffice") or shutil.which("libreoffice")
    if libreoffice:
        result = subprocess.run([libreoffice, "-env:UserInstallation=" + (scratch / "lo-profile").as_uri(),
                                 "--headless", "--convert-to", "pdf", "--outdir", str(pdf.parent), str(source)],
                                capture_output=True, timeout=75)
        produced = pdf.parent / (source.stem + ".pdf")
        if result.returncode or not produced.is_file():
            raise RuntimeError("LibreOffice did not produce a PDF")
        produced.rename(pdf)
        return "libreoffice"
    powershell = shutil.which("powershell.exe") if os.name == "nt" else None
    if powershell:
        from office_preview_worker import convert
        convert(source, pdf, scratch, powershell)
        return "microsoft_office"
    raise RuntimeError("No supported Office renderer is installed")


def render(task_id: str, raw_path: str, max_pages: int = 8, *, include_original: bool = True) -> dict:
    if isinstance(max_pages, bool) or not isinstance(max_pages, int) or not 1 <= max_pages <= 20:
        raise ValueError("max_pages must be an integer from 1 to 20")
    if type(include_original) is not bool:
        raise ValueError("include_original must be a boolean")
    root = task_workspace(task_id).resolve()
    source = _validated_source(root, raw_path)
    rasterizer = shutil.which("pdftoppm")
    if not rasterizer:
        raise RuntimeError("PNG previews require the pdftoppm renderer on PATH")
    if not _SLOT.acquire(blocking=False):
        return {"status": "busy", "retryable": True, "reason": "Another Office preview is running"}
    try:
        before = _digest(source)
        output_name = source.stem[:100] + "-preview-" + uuid.uuid4().hex[:8]
        with tempfile.TemporaryDirectory(prefix="office-preview-", dir=root / "temp") as temporary:
            scratch = Path(temporary)
            copied = scratch / source.name
            shutil.copyfile(source, copied)
            if _digest(copied) != before:
                raise RuntimeError("Source changed while preparing its preview")
            _validated_source(root, str(copied))
            pages = scratch / "rendered"
            pages.mkdir()
            pdf = pages / (output_name + ".pdf")
            renderer = _convert(copied, pdf, scratch)
            if not pdf.is_file() or not 0 < pdf.stat().st_size <= 256 * 1024 * 1024:
                raise RuntimeError("Office renderer returned an invalid PDF")
            with pdf.open("rb") as stream:
                if stream.read(5) != b"%PDF-":
                    raise RuntimeError("Office renderer returned an invalid PDF")
            page_count = None
            if info := shutil.which("pdfinfo"):
                result = subprocess.run([info, str(pdf)], capture_output=True, text=True, timeout=15,
                                        env={**os.environ, "LC_ALL": "C"})
                match = re.search(r"^Pages:\s+(\d+)", result.stdout, re.MULTILINE)
                if result.returncode == 0 and match:
                    page_count = int(match.group(1))
            subprocess.run([rasterizer, "-png", "-scale-to", "1600", "-f", "1", "-l", str(max_pages),
                            str(pdf), str(pages / output_name)], capture_output=True, timeout=60, check=True)
            images = sorted(pages.glob("*.png"))
            if not images or any(p.stat().st_size == 0 for p in images):
                raise RuntimeError("PDF renderer returned no valid pages")
            for image in images:
                with image.open("rb") as stream:
                    if stream.read(8) != b"\x89PNG\r\n\x1a\n":
                        raise RuntimeError("PDF renderer returned an invalid PNG")
            if _digest(source) != before or _digest(copied) != before:
                raise RuntimeError("Source changed during rendering; preview was not published")
            original_in_outputs = source.is_relative_to(root / "outputs")
            if include_original and not original_in_outputs:
                shutil.copyfile(copied, pages / source.name)
                if _digest(pages / source.name) != before:
                    raise RuntimeError("Original copy failed integrity verification")
            target = root / "outputs" / output_name
            pages.rename(target)
            deliverables = sorted(target.iterdir())
            if include_original and original_in_outputs:
                deliverables.insert(0, source)
            return {"status": "rendered", "renderer": renderer, "source": source.relative_to(root).as_posix(),
                    "source_sha256": before, "page_count": page_count, "preview_pages": len(images),
                    "original_included": include_original,
                    "complete_preview": page_count is not None and len(images) == page_count,
                    "files": [{"path": str(p.relative_to(root)).replace("\\", "/"), "sha256": _digest(p),
                               "size_bytes": p.stat().st_size} for p in deliverables]}
    finally:
        _SLOT.release()


def execute(arguments: dict, task_id: str) -> dict:
    try:
        result = render(task_id, str(arguments.get("path", "")), arguments.get("max_pages", 8),
                        include_original=arguments.get("include_original", True))
    except Exception as error:
        result = {"status": "unavailable", "error": type(error).__name__, "reason": str(error)[-1000:],
                  "original_preserved": True}
    return {"success": result["status"] == "rendered", "contentItems": [
        {"type": "inputText", "text": json.dumps(result, ensure_ascii=False)}]}
