"""Propagate the user's proxy choice to Codex's HTTP and WebSocket clients."""

from __future__ import annotations

import urllib.request
from collections.abc import Callable, Mapping


PROXY_KEYS = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")


def system_proxies() -> dict[str, str]:
    # getproxies() may stop at an unrelated environment variable (e.g. NO_PROXY).
    reader = getattr(urllib.request, "getproxies_registry", None)
    if reader is None:
        return {}
    try:
        return dict(reader())
    except OSError:
        return {}


def codex_proxy_environment(
    environment: Mapping[str, str],
    tcp_available: Callable[[str, int], bool],
) -> dict[str, str]:
    env = dict(environment)
    explicit = env.get("GALAXYSSI_CODEX_PROXY", "").strip()
    if explicit:
        for key in PROXY_KEYS:
            env[key] = explicit
        source = "explicit"
    elif any(env.get(key, "").strip() for key in PROXY_KEYS):
        # Never replace an explicit process proxy with an auto-discovered one.
        source = "environment"
    else:
        proxies = system_proxies()
        for scheme in ("http", "https", "all"):
            value = str(proxies.get(scheme) or "").strip()
            if value:
                env[f"{scheme}_proxy"] = value
                env[f"{scheme.upper()}_PROXY"] = value
        if any(env.get(key) for key in PROXY_KEYS):
            source = "system"
        elif tcp_available("127.0.0.1", 7890):
            source = "legacy_local"
            for key in PROXY_KEYS:
                env[key] = "http://127.0.0.1:7890"
        else:
            source = "direct"
        if proxies.get("no") and not (env.get("NO_PROXY") or env.get("no_proxy")):
            env["NO_PROXY"] = str(proxies["no"])
    if source != "direct":
        bypass = list(dict.fromkeys(
            part.strip()
            for value in (env.get("NO_PROXY", ""), env.get("no_proxy", ""), "localhost,127.0.0.1,::1")
            for part in value.split(",") if part.strip()
        ))
        env["NO_PROXY"] = env["no_proxy"] = ",".join(bypass)
    # Only the selection source is diagnostic; never log proxy credentials.
    env["GALAXYSSI_CODEX_PROXY_SOURCE"] = source
    return env
