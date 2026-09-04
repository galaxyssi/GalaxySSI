"""Local speech-to-text bridge for GalaxySSI voice workloads."""
from __future__ import annotations

import hashlib
import json
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

try:
    from faster_whisper import WhisperModel
except ImportError:
    WhisperModel = None


def _env(name: str, default: str) -> str:
    return os.environ.get(name, "").strip() or default


MODEL_NAME = _env("GALAXYSSI_WHISPER_MODEL", "medium")
DEVICE = _env("GALAXYSSI_WHISPER_DEVICE", "cpu")
COMPUTE_TYPE = _env("GALAXYSSI_WHISPER_COMPUTE_TYPE", "int8")

_MODEL_ALIASES = {
    "medium": ("medium", "medium"),
    "large": ("large-v3", "large-v3"),
    "large-v3": ("large-v3", "large-v3"),
    "turbo": ("large-v3-turbo", "turbo"),
    "large-v3-turbo": ("large-v3-turbo", "turbo"),
}


@dataclass(frozen=True)
class WhisperProfile:
    profile_id: str
    model_name: str
    device: str = DEVICE
    compute_type: str = COMPUTE_TYPE

    @property
    def profile_sha256(self) -> str:
        encoded = json.dumps(
            {
                "compute_type": self.compute_type,
                "device": self.device,
                "engine": "faster-whisper",
                "model_name": self.model_name,
                "profile_id": self.profile_id,
                "schema": "galaxyssi.whisper-profile/1.0",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()

    def public(self) -> dict[str, str]:
        return {
            "profile_id": self.profile_id,
            "model_name": self.model_name,
            "engine": "faster-whisper",
            "device": self.device,
            "compute_type": self.compute_type,
            "profile_sha256": self.profile_sha256,
            "sha_kind": "profile_manifest_sha256",
        }


@dataclass(frozen=True)
class WhisperTranscription:
    text: str
    language: str
    language_probability: float | None
    duration_seconds: float | None
    profile: WhisperProfile


def whisper_profile(value: str | WhisperProfile | None = None) -> WhisperProfile:
    if isinstance(value, WhisperProfile):
        return value
    requested = str(value or MODEL_NAME).strip().lower()
    profile_id, model_name = _MODEL_ALIASES.get(requested, (requested, requested))
    return WhisperProfile(
        profile_id=profile_id,
        model_name=model_name,
        device=DEVICE,
        compute_type=COMPUTE_TYPE,
    )


def supported_remote_profiles() -> tuple[WhisperProfile, ...]:
    return tuple(whisper_profile(name) for name in ("medium", "large-v3", "large-v3-turbo"))


def faster_whisper_available() -> bool:
    return WhisperModel is not None


_model: Any | None = None
_model_key: tuple[str, str, str] | None = None
_lock = threading.Lock()


def _default_model_factory(profile: WhisperProfile) -> Any:
    if WhisperModel is None:
        raise RuntimeError("faster-whisper is not installed. Install faster-whisper to enable voice transcription.")
    return WhisperModel(
        profile.model_name,
        device=profile.device,
        compute_type=profile.compute_type,
    )


def _get_model(
    profile: WhisperProfile | None = None,
    *,
    model_factory: Callable[[WhisperProfile], Any] | None = None,
) -> Any:
    global _model, _model_key
    selected = profile or whisper_profile()
    key = (selected.model_name, selected.device, selected.compute_type)
    if _model is not None and _model_key == key:
        return _model
    factory = model_factory or _default_model_factory
    with _lock:
        if _model is None or _model_key != key:
            _model = factory(selected)
            _model_key = key
    return _model


def reset_model_cache() -> None:
    global _model, _model_key
    with _lock:
        _model = None
        _model_key = None


def transcribe_audio_detailed(
    path: str | Path,
    language: str | None = None,
    *,
    profile: str | WhisperProfile | None = None,
    model_factory: Callable[[WhisperProfile], Any] | None = None,
) -> WhisperTranscription:
    audio_path = Path(path)
    if not audio_path.is_file():
        raise FileNotFoundError(f"audio file not found: {audio_path}")
    selected = whisper_profile(profile)
    segments, info = _get_model(selected, model_factory=model_factory).transcribe(
        str(audio_path),
        language=language or None,
        vad_filter=True,
        beam_size=5,
    )
    text = "".join(str(segment.text) for segment in segments).strip()
    return WhisperTranscription(
        text=text,
        language=str(getattr(info, "language", None) or language or "auto"),
        language_probability=_optional_float(getattr(info, "language_probability", None)),
        duration_seconds=_optional_float(getattr(info, "duration", None)),
        profile=selected,
    )


def transcribe_audio(
    path: str | Path,
    language: str | None = None,
    *,
    profile: str | WhisperProfile | None = None,
) -> str:
    return transcribe_audio_detailed(path, language, profile=profile).text


def _optional_float(value: Any) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None
