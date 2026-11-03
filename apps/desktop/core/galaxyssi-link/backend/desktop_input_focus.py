"""Read only focused-control metadata, never text or password values."""
from __future__ import annotations

import atexit
import base64
import hashlib
import json
import os
import queue
import shutil
import subprocess
import threading
from typing import Any


_SCRIPT = r'''
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
while ($null -ne [Console]::ReadLine()) {
    try {
        $element = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $element) { throw "No focus" }
        $current = $element.Current
        $editable = $false
        $value = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$value)) {
            $editable = !$value.Current.IsReadOnly
        } else {
            $text = $null
            if ($element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$text)) {
                $readonly = $text.DocumentRange.GetAttributeValue([System.Windows.Automation.TextPattern]::IsReadOnlyAttribute)
                $editable = ($readonly -is [bool]) -and (!$readonly)
            }
        }
        $bounds = $current.BoundingRectangle
        $result = @{
            available = $true
            editable = [bool]($editable -and $current.IsEnabled -and !$current.IsOffscreen)
            password = [bool]$current.IsPassword
            target = "$( $current.ProcessId ):$( $element.GetRuntimeId() -join ',' )"
            bounds = @{ left=[int]$bounds.Left; top=[int]$bounds.Top; width=[int]$bounds.Width; height=[int]$bounds.Height }
        }
        [Console]::WriteLine(($result | ConvertTo-Json -Depth 4 -Compress))
    } catch {
        [Console]::WriteLine('{"available":false,"editable":false}')
    }
}
'''


class DesktopInputFocusReader:
    """One lazy, hidden UIA worker; bounded reads and restart after a hung provider."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._process: subprocess.Popen | None = None
        self._responses: queue.Queue[str | None] = queue.Queue(maxsize=4)
        atexit.register(self.close)

    def _start(self) -> None:
        executable = shutil.which("powershell.exe")
        if not executable:
            raise OSError("PowerShell is unavailable")
        encoded = base64.b64encode(_SCRIPT.encode("utf-16-le")).decode("ascii")
        process = subprocess.Popen(
            [executable, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", bufsize=1,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        responses: queue.Queue[str | None] = queue.Queue(maxsize=4)
        self._process, self._responses = process, responses

        def read_lines() -> None:
            try:
                for line in process.stdout:
                    responses.put(line, timeout=1)
            except (OSError, ValueError, queue.Full):
                pass
            finally:
                process.stdout.close()
                try:
                    responses.put_nowait(None)
                except queue.Full:
                    pass

        threading.Thread(target=read_lines, name="desktop-input-focus", daemon=True).start()

    def read(self) -> dict[str, Any]:
        if os.name != "nt":
            return {"available": False, "editable": False}
        with self._lock:
            try:
                starting = self._process is None or self._process.poll() is not None
                if starting:
                    self._stop()
                    self._start()
                self._process.stdin.write("focus\n")
                self._process.stdin.flush()
                raw = self._responses.get(timeout=3 if starting else 0.8)
                result = json.loads(raw or "{}")
                target = str(result.pop("target", ""))
                result["target_id"] = hashlib.sha256(target.encode()).hexdigest() if target else ""
                return result
            except (OSError, ValueError, queue.Empty, AttributeError):
                self._stop()
                return {"available": False, "editable": False}

    def _stop(self) -> None:
        process, self._process = self._process, None
        if process:
            if process.poll() is None:
                process.kill()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            if process.stdin:
                try:
                    process.stdin.close()
                except OSError:
                    pass

    def close(self) -> None:
        with self._lock:
            self._stop()


def focus_for_surface(focus: dict[str, Any], bounds: dict[str, Any]) -> dict[str, Any]:
    """Do not open an IME for a field outside the selected monitor/window."""
    value = dict(focus)
    field = value.get("bounds") or {}
    if field:
        left = int(field.get("left", 0)) - int(bounds.get("left", 0))
        top = int(field.get("top", 0)) - int(bounds.get("top", 0))
        width, height = int(field.get("width", 0)), int(field.get("height", 0))
        value["bounds"] = {"left": left, "top": top, "width": width, "height": height}
        if (left + width <= 0 or top + height <= 0 or
                left >= int(bounds.get("width", 0)) or top >= int(bounds.get("height", 0))):
            value["editable"] = False
    return value
