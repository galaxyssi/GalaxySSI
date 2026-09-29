"""Narrow preview exception for passive XLSX data owned by a PPTX chart."""
from io import BytesIO
import posixpath
import re
import zipfile
from xml.etree import ElementTree as ET
from urllib.parse import unquote

_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
_CHART = "http://schemas.openxmlformats.org/drawingml/2006/chart"
_SHEET = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
_CT = "http://schemas.openxmlformats.org/package/2006/content-types"
_REL_XML = "http://schemas.openxmlformats.org/package/2006/relationships"
_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml."
_PARTS = {
    "_rels/.rels": "application/vnd.openxmlformats-package.relationships+xml",
    "xl/_rels/workbook.xml.rels": "application/vnd.openxmlformats-package.relationships+xml",
    "xl/workbook.xml": _XLSX + "sheet.main+xml",
    "xl/styles.xml": _XLSX + "styles+xml",
    "xl/sharedStrings.xml": _XLSX + "sharedStrings+xml",
    "xl/theme/theme1.xml": "application/vnd.openxmlformats-officedocument.theme+xml",
    "docProps/core.xml": "application/vnd.openxmlformats-package.core-properties+xml",
    "docProps/app.xml": "application/vnd.openxmlformats-officedocument.extended-properties+xml",
}
_SAFE_RELS = {_REL + part for part in ("officeDocument", "worksheet", "styles", "sharedStrings", "theme", "extended-properties")}
_SAFE_RELS.add("http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties")
_FORBIDDEN = {"f", "definedName", "externalReference", "oleObject", "control", "webPublishItem", "connection", "queryTable", "ddeLink"}


def _xml(archive, name):
    if archive.getinfo(name).file_size > 4 * 1024 * 1024:
        raise ValueError("Chart XML exceeds preview limit")
    raw = archive.read(name)
    if b"\x00" in raw or b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("Unsafe chart XML")
    return ET.fromstring(raw)


def _target(owner, target):
    if not target or any(c in target for c in ("\\", "%", ":", "#", "?")) or target.startswith("/"):
        raise ValueError("Invalid chart package target")
    result = posixpath.normpath(posixpath.join(posixpath.dirname(owner), target))
    if result.startswith("../"):
        raise ValueError("Chart package target escapes container")
    return result


def _validate_workbook(data):
    with zipfile.ZipFile(BytesIO(data)) as book:
        names = book.namelist()
        expanded = sum(item.file_size for item in book.infolist())
        if len(names) > 512 or expanded > 32 * 1024 * 1024 or len({n.casefold() for n in names}) != len(names):
            raise ValueError("Embedded chart workbook exceeds limits or has duplicate entries")
        if not {"[Content_Types].xml", "xl/workbook.xml", "_rels/.rels"}.issubset(names):
            raise ValueError("Invalid chart workbook")
        types = _xml(book, "[Content_Types].xml")
        if types.tag != f"{{{_CT}}}Types":
            raise ValueError("Invalid chart workbook content types")
        defaults, overrides = {}, {}
        for item in types:
            if item.tag == f"{{{_CT}}}Default":
                key = item.get("Extension", "")
                if key in defaults:
                    raise ValueError("Duplicate workbook content type")
                defaults[key] = item.get("ContentType")
            elif item.tag == f"{{{_CT}}}Override":
                key = item.get("PartName", "")
                if key in overrides:
                    raise ValueError("Duplicate workbook content type")
                overrides[key] = item.get("ContentType")
            else:
                raise ValueError("Unexpected workbook content type")
        for name in names:
            if name == "[Content_Types].xml":
                continue
            expected = _PARTS.get(name)
            if re.fullmatch(r"xl/worksheets/sheet[1-9][0-9]*\.xml", name):
                expected = _XLSX + "worksheet+xml"
            if expected is None or overrides.get("/" + name, defaults.get(name.rsplit(".", 1)[-1])) != expected:
                raise ValueError("Only passive chart workbook parts are supported")
            tree = _xml(book, name)
            if any(node.tag.rsplit("}", 1)[-1] in _FORBIDDEN
                   or node.tag.rsplit("}", 1)[-1].lower().startswith("formula") for node in tree.iter()):
                raise ValueError("Chart workbooks must contain data only, without formulas or active content")
            if name == "xl/workbook.xml" and tree.tag != f"{{{_SHEET}}}workbook":
                raise ValueError("Invalid chart workbook root")
            if name.startswith("xl/worksheets/") and tree.tag != f"{{{_SHEET}}}worksheet":
                raise ValueError("Invalid chart worksheet root")
            if name.endswith(".rels"):
                if tree.tag != f"{{{_REL_XML}}}Relationships":
                    raise ValueError("Invalid chart workbook relationships")
                owner = "xl/workbook.xml" if name.startswith("xl/") else ""
                for relation in tree:
                    if (relation.tag != f"{{{_REL_XML}}}Relationship" or relation.get("TargetMode", "Internal") != "Internal"
                            or relation.get("Type") not in _SAFE_RELS
                            or _target(owner, relation.get("Target", "")) not in names):
                        raise ValueError("Unsafe chart workbook relationship")
        return expanded


def passive_chart_workbooks(archive, suffix):
    embedded = {name for name in archive.namelist() if "/embeddings/" in name.lower()}
    if not embedded or suffix != ".pptx":
        return set()
    approved, total = set(), 0
    for name in archive.namelist():
        if not name.endswith(".rels"):
            continue
        owner = posixpath.join(posixpath.dirname(posixpath.dirname(name)), posixpath.basename(name)[:-5])
        relationships = _xml(archive, name)
        ids = [item.get("Id") for item in relationships]
        if len(ids) != len(set(ids)):
            raise ValueError("Ambiguous Office relationships")
        for relation in relationships:
            if relation.get("TargetMode", "Internal") != "Internal":
                continue
            raw_target = relation.get("Target", "")
            decoded = unquote(raw_target).replace("\\", "/")
            target = posixpath.normpath(decoded.lstrip("/") if decoded.startswith("/") else
                                       posixpath.join(posixpath.dirname(owner), decoded))
            if target not in embedded:
                continue
            _target(owner, raw_target)
            if (not re.fullmatch(r"ppt/charts/chart[1-9][0-9]*\.xml", owner)
                    or relation.get("Type") != _REL + "package"
                    or not re.fullmatch(r"ppt/embeddings/[^/]+\.xlsx", target)):
                raise ValueError("Only chart-owned XLSX data can be previewed")
            chart = _xml(archive, owner)
            external = chart.findall(f"{{{_CHART}}}externalData")
            if (chart.tag != f"{{{_CHART}}}chartSpace" or len(external) != 1
                    or external[0].get(f"{{{_REL[:-1]}}}id") != relation.get("Id")
                    or any(node.get("val", "") not in ("0", "false") for node in external[0].findall(f"{{{_CHART}}}autoUpdate"))):
                raise ValueError("Chart data relationship is not passive")
            if target not in approved:
                if archive.getinfo(target).file_size > 8 * 1024 * 1024:
                    raise ValueError("Embedded chart workbook is too large")
                total += _validate_workbook(archive.read(target))
                if total > 64 * 1024 * 1024:
                    raise ValueError("Embedded chart data exceeds total preview limit")
                approved.add(target)
    if approved != embedded:
        raise ValueError("Unreferenced or unsupported embedded Office object")
    return approved
