"""Small, dependency-free helpers shared by the self-evolution subsystem."""
from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
import time
from dataclasses import asdict, is_dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

_SECRET_KEY = re.compile(
    r"(?i)(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|private[_-]?key)"
)
_BEARER = re.compile(r"(?i)\b(bearer|token)\s+[A-Za-z0-9._~+\-/=]{8,}")
_GITHUB_TOKEN = re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")
_PEM = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")
_SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def now_millis() -> int:
    return int(time.time() * 1_000)


def utc_iso(timestamp: float | None = None) -> str:
    return datetime.fromtimestamp(timestamp or time.time(), tz=timezone.utc).isoformat().replace("+00:00", "Z")


def state_root() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    return (Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI").resolve()


def find_repo_root(start: Path | None = None) -> Path:
    configured = str(os.environ.get("GALAXYSSI_SOURCE_ROOT") or "").strip()
    if configured:
        candidate = Path(configured).expanduser().resolve()
        if (candidate / ".git").exists() and (candidate / "apps").is_dir():
            return candidate
    origin = (start or Path(__file__)).resolve()
    for parent in (origin, *origin.parents):
        if (parent / ".git").exists() and (parent / "apps").is_dir():
            return parent
    raise RuntimeError("Set GALAXYSSI_SOURCE_ROOT to a GalaxySSI Git checkout.")


def safe_identifier(value: str, *, label: str = "identifier") -> str:
    clean = str(value or "").strip()
    if not _SAFE_ID.fullmatch(clean):
        raise ValueError(f"Unsafe {label}: {value!r}")
    return clean


def as_jsonable(value: Any) -> Any:
    if is_dataclass(value):
        return as_jsonable(asdict(value))
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {str(key): as_jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [as_jsonable(item) for item in value]
    return value


def stable_json(value: Any) -> str:
    return json.dumps(as_jsonable(value), ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_text(value: str) -> str:
    return sha256_bytes(str(value).encode("utf-8"))


def sha256_file(path: Path, *, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        while True:
            chunk = stream.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def atomic_write_json(path: Path, value: Any) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(as_jsonable(value), ensure_ascii=True, indent=2, sort_keys=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=str(target.parent))
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass


def read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default


def redact_text(value: str, *, maximum: int = 16_000) -> str:
    clean = str(value or "")[:maximum]
    clean = _BEARER.sub(lambda match: f"{match.group(1)} [REDACTED]", clean)
    clean = _GITHUB_TOKEN.sub("[REDACTED_GITHUB_TOKEN]", clean)
    clean = _PEM.sub("-----BEGIN [REDACTED] PRIVATE KEY-----", clean)
    return clean


def redact(value: Any, *, maximum_text: int = 16_000) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            name = str(key)
            result[name] = "[REDACTED]" if _SECRET_KEY.search(name) else redact(item, maximum_text=maximum_text)
        return result
    if isinstance(value, (list, tuple, set)):
        return [redact(item, maximum_text=maximum_text) for item in value]
    if isinstance(value, str):
        return redact_text(value, maximum=maximum_text)
    return value


def bounded_strings(values: Iterable[Any], *, maximum: int, count: int) -> list[str]:
    rows: list[str] = []
    for raw in values:
        value = str(raw or "").strip()
        if value and value not in rows:
            rows.append(value[:maximum])
        if len(rows) >= count:
            break
    return rows


def parse_github_timestamp(value: str) -> float:
    text = str(value or "").strip()
    if not text:
        return 0.0
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def days_since(value: str) -> int:
    timestamp = parse_github_timestamp(value)
    if timestamp <= 0:
        return 9_999
    return max(0, int((time.time() - timestamp) // 86_400))
