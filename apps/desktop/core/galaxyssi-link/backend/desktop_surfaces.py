"""Multi-display and multi-window surface sessions for Desktop control."""

from __future__ import annotations

import ctypes
import hashlib
import os
import threading
import time
from ctypes import wintypes
from typing import Any, Callable, Mapping, Protocol


CONTRACT_VERSION = "galaxyssi.desktop-surfaces/1.0"
MAX_DISPLAYS = 16
MAX_WINDOWS = 100
MAX_SURFACE_SESSIONS = 128


def enable_windows_per_monitor_dpi() -> None:
    if os.name != "nt":
        return
    try:
        ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    except (AttributeError, OSError):
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except (AttributeError, OSError):
            pass


enable_windows_per_monitor_dpi()


class DesktopSurfaceError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = str(code or "desktop_surface_failed")
        self.retryable = bool(retryable)


class DesktopSurfaceProvider(Protocol):
    def displays(self) -> list[dict[str, Any]]: ...

    def windows(self, displays: list[dict[str, Any]]) -> list[dict[str, Any]]: ...

    def activate_window(self, window_id: str) -> bool: ...


class StaticDesktopSurfaceProvider:
    """Deterministic single-display provider for injected capture environments."""

    def displays(self) -> list[dict[str, Any]]:
        return [{
            "display_id": "display:injected",
            "name": "Injected display",
            "device_name": "injected",
            "bounds": {"left": 0, "top": 0, "width": 1920, "height": 1080},
            "work_area": {"left": 0, "top": 0, "width": 1920, "height": 1080},
            "primary": True,
        }]

    def windows(self, _displays: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return []

    def activate_window(self, _window_id: str) -> bool:
        return False


def _safe_bounds(value: Mapping[str, Any] | None) -> dict[str, int]:
    source = value if isinstance(value, Mapping) else {}
    try:
        left = int(source.get("left") or 0)
        top = int(source.get("top") or 0)
        width = max(0, int(source.get("width") or 0))
        height = max(0, int(source.get("height") or 0))
    except (TypeError, ValueError):
        return {"left": 0, "top": 0, "width": 0, "height": 0}
    return {"left": left, "top": top, "width": width, "height": height}


def _contains(bounds: Mapping[str, int], x: int, y: int) -> bool:
    return (
        int(bounds.get("left") or 0) <= x
        < int(bounds.get("left") or 0) + int(bounds.get("width") or 0)
        and int(bounds.get("top") or 0) <= y
        < int(bounds.get("top") or 0) + int(bounds.get("height") or 0)
    )


def _stable_id(prefix: str, value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:20]
    return f"{prefix}:{digest}"


class _WindowsRect(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


class _WindowsMonitorInfo(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("rcMonitor", _WindowsRect),
        ("rcWork", _WindowsRect),
        ("dwFlags", wintypes.DWORD),
        ("szDevice", wintypes.WCHAR * 32),
    ]


class WindowsDesktopSurfaceProvider:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._window_handles: dict[str, int] = {}

    @staticmethod
    def _require_windows() -> None:
        if os.name != "nt":
            raise DesktopSurfaceError(
                "desktop_surfaces_unavailable",
                "Desktop surface discovery requires Windows",
            )

    def displays(self) -> list[dict[str, Any]]:
        self._require_windows()
        user32 = ctypes.windll.user32
        rows: list[dict[str, Any]] = []
        monitor_proc = ctypes.WINFUNCTYPE(
            wintypes.BOOL,
            wintypes.HANDLE,
            wintypes.HANDLE,
            ctypes.POINTER(_WindowsRect),
            wintypes.LPARAM,
        )

        def collect(monitor, _dc, _rect, _data):
            info = _WindowsMonitorInfo()
            info.cbSize = ctypes.sizeof(_WindowsMonitorInfo)
            if not user32.GetMonitorInfoW(monitor, ctypes.byref(info)):
                return True
            device_name = str(info.szDevice or f"monitor-{len(rows) + 1}")
            bounds = {
                "left": int(info.rcMonitor.left),
                "top": int(info.rcMonitor.top),
                "width": max(0, int(info.rcMonitor.right - info.rcMonitor.left)),
                "height": max(0, int(info.rcMonitor.bottom - info.rcMonitor.top)),
            }
            work_area = {
                "left": int(info.rcWork.left),
                "top": int(info.rcWork.top),
                "width": max(0, int(info.rcWork.right - info.rcWork.left)),
                "height": max(0, int(info.rcWork.bottom - info.rcWork.top)),
            }
            rows.append({
                "display_id": _stable_id("display", device_name.casefold()),
                "name": device_name.replace("\\\\.\\", "")[:120],
                "device_name": device_name[:120],
                "bounds": bounds,
                "work_area": work_area,
                "primary": bool(int(info.dwFlags) & 1),
            })
            return len(rows) < MAX_DISPLAYS

        callback = monitor_proc(collect)
        if not user32.EnumDisplayMonitors(0, 0, callback, 0):
            raise DesktopSurfaceError(
                "display_discovery_failed",
                "Windows could not enumerate connected displays",
                retryable=True,
            )
        rows.sort(
            key=lambda row: (
                not bool(row.get("primary")),
                int((row.get("bounds") or {}).get("left") or 0),
                int((row.get("bounds") or {}).get("top") or 0),
            )
        )
        return rows[:MAX_DISPLAYS]

    def windows(self, displays: list[dict[str, Any]]) -> list[dict[str, Any]]:
        self._require_windows()
        user32 = ctypes.windll.user32
        foreground = int(user32.GetForegroundWindow() or 0)
        rows: list[dict[str, Any]] = []
        handles: dict[str, int] = {}
        window_proc = ctypes.WINFUNCTYPE(
            wintypes.BOOL,
            wintypes.HWND,
            wintypes.LPARAM,
        )

        def collect(hwnd, _data):
            native_handle = int(hwnd or 0)
            if not native_handle or not user32.IsWindowVisible(hwnd):
                return True
            title_length = int(user32.GetWindowTextLengthW(hwnd) or 0)
            if title_length <= 0:
                return True
            title_buffer = ctypes.create_unicode_buffer(min(title_length + 1, 1_024))
            if user32.GetWindowTextW(hwnd, title_buffer, len(title_buffer)) <= 0:
                return True
            title = title_buffer.value.strip()
            if not title:
                return True
            rect = _WindowsRect()
            if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
                return True
            bounds = {
                "left": int(rect.left),
                "top": int(rect.top),
                "width": max(0, int(rect.right - rect.left)),
                "height": max(0, int(rect.bottom - rect.top)),
            }
            if bounds["width"] < 32 or bounds["height"] < 32:
                return True
            process_id = wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
            class_buffer = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, class_buffer, len(class_buffer))
            center_x = bounds["left"] + bounds["width"] // 2
            center_y = bounds["top"] + bounds["height"] // 2
            display_id = next(
                (
                    str(display.get("display_id") or "")
                    for display in displays
                    if _contains(_safe_bounds(display.get("bounds")), center_x, center_y)
                ),
                str(next((item for item in displays if item.get("primary")), {}).get("display_id") or ""),
            )
            window_id = _stable_id(
                "window",
                f"{native_handle:x}:{int(process_id.value)}",
            )
            rows.append({
                "window_id": window_id,
                "title": title[:500],
                "class_name": class_buffer.value[:160],
                "process_id": int(process_id.value),
                "bounds": bounds,
                "display_id": display_id,
                "foreground": native_handle == foreground,
                "minimized": bool(user32.IsIconic(hwnd)),
            })
            handles[window_id] = native_handle
            return len(rows) < MAX_WINDOWS

        callback = window_proc(collect)
        if not user32.EnumWindows(callback, 0):
            raise DesktopSurfaceError(
                "window_discovery_failed",
                "Windows could not enumerate application windows",
                retryable=True,
            )
        rows.sort(
            key=lambda row: (
                not bool(row.get("foreground")),
                bool(row.get("minimized")),
                str(row.get("title") or "").casefold(),
            )
        )
        with self._lock:
            self._window_handles = handles
        return rows[:MAX_WINDOWS]

    def activate_window(self, window_id: str) -> bool:
        self._require_windows()
        clean_window_id = str(window_id or "").strip()
        if not clean_window_id:
            return False
        displays = self.displays()
        self.windows(displays)
        with self._lock:
            hwnd = self._window_handles.get(clean_window_id)
        if not hwnd:
            return False
        user32 = ctypes.windll.user32
        if not user32.IsWindow(hwnd):
            return False
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, 9)
        return bool(user32.SetForegroundWindow(hwnd))


class DesktopSurfaceSessionRegistry:
    def __init__(
        self,
        provider: DesktopSurfaceProvider | None = None,
        *,
        sessions: Mapping[str, Any] | None = None,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.provider = provider or WindowsDesktopSurfaceProvider()
        self.now = now
        self._lock = threading.RLock()
        self._sessions: dict[str, dict[str, Any]] = {
            str(session_id)[:240]: {
                "selected_display_id": str(value.get("selected_display_id") or "")[:120],
                "selected_window_id": str(value.get("selected_window_id") or "")[:120],
                "updated_at": max(0, int(value.get("updated_at") or 0)),
            }
            for session_id, value in dict(sessions or {}).items()
            if str(session_id).strip() and isinstance(value, Mapping)
        }

    def catalog(self, session_id: str) -> dict[str, Any]:
        clean_session_id = self._session_id(session_id)
        displays = self.provider.displays()[:MAX_DISPLAYS]
        if not displays:
            raise DesktopSurfaceError(
                "display_not_found",
                "No controllable Desktop display is available",
                retryable=True,
            )
        windows = self.provider.windows(displays)[:MAX_WINDOWS]
        display_ids = {str(row.get("display_id") or "") for row in displays}
        windows_by_id = {
            str(row.get("window_id") or ""): row
            for row in windows
            if str(row.get("window_id") or "")
        }
        with self._lock:
            selection = dict(self._sessions.get(clean_session_id) or {})
            selected_window_id = str(selection.get("selected_window_id") or "")
            selected_window = windows_by_id.get(selected_window_id)
            selected_display_id = str(selection.get("selected_display_id") or "")
            if selected_window is not None:
                selected_display_id = str(selected_window.get("display_id") or "")
            if selected_display_id not in display_ids:
                selected_display_id = str(
                    next(
                        (
                            row.get("display_id")
                            for row in displays
                            if row.get("primary")
                        ),
                        displays[0].get("display_id"),
                    )
                    or ""
                )
            if selected_window is None:
                selected_window_id = ""
            normalized = {
                "selected_display_id": selected_display_id,
                "selected_window_id": selected_window_id,
                "updated_at": max(
                    int(selection.get("updated_at") or 0),
                    int(self.now() * 1_000),
                ),
            }
            self._sessions[clean_session_id] = normalized
            self._prune_locked()
        target = selected_window or next(
            row for row in displays if row.get("display_id") == selected_display_id
        )
        target_kind = "window" if selected_window is not None else "display"
        return {
            "contract_version": CONTRACT_VERSION,
            "session_id": clean_session_id,
            "display_count": len(displays),
            "window_count": len(windows),
            "displays": displays,
            "windows": windows,
            "selection": {
                **normalized,
                "target_kind": target_kind,
            },
            "target": {
                "kind": target_kind,
                "display_id": selected_display_id,
                "window_id": selected_window_id,
                "title": str(target.get("title") or target.get("name") or "")[:500],
                "bounds": _safe_bounds(target.get("bounds")),
                "foreground": bool(target.get("foreground", target_kind == "display")),
                "minimized": bool(target.get("minimized", False)),
            },
        }

    def select(
        self,
        session_id: str,
        *,
        display_id: str = "",
        window_id: str = "",
    ) -> dict[str, Any]:
        clean_session_id = self._session_id(session_id)
        clean_display_id = str(display_id or "").strip()[:120]
        clean_window_id = str(window_id or "").strip()[:120]
        if not clean_display_id and not clean_window_id:
            raise DesktopSurfaceError(
                "surface_selection_required",
                "Select a display or window",
            )
        catalog = self.catalog(clean_session_id)
        displays = {
            str(row.get("display_id") or ""): row
            for row in catalog["displays"]
        }
        windows = {
            str(row.get("window_id") or ""): row
            for row in catalog["windows"]
        }
        if clean_window_id:
            selected_window = windows.get(clean_window_id)
            if selected_window is None:
                raise DesktopSurfaceError(
                    "window_not_found",
                    "The selected window is no longer available",
                    retryable=True,
                )
            clean_display_id = str(selected_window.get("display_id") or "")
        elif clean_display_id not in displays:
            raise DesktopSurfaceError(
                "display_not_found",
                "The selected display is no longer available",
                retryable=True,
            )
        with self._lock:
            self._sessions[clean_session_id] = {
                "selected_display_id": clean_display_id,
                "selected_window_id": clean_window_id,
                "updated_at": int(self.now() * 1_000),
            }
            self._prune_locked()
        return self.catalog(clean_session_id)

    def activate_window(self, session_id: str, window_id: str) -> dict[str, Any]:
        self.select(session_id, window_id=window_id)
        if not self.provider.activate_window(window_id):
            raise DesktopSurfaceError(
                "window_activation_failed",
                "Windows could not activate the selected window",
                retryable=True,
            )
        return self.catalog(session_id)

    def follow_foreground_window(self, session_id: str) -> dict[str, Any]:
        catalog = self.catalog(session_id)
        foreground = next(
            (
                row
                for row in catalog["windows"]
                if bool(row.get("foreground"))
            ),
            None,
        )
        if foreground is None:
            return catalog
        return self.select(
            session_id,
            window_id=str(foreground.get("window_id") or ""),
        )

    def target(self, session_id: str) -> dict[str, Any]:
        return dict(self.catalog(session_id)["target"])

    def export(self) -> dict[str, dict[str, Any]]:
        with self._lock:
            return {
                session_id: dict(value)
                for session_id, value in self._sessions.items()
            }

    def restore(self, session_id: str, persistent_id: str) -> bool:
        clean_session_id = self._session_id(session_id)
        clean_persistent_id = self._session_id(persistent_id)
        with self._lock:
            if clean_session_id in self._sessions:
                return False
            source = self._sessions.get(clean_persistent_id)
            if not isinstance(source, Mapping):
                return False
            self._sessions[clean_session_id] = dict(source)
            self._sessions[clean_session_id]["updated_at"] = int(self.now() * 1_000)
            self._prune_locked()
            return True

    def mirror(self, session_id: str, persistent_id: str) -> bool:
        clean_session_id = self._session_id(session_id)
        clean_persistent_id = self._session_id(persistent_id)
        with self._lock:
            source = self._sessions.get(clean_session_id)
            if not isinstance(source, Mapping):
                return False
            self._sessions[clean_persistent_id] = dict(source)
            self._prune_locked()
            return True

    def forget(self, session_id: str) -> None:
        with self._lock:
            self._sessions.pop(str(session_id or "").strip(), None)

    def clear(self) -> None:
        with self._lock:
            self._sessions.clear()

    @staticmethod
    def _session_id(session_id: str) -> str:
        value = str(session_id or "").strip()
        if not value or len(value) > 240:
            raise DesktopSurfaceError(
                "desktop_session_required",
                "A valid Desktop session is required",
            )
        return value

    def _prune_locked(self) -> None:
        if len(self._sessions) <= MAX_SURFACE_SESSIONS:
            return
        oldest = sorted(
            self._sessions,
            key=lambda key: int(self._sessions[key].get("updated_at") or 0),
        )
        for session_id in oldest[: len(self._sessions) - MAX_SURFACE_SESSIONS]:
            self._sessions.pop(session_id, None)
