"""Read-only, conservative XLSX drawing/print-area diagnostics, not visual QA."""

import posixpath
import zipfile
from xml.etree import ElementTree as ET

_S = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
_D = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
_P = "http://schemas.openxmlformats.org/package/2006/relationships"


def _xml(archive, name):
    if archive.getinfo(name).file_size > 4 * 1024 * 1024:
        raise ValueError("layout_part_too_large")
    data = archive.read(name)
    if b"\x00" in data or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("unsupported_layout_xml")
    return ET.fromstring(data)


def _relations(archive, owner):
    path = posixpath.join(posixpath.dirname(owner), "_rels", posixpath.basename(owner) + ".rels")
    result = {}
    for item in _xml(archive, path).findall(f"{{{_P}}}Relationship"):
        target, identity = item.get("Target", ""), item.get("Id")
        if (not identity or identity in result or not target
                or item.get("TargetMode", "").lower() == "external"
                or any(c in target for c in ("\\", "%", ":", "?", "#"))):
            raise ValueError("unsupported_layout_relationship")
        resolved = posixpath.normpath(target.lstrip("/") if target.startswith("/")
                                     else posixpath.join(posixpath.dirname(owner), target))
        if resolved.startswith("../") or resolved == "..":
            raise ValueError("layout_relationship_outside_package")
        result[identity] = (item.get("Type"), resolved)
    return result


def _marker(anchor, tag):
    marker = anchor.find(f"{{{_D}}}{tag}")
    if marker is None:
        raise ValueError("missing_drawing_marker")
    values = tuple(int(marker.findtext(f"{{{_D}}}{key}", "-1"))
                   for key in ("col", "colOff", "row", "rowOff"))
    if any(v < 0 for v in values) or values[0] > 16384 or values[2] > 1048576:
        raise ValueError("unsupported_drawing_marker")
    return values[:2], values[2:]


def inspect_print_layout(source):
    result = {"scope": "explicit_xlsx_print_areas_and_two_cell_drawings",
              "status": "not_applicable", "checked_drawings": 0, "issues": [],
              "unverified": [], "visual_review_required": True}
    if source.suffix.lower() != ".xlsx":
        return result
    result["status"] = "partial"
    try:
        from openpyxl.workbook.defined_name import DefinedName
        from openpyxl.utils.cell import range_boundaries
        with zipfile.ZipFile(source) as archive:
            book = _xml(archive, "xl/workbook.xml")
            relations = _relations(archive, "xl/workbook.xml")
            areas = {}
            for definition in book.findall(f"{{{_S}}}definedNames/{{{_S}}}definedName"):
                if definition.get("name") != "_xlnm.Print_Area":
                    continue
                index = int(definition.get("localSheetId", "-1"))
                destinations = list(DefinedName(name="_xlnm.Print_Area", attr_text=definition.text).destinations)
                if not destinations:
                    raise ValueError("dynamic_print_area")
                for sheet_name, reference in destinations:
                    bounds = range_boundaries(reference)
                    if any(v is None for v in bounds):
                        raise ValueError("non_rectangular_print_area")
                    areas.setdefault(index, []).append((sheet_name.replace("''", "'"), bounds))
            for index, sheet in enumerate(book.findall(f"{{{_S}}}sheets/{{{_S}}}sheet")):
                if sheet.get("state", "visible") != "visible":
                    continue
                kind, path = relations[sheet.get(f"{{{_R}}}id")]
                if kind != _R + "/worksheet":
                    result["unverified"].append("non_worksheet_sheet")
                    continue
                for drawing in _xml(archive, path).findall(f"{{{_S}}}drawing"):
                    kind, drawing_path = _relations(archive, path)[drawing.get(f"{{{_R}}}id")]
                    if kind != _R + "/drawing":
                        raise ValueError("unsupported_drawing_relationship")
                    rectangles = [b for name, b in areas.get(index, []) if name == sheet.get("name")]
                    if not rectangles:
                        result["unverified"].append("drawing_without_static_print_area")
                        continue
                    for anchor in _xml(archive, drawing_path):
                        client = anchor.find(f"{{{_D}}}clientData")
                        if client is not None and client.get("fPrintsWithSheet") in ("0", "false"):
                            continue
                        if anchor.tag != f"{{{_D}}}twoCellAnchor":
                            result["unverified"].append("unsupported_drawing_anchor")
                            continue
                        start_x, start_y = _marker(anchor, "from")
                        end_x, end_y = _marker(anchor, "to")
                        if end_x <= start_x or end_y <= start_y:
                            raise ValueError("inverted_drawing_bounds")
                        result["checked_drawings"] += 1
                        # Markers are zero-based; the right/bottom area edge is exclusive.
                        contained = any((left - 1, 0) <= start_x < end_x <= (right, 0)
                                        and (top - 1, 0) <= start_y < end_y <= (bottom, 0)
                                        for left, top, right, bottom in rectangles)
                        if not contained:
                            result["issues"].append({"code": "drawing_exceeds_print_area",
                                "sheet_index": index, "drawing_part": drawing_path,
                                "action": "Inspect the original and preview; fit the whole drawing inside an intended print area or disclose intentional cropping. Do not silently change a user template."})
                        if result["checked_drawings"] >= 1000:
                            raise ValueError("layout_drawing_limit")
    except (ImportError, ValueError, TypeError, KeyError, AttributeError, ET.ParseError, zipfile.BadZipFile):
        result["unverified"].append("layout_not_fully_inspected")
    result["unverified"] = sorted(set(result["unverified"]))
    result["status"] = "issues_found" if result["issues"] else "partial" if result["unverified"] else "no_issue_in_checked_scope"
    return result
