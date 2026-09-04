"""Bounded three-layer Desktop perception for GalaxySSI agents."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any, Callable, Mapping


CONTRACT_VERSION = "galaxyssi.desktop-perception/1.0"
MAX_SCREENSHOT_BYTES = 100_000
MAX_UI_ELEMENTS = 120
MAX_UI_DEPTH = 12
MAX_OCR_CHARS = 24_000
MAX_OCR_LINES = 160
MAX_RESULT_BYTES = 240 * 1024

ScreenshotProvider = Callable[[], dict[str, Any]]
UiTreeProvider = Callable[[int, int], dict[str, Any]]
OcrProvider = Callable[[bytes, int], dict[str, Any]]


class DesktopPerceptionError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = str(code or "desktop_perception_failed")
        self.retryable = bool(retryable)


def _bounded_text(value: Any, maximum: int) -> str:
    return str(value or "").replace("\x00", "")[:maximum]


def _safe_int(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _layer_error(exc: Exception) -> dict[str, Any]:
    return {
        "status": "unavailable",
        "error": {
            "code": _bounded_text(getattr(exc, "code", "") or exc.__class__.__name__, 96),
            "message": _bounded_text(str(exc) or "Perception layer unavailable", 500),
            "retryable": bool(getattr(exc, "retryable", False)),
        },
    }


def _powershell() -> str:
    executable = shutil.which("powershell.exe") or shutil.which("powershell")
    if not executable:
        raise DesktopPerceptionError(
            "powershell_unavailable",
            "Windows PowerShell is unavailable",
            retryable=True,
        )
    return executable


def _run_powershell_json(
    script: str,
    *,
    environment: Mapping[str, str] | None = None,
    timeout_seconds: float,
) -> dict[str, Any]:
    env = os.environ.copy()
    env.update({str(key): str(value) for key, value in dict(environment or {}).items()})
    flags = 0x08000000 if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            [
                _powershell(),
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                script,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=timeout_seconds,
            creationflags=flags,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise DesktopPerceptionError(
            "perception_timeout",
            "Windows perception timed out",
            retryable=True,
        ) from exc
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip()
        raise DesktopPerceptionError(
            "windows_perception_failed",
            _bounded_text(message, 1_000) or "Windows perception failed",
            retryable=True,
        )
    candidates = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    for candidate in reversed(candidates):
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    raise DesktopPerceptionError(
        "invalid_perception_output",
        "Windows perception returned invalid output",
        retryable=True,
    )


class WindowsUiAutomationProvider:
    def __call__(self, max_elements: int, max_depth: int) -> dict[str, Any]:
        if os.name != "nt":
            raise DesktopPerceptionError(
                "ui_automation_unavailable",
                "Windows UI Automation requires Windows",
            )
        result = _run_powershell_json(
            _UI_AUTOMATION_SCRIPT,
            environment={
                "GALAXYSSI_UI_MAX_ELEMENTS": str(max_elements),
                "GALAXYSSI_UI_MAX_DEPTH": str(max_depth),
            },
            timeout_seconds=6.0,
        )
        elements = result.get("elements")
        if not isinstance(elements, list):
            raise DesktopPerceptionError(
                "invalid_ui_tree",
                "Windows UI Automation returned no element list",
                retryable=True,
            )
        bounded: list[dict[str, Any]] = []
        for raw in elements[:max_elements]:
            if not isinstance(raw, Mapping):
                continue
            bounds = raw.get("bounds") if isinstance(raw.get("bounds"), Mapping) else {}
            actions = raw.get("actions") if isinstance(raw.get("actions"), list) else []
            bounded.append({
                "id": _bounded_text(raw.get("id"), 160),
                "parent_id": _bounded_text(raw.get("parent_id"), 160),
                "depth": min(max(0, _safe_int(raw.get("depth"))), max_depth),
                "name": (
                    "[redacted]"
                    if bool(raw.get("password"))
                    else _bounded_text(raw.get("name"), 500)
                ),
                "control_type": _bounded_text(raw.get("control_type"), 120),
                "automation_id": _bounded_text(raw.get("automation_id"), 240),
                "class_name": _bounded_text(raw.get("class_name"), 240),
                "framework_id": _bounded_text(raw.get("framework_id"), 80),
                "bounds": {
                    "left": _safe_int(bounds.get("left")),
                    "top": _safe_int(bounds.get("top")),
                    "width": max(0, _safe_int(bounds.get("width"))),
                    "height": max(0, _safe_int(bounds.get("height"))),
                },
                "enabled": bool(raw.get("enabled")),
                "focusable": bool(raw.get("focusable")),
                "focused": bool(raw.get("focused")),
                "offscreen": bool(raw.get("offscreen")),
                "password": bool(raw.get("password")),
                "actions": [
                    _bounded_text(action, 64)
                    for action in actions[:12]
                    if _bounded_text(action, 64)
                ],
            })
        window = result.get("active_window")
        active_window = dict(window) if isinstance(window, Mapping) else {}
        return {
            "engine": "windows-ui-automation",
            "active_window": {
                "title": _bounded_text(active_window.get("title"), 500),
                "automation_id": _bounded_text(active_window.get("automation_id"), 240),
                "class_name": _bounded_text(active_window.get("class_name"), 240),
                "framework_id": _bounded_text(active_window.get("framework_id"), 80),
                "process_id": max(0, _safe_int(active_window.get("process_id"))),
            },
            "elements": bounded,
            "element_count": len(bounded),
            "truncated": bool(result.get("truncated")) or len(elements) > len(bounded),
        }


class WindowsMediaOcrProvider:
    def __call__(self, image_bytes: bytes, max_chars: int) -> dict[str, Any]:
        if os.name != "nt":
            raise DesktopPerceptionError(
                "ocr_unavailable",
                "Windows OCR requires Windows",
            )
        if not image_bytes or len(image_bytes) > MAX_SCREENSHOT_BYTES:
            raise DesktopPerceptionError(
                "invalid_ocr_image",
                "OCR image is outside the bounded screenshot limit",
            )
        temporary_path = ""
        try:
            with tempfile.NamedTemporaryFile(
                prefix="galaxyssi-ocr-",
                suffix=".jpg",
                delete=False,
            ) as temporary:
                temporary.write(image_bytes)
                temporary_path = temporary.name
            result = _run_powershell_json(
                _WINDOWS_OCR_SCRIPT,
                environment={"GALAXYSSI_OCR_IMAGE": temporary_path},
                timeout_seconds=12.0,
            )
        finally:
            if temporary_path:
                try:
                    Path(temporary_path).unlink(missing_ok=True)
                except OSError:
                    pass
        text = _bounded_text(result.get("text"), max_chars)
        raw_lines = result.get("lines") if isinstance(result.get("lines"), list) else []
        lines: list[str] = []
        remaining = max_chars
        for raw in raw_lines[:MAX_OCR_LINES]:
            line = _bounded_text(raw, min(2_000, remaining)).strip()
            if not line:
                continue
            lines.append(line)
            remaining -= len(line)
            if remaining <= 0:
                break
        return {
            "engine": _bounded_text(result.get("engine"), 120) or "windows-media-ocr",
            "language": _bounded_text(result.get("language"), 80),
            "text": text,
            "lines": lines,
            "character_count": len(text),
            "line_count": len(lines),
            "truncated": len(str(result.get("text") or "")) > len(text)
            or len(raw_lines) > len(lines),
        }


class DesktopPerceptionService:
    def __init__(
        self,
        screenshot_provider: ScreenshotProvider,
        *,
        ui_tree_provider: UiTreeProvider | None = None,
        ocr_provider: OcrProvider | None = None,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.screenshot_provider = screenshot_provider
        self.ui_tree_provider = ui_tree_provider or WindowsUiAutomationProvider()
        self.ocr_provider = ocr_provider or WindowsMediaOcrProvider()
        self.now = now

    def capture(
        self,
        *,
        include_screenshot: bool = True,
        include_ocr: bool = True,
        include_ui_tree: bool = True,
        max_elements: int = 80,
        max_depth: int = 8,
        max_ocr_chars: int = 12_000,
    ) -> dict[str, Any]:
        max_elements = min(max(1, int(max_elements)), MAX_UI_ELEMENTS)
        max_depth = min(max(1, int(max_depth)), MAX_UI_DEPTH)
        max_ocr_chars = min(max(0, int(max_ocr_chars)), MAX_OCR_CHARS)
        started_at = int(self.now() * 1_000)
        capture_id = str(uuid.uuid4())
        screenshot: dict[str, Any] | None = None
        screenshot_bytes = b""
        screenshot_layer: dict[str, Any]
        try:
            screenshot, screenshot_bytes = self._validated_screenshot(
                self.screenshot_provider()
            )
            screenshot_layer = {
                "status": "available",
                "engine": "windows-image-grab",
                "sha256": hashlib.sha256(screenshot_bytes).hexdigest(),
                "bytes": len(screenshot_bytes),
                "width": screenshot["width"],
                "height": screenshot["height"],
                "original_width": screenshot["original_width"],
                "original_height": screenshot["original_height"],
                "captured_at": screenshot["captured_at"],
            }
        except Exception as exc:
            screenshot_layer = _layer_error(exc)

        if include_ui_tree:
            try:
                ui_tree = {
                    "status": "available",
                    **self.ui_tree_provider(max_elements, max_depth),
                }
            except Exception as exc:
                ui_tree = _layer_error(exc)
        else:
            ui_tree = {"status": "disabled"}

        if include_ocr and max_ocr_chars > 0 and screenshot_bytes:
            try:
                ocr = {
                    "status": "available",
                    **self.ocr_provider(screenshot_bytes, max_ocr_chars),
                }
            except Exception as exc:
                ocr = _layer_error(exc)
        elif not include_ocr or max_ocr_chars <= 0:
            ocr = {"status": "disabled"}
        else:
            ocr = {
                "status": "unavailable",
                "error": {
                    "code": "screenshot_unavailable",
                    "message": "OCR requires an available screenshot",
                    "retryable": True,
                },
            }

        available_layers = [
            name
            for name, layer in (
                ("ui_tree", ui_tree),
                ("ocr", ocr),
                ("screenshot", screenshot_layer),
            )
            if layer.get("status") == "available"
        ]
        if not available_layers:
            raise DesktopPerceptionError(
                "desktop_perception_unavailable",
                "No Desktop perception layer is currently available",
                retryable=True,
            )
        completed_at = int(self.now() * 1_000)
        result: dict[str, Any] = {
            "contract_version": CONTRACT_VERSION,
            "capture_id": capture_id,
            "captured_at": completed_at,
            "duration_ms": max(0, completed_at - started_at),
            "active_window": (
                ui_tree.get("active_window")
                if isinstance(ui_tree.get("active_window"), dict)
                else {}
            ),
            "available_layers": available_layers,
            "preferred_grounding": (
                "ui_tree"
                if ui_tree.get("status") == "available" and ui_tree.get("element_count", 0) > 0
                else "ocr"
                if ocr.get("status") == "available" and ocr.get("character_count", 0) > 0
                else "screenshot"
            ),
            "untrusted_evidence": True,
            "screenshot_layer": screenshot_layer,
            "ui_tree": ui_tree,
            "ocr": ocr,
        }
        if include_screenshot and screenshot is not None:
            result["screenshot"] = screenshot
        self._fit_result(result)
        return result

    @staticmethod
    def _validated_screenshot(
        value: Mapping[str, Any],
    ) -> tuple[dict[str, Any], bytes]:
        if not isinstance(value, Mapping) or value.get("image_mime") != "image/jpeg":
            raise DesktopPerceptionError(
                "invalid_screenshot",
                "Desktop screenshot must be a JPEG object",
            )
        try:
            decoded = base64.b64decode(str(value.get("image_base64") or ""), validate=True)
        except (ValueError, TypeError) as exc:
            raise DesktopPerceptionError(
                "invalid_screenshot",
                "Desktop screenshot payload is invalid",
            ) from exc
        if not decoded or len(decoded) > MAX_SCREENSHOT_BYTES:
            raise DesktopPerceptionError(
                "invalid_screenshot",
                "Desktop screenshot exceeds its transport limit",
            )
        if _safe_int(value.get("bytes"), len(decoded)) != len(decoded):
            raise DesktopPerceptionError(
                "invalid_screenshot",
                "Desktop screenshot byte metadata does not match",
            )
        screenshot = {
            "image_mime": "image/jpeg",
            "image_base64": base64.b64encode(decoded).decode("ascii"),
            "bytes": len(decoded),
            "width": _safe_int(value.get("width")),
            "height": _safe_int(value.get("height")),
            "original_width": _safe_int(value.get("original_width")),
            "original_height": _safe_int(value.get("original_height")),
            "captured_at": _safe_int(value.get("captured_at"), int(time.time() * 1_000)),
        }
        if min(
            screenshot["width"],
            screenshot["height"],
            screenshot["original_width"],
            screenshot["original_height"],
        ) <= 0:
            raise DesktopPerceptionError(
                "invalid_screenshot",
                "Desktop screenshot dimensions are invalid",
            )
        return screenshot, decoded

    @staticmethod
    def _fit_result(result: dict[str, Any]) -> None:
        def size() -> int:
            return len(json.dumps(
                result,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8"))

        ui_tree = result.get("ui_tree")
        while size() > MAX_RESULT_BYTES and isinstance(ui_tree, dict):
            elements = ui_tree.get("elements")
            if not isinstance(elements, list) or len(elements) <= 12:
                break
            del elements[max(12, len(elements) // 2):]
            ui_tree["element_count"] = len(elements)
            ui_tree["truncated"] = True
        ocr = result.get("ocr")
        if size() > MAX_RESULT_BYTES and isinstance(ocr, dict):
            lines = ocr.get("lines")
            if isinstance(lines, list):
                ocr["lines"] = lines[:24]
                ocr["line_count"] = len(ocr["lines"])
                ocr["truncated"] = True
            text = str(ocr.get("text") or "")
            if len(text) > 4_000:
                ocr["text"] = text[:4_000]
                ocr["character_count"] = len(ocr["text"])
                ocr["truncated"] = True
        if size() > MAX_RESULT_BYTES:
            raise DesktopPerceptionError(
                "perception_result_too_large",
                "Desktop perception result exceeds its bounded output limit",
            )


_UI_AUTOMATION_SCRIPT = r"""
$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class GalaxySSIUser32 {
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
}
'@
$maxElements = [Math]::Max(1, [Math]::Min(120, [int]$env:GALAXYSSI_UI_MAX_ELEMENTS))
$maxDepth = [Math]::Max(1, [Math]::Min(12, [int]$env:GALAXYSSI_UI_MAX_DEPTH))
$handle = [GalaxySSIUser32]::GetForegroundWindow()
if ($handle -eq [IntPtr]::Zero) { throw "No foreground window is available" }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
if ($null -eq $root) { throw "UI Automation could not resolve the foreground window" }
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$queue = New-Object System.Collections.Queue
$queue.Enqueue([pscustomobject]@{ Element = $root; Depth = 0; ParentId = "" })
$elements = New-Object System.Collections.Generic.List[object]
$truncated = $false
while ($queue.Count -gt 0 -and $elements.Count -lt $maxElements) {
  $item = $queue.Dequeue()
  $element = $item.Element
  try {
    $current = $element.Current
    $runtime = @($element.GetRuntimeId()) -join "."
    if ([string]::IsNullOrWhiteSpace($runtime)) { $runtime = "node-$($elements.Count)" }
    $actions = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in @($element.GetSupportedPatterns())) {
      $name = [string]$pattern.ProgrammaticName
      if ($name -match "Invoke") { $actions.Add("invoke") }
      elseif ($name -match "Toggle") { $actions.Add("toggle") }
      elseif ($name -match "SelectionItem") { $actions.Add("select") }
      elseif ($name -match "ExpandCollapse") { $actions.Add("expand_collapse") }
      elseif ($name -match "Scroll") { $actions.Add("scroll") }
      elseif ($name -match "Value") { $actions.Add("set_value") }
    }
    $bounds = $current.BoundingRectangle
    $elements.Add([ordered]@{
      id = $runtime
      parent_id = [string]$item.ParentId
      depth = [int]$item.Depth
      name = if ($current.IsPassword) { "" } else { [string]$current.Name }
      control_type = ([string]$current.ControlType.ProgrammaticName -replace "^ControlType\.", "")
      automation_id = [string]$current.AutomationId
      class_name = [string]$current.ClassName
      framework_id = [string]$current.FrameworkId
      bounds = [ordered]@{
        left = [int][Math]::Round($bounds.Left)
        top = [int][Math]::Round($bounds.Top)
        width = [int][Math]::Max(0, [Math]::Round($bounds.Width))
        height = [int][Math]::Max(0, [Math]::Round($bounds.Height))
      }
      enabled = [bool]$current.IsEnabled
      focusable = [bool]$current.IsKeyboardFocusable
      focused = [bool]$current.HasKeyboardFocus
      offscreen = [bool]$current.IsOffscreen
      password = [bool]$current.IsPassword
      actions = @($actions | Select-Object -Unique)
    })
    if ($item.Depth -lt $maxDepth) {
      $child = $walker.GetFirstChild($element)
      while ($null -ne $child) {
        if (($elements.Count + $queue.Count) -ge ($maxElements * 2)) {
          $truncated = $true
          break
        }
        $queue.Enqueue([pscustomobject]@{
          Element = $child
          Depth = ([int]$item.Depth + 1)
          ParentId = $runtime
        })
        $child = $walker.GetNextSibling($child)
      }
    }
  } catch {}
}
if ($queue.Count -gt 0) { $truncated = $true }
$rootCurrent = $root.Current
$activeWindow = [pscustomobject]@{
  title = [string]$rootCurrent.Name
  automation_id = [string]$rootCurrent.AutomationId
  class_name = [string]$rootCurrent.ClassName
  framework_id = [string]$rootCurrent.FrameworkId
  process_id = [int]$rootCurrent.ProcessId
}
$elementRows = @($elements | ForEach-Object { $_ })
$result = [pscustomobject]@{
  engine = "windows-ui-automation"
  active_window = $activeWindow
  elements = $elementRows
  truncated = [bool]$truncated
}
$result | ConvertTo-Json -Depth 8 -Compress
"""


_WINDOWS_OCR_SCRIPT = r"""
$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq "AsTask" -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1)
function Await-Result($operation, [Type]$resultType) {
  $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
  $task.Wait()
  return $task.Result
}
$path = [string]$env:GALAXYSSI_OCR_IMAGE
$file = Await-Result ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
$stream = Await-Result ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await-Result ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await-Result ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) { throw "No Windows OCR language is installed" }
$result = Await-Result ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$lines = @($result.Lines | ForEach-Object { [string]$_.Text })
[ordered]@{
  engine = "windows-media-ocr"
  language = [string]$engine.RecognizerLanguage.LanguageTag
  text = [string]$result.Text
  lines = $lines
} | ConvertTo-Json -Depth 5 -Compress
"""
