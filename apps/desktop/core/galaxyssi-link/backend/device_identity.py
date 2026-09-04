"""Stable, human-readable identity metadata for this Desktop installation."""
from __future__ import annotations

import os
import platform
import socket
from functools import lru_cache


_PLACEHOLDERS = {
    "default string",
    "not applicable",
    "not specified",
    "o.e.m.",
    "system product name",
    "system version",
    "to be filled by o.e.m.",
    "unknown",
}


def _clean(value: object) -> str:
    text = " ".join(str(value or "").strip().split())
    return "" if text.lower() in _PLACEHOLDERS else text[:120]


def _windows_bios_value(name: str) -> str:
    if os.name != "nt":
        return ""
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"HARDWARE\DESCRIPTION\System\BIOS",
        ) as key:
            value, _ = winreg.QueryValueEx(key, name)
            return _clean(value)
    except (ImportError, OSError):
        return ""


def compose_device_display_name(
    *,
    explicit_name: str = "",
    model: str = "",
    host_name: str = "",
    identity_fingerprint: str = "",
) -> str:
    explicit = _clean(explicit_name)
    if explicit:
        return explicit
    clean_host = _clean(host_name)
    if clean_host:
        return clean_host
    clean_model = _clean(model)
    if clean_model:
        return clean_model
    suffix = "".join(ch for ch in identity_fingerprint if ch.isalnum())[:4].upper()
    return f"GalaxySSI Desktop \u00b7 {suffix}" if suffix else "GalaxySSI Desktop"


@lru_cache(maxsize=4)
def desktop_device_profile(identity_fingerprint: str = "") -> dict:
    host_name = _clean(socket.gethostname())
    manufacturer = _windows_bios_value("SystemManufacturer")
    model = _windows_bios_value("SystemFamily") or _windows_bios_value("SystemProductName")
    explicit_name = _clean(os.environ.get("GALAXYSSI_DESKTOP_NAME"))
    display_name = compose_device_display_name(
        explicit_name=explicit_name,
        model=model,
        host_name=host_name,
        identity_fingerprint=identity_fingerprint,
    )
    return {
        "kind": "desktop",
        "display_name": display_name,
        "device_name": display_name,
        "host_name": host_name,
        "manufacturer": manufacturer,
        "model": model,
        "platform": platform.system().lower() or "desktop",
        "platform_version": _clean(platform.release()),
        "architecture": _clean(platform.machine()),
    }
