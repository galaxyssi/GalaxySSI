"""Expose installed Office authoring modules without importing them per turn."""
from __future__ import annotations

import importlib.util
import json
import sys


MODULES = ("docx", "pptx", "xlsxwriter", "openpyxl")


def office_authoring_contract() -> str:
    available = []
    for module in MODULES:
        try:
            if importlib.util.find_spec(module) is not None:
                available.append(module)
        except (ImportError, ValueError, OSError):
            continue
    if not available:
        return ""
    return (
        "- For Office files, the Desktop Python interpreter is "
        + json.dumps(sys.executable, ensure_ascii=True)
        + "; discovered authoring modules: " + ", ".join(available) + ". "
        "Use this exact interpreter, not an unrelated PATH Python. Discovery is not an import or render check. "
        "Prefer installed python-docx/docx for editable Word documents, python-pptx/pptx for editable slides "
        "and native charts, and XlsxWriter/xlsxwriter for new workbooks. Use openpyxl to inspect or update "
        "existing workbooks without silently losing unsupported features. Preserve user templates. "
        "For formulas, preserve the formula and verify calculated results; XlsxWriter does not calculate "
        "formulas, so supply independently computed cached values or recalculate with a spreadsheet engine. "
        "Authoring libraries do not render Office pages. Save the native file, render it with the existing "
        "Office preview tool/converter, inspect the actual previews, and fix layout or data discrepancies."
    )
