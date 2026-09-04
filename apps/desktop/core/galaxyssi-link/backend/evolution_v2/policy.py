"""Risk classification and immutable safety policy for self-modifying tasks."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .common import find_repo_root, read_json
from .models import PolicyDecision

RISK_ORDER = {"low": 0, "medium": 1, "high": 2, "critical": 3}
DEFAULT_POLICY: dict[str, Any] = {
    "schema": "galaxyssi.evolution-policy.v2",
    "publish": {
        "require_approval_hash": True,
        "auto_publish": False,
        "auto_merge": False,
        "allow_critical_pr": True,
    },
    "limits": {
        "max_changed_files": 96,
        "max_total_diff_lines": 12000,
        "max_new_file_bytes": 2097152,
        "max_binary_files": 0,
    },
    "quality": {
        "require_tests_for_code": True,
        "desktop_runtime_smoke": True,
        "android_device_smoke": False,
        "agent_review": False,
        "agent_review_fail_closed_from": "high",
    },
    "protected_paths": [
        ".git",
        ".github/workflows",
        ".openai",
        "config/evolution-policy.json",
        "config/evolution-gates.json",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/gate_cli.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/gates.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/policy.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/review.py",
        "node_modules",
        "dist",
        "build",
        "runtime-data",
    ],
    "critical_paths": [
        "apps/desktop/core/galaxyssi-link/backend/crypto",
        "apps/desktop/core/galaxyssi-link/backend/pairing",
        "apps/desktop/core/galaxyssi-link/backend/desktop_control",
        "apps/desktop/core/galaxyssi-link/backend/evolution_manager.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/api.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/audit.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/github_client.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/manager.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/provenance.py",
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2/snapshots.py",
        "apps/android/app/src/main/AndroidManifest.xml",
        "apps/android/app/src/main/java/com/galaxyssi/chat/security",
        "apps/android/app/src/main/java/com/galaxyssi/chat/accessibility",
        ".github/workflows",
    ],
    "high_risk_paths": [
        "apps/desktop/core/galaxyssi-link/backend/mqtt_bridge.py",
        "apps/desktop/core/galaxyssi-link/backend/agent_gateway.py",
        "apps/desktop/src/main.js",
        "apps/desktop/src/preload.js",
        "apps/android/app/build.gradle.kts",
        "apps/desktop/package.json",
    ],
    "low_risk_paths": ["docs", "README.md", "apps/desktop/src/renderer/locales"],
    "dependency_files": [
        "apps/desktop/package.json",
        "apps/desktop/package-lock.json",
        "apps/android/build.gradle.kts",
        "apps/android/settings.gradle.kts",
        "apps/android/app/build.gradle.kts",
        "apps/desktop/core/galaxyssi-link/backend/requirements.txt",
    ],
    "secret_patterns": [
        "github_pat_",
        "ghp_",
        "gho_",
        "AKIA",
        "-----BEGIN PRIVATE KEY-----",
        "-----BEGIN RSA PRIVATE KEY-----",
    ],
}


@dataclass(frozen=True)
class PathMatch:
    path: str
    rule: str
    risk: str


class EvolutionPolicy:
    def __init__(self, source_root: Path | None = None, config_path: Path | None = None) -> None:
        self.source_root = (Path(source_root) if source_root else find_repo_root()).resolve()
        configured = config_path or self.source_root / "config" / "evolution-policy.json"
        self.config_path = Path(configured)
        loaded = read_json(self.config_path, {})
        self.config = _deep_merge(DEFAULT_POLICY, loaded if isinstance(loaded, dict) else {})

    def decide(self, scope: Iterable[str], requested_risk: str = "medium") -> PolicyDecision:
        requested = requested_risk if requested_risk in RISK_ORDER else "medium"
        effective = requested
        reasons: list[str] = []
        matched: list[str] = []
        allowed = True
        for raw in scope:
            path = str(raw or "").replace("\\", "/").strip("/")
            if not path:
                continue
            protected = self._match(path, self.config.get("protected_paths") or [])
            if protected:
                allowed = False
                effective = "critical"
                reasons.append(f"Protected path cannot be modified by evolution: {path}")
                matched.append(f"protected:{protected}")
                continue
            critical = self._match(path, self.config.get("critical_paths") or [])
            if critical:
                effective = _max_risk(effective, "critical")
                reasons.append(f"Critical control/security surface: {path}")
                matched.append(f"critical:{critical}")
                continue
            high = self._match(path, self.config.get("high_risk_paths") or [])
            if high:
                effective = _max_risk(effective, "high")
                reasons.append(f"High-impact runtime or dependency surface: {path}")
                matched.append(f"high:{high}")
                continue
            if self._match(path, self.config.get("dependency_files") or []):
                effective = _max_risk(effective, "high")
                reasons.append(f"Dependency or build graph change: {path}")
                matched.append("dependency")
            elif not self._match(path, self.config.get("low_risk_paths") or []):
                effective = _max_risk(effective, "medium")
        if RISK_ORDER[effective] > RISK_ORDER[requested]:
            reasons.insert(0, f"Risk elevated from {requested} to {effective} by policy.")
        publish = self.config.get("publish") or {}
        auto_publish = bool(publish.get("auto_publish")) and effective == "low" and allowed
        auto_merge = bool(publish.get("auto_merge")) and effective == "low" and allowed
        return PolicyDecision(
            requested_risk=requested,
            effective_risk=effective,
            allowed=allowed,
            approval_required=True,
            auto_publish=auto_publish,
            auto_merge=auto_merge,
            reasons=reasons or ["No elevated-risk path rule matched."],
            matched_rules=matched,
        )

    def validate_changed_files(self, changed_files: Iterable[str]) -> PolicyDecision:
        return self.decide(changed_files, "low")

    def quality(self, key: str, default: Any = None) -> Any:
        return (self.config.get("quality") or {}).get(key, default)

    def limit(self, key: str, default: int) -> int:
        try:
            return int((self.config.get("limits") or {}).get(key, default))
        except (TypeError, ValueError):
            return default

    def public(self) -> dict[str, Any]:
        return {
            "schema": self.config.get("schema"),
            "config_path": str(self.config_path),
            "publish": self.config.get("publish"),
            "limits": self.config.get("limits"),
            "quality": self.config.get("quality"),
            "protected_paths": self.config.get("protected_paths"),
            "critical_paths": self.config.get("critical_paths"),
            "high_risk_paths": self.config.get("high_risk_paths"),
        }

    @staticmethod
    def _match(path: str, roots: Iterable[str]) -> str:
        lowered = path.casefold()
        for raw in roots:
            root = str(raw or "").replace("\\", "/").strip("/")
            if not root:
                continue
            root_lower = root.casefold()
            if lowered == root_lower or lowered.startswith(f"{root_lower}/"):
                return root
        return ""


def _max_risk(first: str, second: str) -> str:
    return first if RISK_ORDER[first] >= RISK_ORDER[second] else second


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in base.items():
        result[key] = _deep_merge(value, {}) if isinstance(value, dict) else list(value) if isinstance(value, list) else value
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result
