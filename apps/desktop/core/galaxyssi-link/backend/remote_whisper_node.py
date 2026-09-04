"""Pairing-bound high-accuracy Whisper node for Android transcript correction."""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import shutil
import tempfile
import threading
import time
import uuid
import wave
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Mapping

from galaxyssi_client import desktop_id, desktop_name
from stt_bridge import (
    WhisperProfile,
    WhisperTranscription,
    faster_whisper_available,
    supported_remote_profiles,
    transcribe_audio_detailed,
    whisper_profile,
)


PROTOCOL = "galaxyssi.remote-whisper/1.0"
REQUEST_TYPE = "remote_whisper_request"
CHUNK_TYPE = "remote_whisper_chunk"
CANCEL_TYPE = "remote_whisper_cancel"
RESULT_TYPE = "remote_whisper_result"
CANCELLED_TYPE = "remote_whisper_cancelled"
ERROR_TYPE = "remote_whisper_error"
AUDIO_FORMAT = "pcm_s16le_16000_mono"
CONSENT_SCOPE = "voice.remote_whisper.correction"


class RemoteWhisperError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = str(code)


@dataclass(frozen=True)
class RemoteWhisperNodeConfig:
    enabled: bool = True
    model_profile_id: str = "medium"
    max_pcm_bytes: int = 16_000 * 2 * 120
    consent_max_age_ms: int = 5 * 60 * 1_000
    cache_entries: int = 64
    workers: int = 1
    temp_root: Path = field(
        default_factory=lambda: Path(
            os.environ.get("GALAXYSSI_REMOTE_WHISPER_TEMP", "").strip()
            or Path(tempfile.gettempdir()) / "GalaxySSI" / "remote-whisper"
        )
    )

    @classmethod
    def from_environment(cls) -> "RemoteWhisperNodeConfig":
        return cls(
            enabled=os.environ.get("GALAXYSSI_REMOTE_WHISPER_ENABLED", "1").strip().lower()
            not in {"0", "false", "off", "no"},
            model_profile_id=os.environ.get(
                "GALAXYSSI_REMOTE_WHISPER_PROFILE",
                os.environ.get("GALAXYSSI_WHISPER_MODEL", "medium"),
            ).strip()
            or "medium",
            max_pcm_bytes=max(
                32_000,
                int(os.environ.get("GALAXYSSI_REMOTE_WHISPER_MAX_PCM_BYTES", str(16_000 * 2 * 120))),
            ),
            workers=max(1, min(2, int(os.environ.get("GALAXYSSI_REMOTE_WHISPER_WORKERS", "1")))),
        )


@dataclass(frozen=True)
class ValidatedRemoteWhisperRequest:
    request_id: str
    voice_session_id: str
    transcript_id: str
    client_route_id: str
    client_id: str
    language: str
    profile: WhisperProfile
    pcm: bytes
    pcm_sha256: str
    sample_count: int
    duration_ms: int
    request_digest: str
    deletion_requested: bool


@dataclass
class _ActiveRequest:
    request_digest: str
    cancel: threading.Event = field(default_factory=threading.Event)
    done: threading.Event = field(default_factory=threading.Event)


@dataclass
class _InboundAudioTransfer:
    manifest: dict[str, Any]
    manifest_digest: str
    chunk_count: int
    chunk_size_bytes: int
    byte_count: int
    pcm_sha256: str
    created_at_ms: int
    chunks: dict[int, bytearray] = field(default_factory=dict)


class RemoteWhisperRequestAssembler:
    """Reassembles encrypted application messages before Whisper can see PCM."""

    def __init__(
        self,
        *,
        max_pcm_bytes: int = 16_000 * 2 * 120,
        max_chunk_bytes: int = 128 * 1024,
        transfer_ttl_ms: int = 5 * 60 * 1_000,
        clock_ms: Callable[[], int] | None = None,
    ) -> None:
        self.max_pcm_bytes = max_pcm_bytes
        self.max_chunk_bytes = max_chunk_bytes
        self.transfer_ttl_ms = transfer_ttl_ms
        self._clock_ms = clock_ms or (lambda: int(time.time() * 1_000))
        self._lock = threading.RLock()
        self._transfers: dict[tuple[str, str], _InboundAudioTransfer] = {}

    def accept(self, payload: Mapping[str, Any], *, client_route_id: str) -> dict[str, Any] | None:
        with self._lock:
            self._purge_expired_locked()
            payload_type = str(payload.get("type") or "")
            if payload_type == REQUEST_TYPE:
                self._accept_manifest_locked(payload, client_route_id)
                return None
            if payload_type != CHUNK_TYPE:
                raise RemoteWhisperError("protocol_invalid", "Unsupported remote Whisper packet")
            return self._accept_chunk_locked(payload, client_route_id)

    def cancel(self, request_id: str, *, client_route_id: str) -> bool:
        with self._lock:
            transfer = self._transfers.pop((client_route_id, request_id), None)
            if transfer is not None:
                self._wipe_transfer(transfer)
            return transfer is not None

    def active_count(self) -> int:
        with self._lock:
            self._purge_expired_locked()
            return len(self._transfers)

    def _accept_manifest_locked(self, payload: Mapping[str, Any], client_route_id: str) -> None:
        if payload.get("protocol") != PROTOCOL:
            raise RemoteWhisperError("protocol_invalid", "Unsupported remote Whisper protocol")
        request_id = _valid_uuid(payload.get("request_id"), "request_id")
        if str(payload.get("client_route_id") or "") != client_route_id:
            raise RemoteWhisperError("identity_mismatch", "Client route does not match the encrypted pairing")
        audio = payload.get("audio")
        if not isinstance(audio, Mapping) or audio.get("format") != AUDIO_FORMAT:
            raise RemoteWhisperError("audio_format_invalid", "PCM16 16 kHz mono audio is required")
        byte_count = int(audio.get("byte_count") or 0)
        chunk_count = int(audio.get("chunk_count") or 0)
        chunk_size_bytes = int(audio.get("chunk_size_bytes") or 0)
        if byte_count <= 0 or byte_count > self.max_pcm_bytes or byte_count % 2:
            raise RemoteWhisperError("audio_size_invalid", "Remote PCM length is invalid")
        if chunk_size_bytes <= 0 or chunk_size_bytes > self.max_chunk_bytes:
            raise RemoteWhisperError("audio_chunk_invalid", "Remote PCM chunk size is invalid")
        expected_chunks = (byte_count + chunk_size_bytes - 1) // chunk_size_bytes
        if chunk_count != expected_chunks or chunk_count > 128:
            raise RemoteWhisperError("audio_chunk_invalid", "Remote PCM chunk count is invalid")
        pcm_sha256 = str(audio.get("sha256") or "").lower()
        if not _is_sha256(pcm_sha256):
            raise RemoteWhisperError("audio_integrity_failed", "Remote PCM hash is invalid")
        manifest = json.loads(json.dumps(dict(payload), ensure_ascii=True))
        manifest_digest = hashlib.sha256(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()
        key = (client_route_id, request_id)
        existing = self._transfers.get(key)
        if existing is not None:
            if existing.manifest_digest != manifest_digest:
                raise RemoteWhisperError("idempotency_conflict", "Request manifest changed during transfer")
            return
        self._transfers[key] = _InboundAudioTransfer(
            manifest=manifest,
            manifest_digest=manifest_digest,
            chunk_count=chunk_count,
            chunk_size_bytes=chunk_size_bytes,
            byte_count=byte_count,
            pcm_sha256=pcm_sha256,
            created_at_ms=self._clock_ms(),
        )

    def _accept_chunk_locked(
        self,
        payload: Mapping[str, Any],
        client_route_id: str,
    ) -> dict[str, Any] | None:
        request_id = _valid_uuid(payload.get("request_id"), "request_id")
        if payload.get("protocol") != PROTOCOL or str(payload.get("client_route_id") or "") != client_route_id:
            raise RemoteWhisperError("identity_mismatch", "Remote PCM chunk identity does not match")
        key = (client_route_id, request_id)
        transfer = self._transfers.get(key)
        if transfer is None:
            raise RemoteWhisperError("manifest_required", "Remote PCM manifest must arrive before chunks")
        index = int(payload.get("chunk_index") if payload.get("chunk_index") is not None else -1)
        if int(payload.get("chunk_count") or 0) != transfer.chunk_count or index not in range(transfer.chunk_count):
            raise RemoteWhisperError("audio_chunk_invalid", "Remote PCM chunk index is invalid")
        encoded = str(payload.get("data_base64") or "")
        if not encoded or len(encoded) > ((self.max_chunk_bytes + 2) // 3 * 4 + 4):
            raise RemoteWhisperError("audio_chunk_invalid", "Remote PCM chunk exceeds the limit")
        try:
            chunk = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise RemoteWhisperError("audio_base64_invalid", "Remote PCM chunk encoding is invalid") from exc
        expected_size = min(
            transfer.chunk_size_bytes,
            transfer.byte_count - index * transfer.chunk_size_bytes,
        )
        if len(chunk) != expected_size:
            raise RemoteWhisperError("audio_chunk_invalid", "Remote PCM chunk length is invalid")
        if hashlib.sha256(chunk).hexdigest() != str(payload.get("chunk_sha256") or "").lower():
            raise RemoteWhisperError("audio_integrity_failed", "Remote PCM chunk integrity check failed")
        existing = transfer.chunks.get(index)
        if existing is not None:
            if bytes(existing) != chunk:
                raise RemoteWhisperError("idempotency_conflict", "Remote PCM duplicate chunk changed")
        else:
            transfer.chunks[index] = bytearray(chunk)
        if len(transfer.chunks) != transfer.chunk_count:
            return None
        pcm = b"".join(bytes(transfer.chunks[position]) for position in range(transfer.chunk_count))
        if len(pcm) != transfer.byte_count or hashlib.sha256(pcm).hexdigest() != transfer.pcm_sha256:
            self._transfers.pop(key, None)
            self._wipe_transfer(transfer)
            raise RemoteWhisperError("audio_integrity_failed", "Complete remote PCM integrity check failed")
        completed = transfer.manifest
        completed_audio = dict(completed["audio"])
        completed_audio["data_base64"] = base64.b64encode(pcm).decode("ascii")
        completed["audio"] = completed_audio
        self._transfers.pop(key, None)
        self._wipe_transfer(transfer)
        return completed

    def _purge_expired_locked(self) -> None:
        cutoff = self._clock_ms() - self.transfer_ttl_ms
        expired = [key for key, value in self._transfers.items() if value.created_at_ms < cutoff]
        for key in expired:
            self._wipe_transfer(self._transfers.pop(key))

    @staticmethod
    def _wipe_transfer(transfer: _InboundAudioTransfer) -> None:
        for chunk in transfer.chunks.values():
            chunk[:] = b"\x00" * len(chunk)
        transfer.chunks.clear()


class RemoteWhisperNodeService:
    def __init__(
        self,
        config: RemoteWhisperNodeConfig | None = None,
        *,
        transcriber: Callable[[Path, str, WhisperProfile], WhisperTranscription] | None = None,
        clock_ms: Callable[[], int] | None = None,
        dependency_available: Callable[[], bool] | None = None,
    ) -> None:
        self.config = config or RemoteWhisperNodeConfig.from_environment()
        self._transcriber = transcriber or (
            lambda path, language, profile: transcribe_audio_detailed(
                path,
                language,
                profile=profile,
            )
        )
        self._clock_ms = clock_ms or (lambda: int(time.time() * 1_000))
        self._dependency_available = dependency_available or faster_whisper_available
        self._lock = threading.RLock()
        self._active: dict[tuple[str, str], _ActiveRequest] = {}
        self._results: OrderedDict[tuple[str, str], tuple[str, dict[str, Any]]] = OrderedDict()
        self._executor = ThreadPoolExecutor(
            max_workers=self.config.workers,
            thread_name_prefix="galaxyssi-remote-whisper",
        )

    def capability(self, client_route_id: str = "") -> dict[str, Any]:
        profiles = supported_remote_profiles()
        selected = whisper_profile(self.config.model_profile_id)
        supported_ids = {profile.profile_id for profile in profiles}
        dependency_ready = bool(self._dependency_available())
        enabled = self.config.enabled and dependency_ready and selected.profile_id in supported_ids
        reason = ""
        if not self.config.enabled:
            reason = "disabled"
        elif not dependency_ready:
            reason = "faster_whisper_unavailable"
        elif selected.profile_id not in supported_ids:
            reason = "unsupported_profile"
        return {
            "enabled": enabled,
            "available": enabled,
            "reason_code": reason,
            "protocol": PROTOCOL,
            "execution_device": {
                "device_id": desktop_id(),
                "device_name": desktop_name(),
                "kind": "desktop",
            },
            "active_profile": selected.public(),
            "model_profiles": [profile.public() for profile in profiles],
            "supported_audio": [AUDIO_FORMAT],
            "max_pcm_bytes": self.config.max_pcm_bytes,
            "max_duration_ms": self.config.max_pcm_bytes * 1_000 // (16_000 * 2),
            "authorization": {
                "explicit_user_consent_required": True,
                "paired_device_identity_required": True,
                "only_my_devices": True,
                "scope": CONSENT_SCOPE,
                "client_route_id": str(client_route_id or ""),
            },
            "retention": {
                "raw_audio": "ephemeral",
                "delete_after_decode": True,
                "content_logging": False,
            },
        }

    def process(
        self,
        payload: Mapping[str, Any],
        *,
        client_route_id: str,
        paired_client: Mapping[str, Any] | None,
    ) -> dict[str, Any]:
        request_id = str(payload.get("request_id") or "")
        try:
            request = self._validate(payload, client_route_id, paired_client)
            return self._process_validated(request)
        except RemoteWhisperError as exc:
            return self._error_payload(request_id, exc.code, str(exc))
        except Exception as exc:
            return self._error_payload(request_id, "decode_failed", str(exc) or "Remote transcription failed")

    def submit(
        self,
        payload: Mapping[str, Any],
        *,
        client_route_id: str,
        paired_client: Mapping[str, Any] | None,
        on_result: Callable[[dict[str, Any]], None],
    ) -> None:
        request_copy = dict(payload)

        def run() -> None:
            on_result(
                self.process(
                    request_copy,
                    client_route_id=client_route_id,
                    paired_client=paired_client,
                )
            )

        self._executor.submit(run)

    def cancel(self, payload: Mapping[str, Any], *, client_route_id: str) -> dict[str, Any]:
        request_id = _valid_uuid(payload.get("request_id"), "request_id")
        requested_route = str(payload.get("client_route_id") or "")
        if requested_route != client_route_id:
            return self._error_payload(request_id, "identity_mismatch", "Client route does not own this request")
        key = (client_route_id, request_id)
        with self._lock:
            active = self._active.get(key)
            if active is not None:
                active.cancel.set()
        return self._base_payload(CANCELLED_TYPE, request_id, status="cancelled", active=active is not None)

    def shutdown(self) -> None:
        self._executor.shutdown(wait=False, cancel_futures=True)

    def _process_validated(self, request: ValidatedRemoteWhisperRequest) -> dict[str, Any]:
        key = (request.client_route_id, request.request_id)
        owner = False
        with self._lock:
            cached = self._results.get(key)
            if cached is not None:
                digest, result = cached
                if digest != request.request_digest:
                    raise RemoteWhisperError("idempotency_conflict", "Request ID was reused with different audio")
                duplicate = dict(result)
                duplicate["duplicate"] = True
                return duplicate
            active = self._active.get(key)
            if active is None:
                active = _ActiveRequest(request.request_digest)
                self._active[key] = active
                owner = True
            elif active.request_digest != request.request_digest:
                raise RemoteWhisperError("idempotency_conflict", "Request ID was reused with different audio")
        if not owner:
            if not active.done.wait(timeout=240.0):
                raise RemoteWhisperError("duplicate_wait_timeout", "The original request is still running")
            with self._lock:
                cached = self._results.get(key)
                if cached is None:
                    raise RemoteWhisperError("duplicate_result_unavailable", "The original request did not complete")
                duplicate = dict(cached[1])
                duplicate["duplicate"] = True
                return duplicate

        result: dict[str, Any]
        temporary_directory: Path | None = None
        audio_path: Path | None = None
        cleanup_verified = False
        started_at = self._clock_ms()
        try:
            if active.cancel.is_set():
                raise RemoteWhisperError("cancelled", "Remote transcription was cancelled")
            self.config.temp_root.mkdir(parents=True, exist_ok=True)
            temporary_directory = Path(
                tempfile.mkdtemp(prefix="request-", dir=str(self.config.temp_root))
            )
            audio_path = temporary_directory / "audio.wav"
            _write_pcm_wav(audio_path, request.pcm)
            transcription = self._transcriber(audio_path, request.language, request.profile)
            if active.cancel.is_set():
                raise RemoteWhisperError("cancelled", "Remote transcription was cancelled")
            text = str(transcription.text or "").strip()
            if not text:
                raise RemoteWhisperError("empty_transcript", "Remote transcription returned no speech")
            result = self._base_payload(
                RESULT_TYPE,
                request.request_id,
                status="completed",
                voice_session_id=request.voice_session_id,
                transcript_id=request.transcript_id,
                content=text,
                language=transcription.language,
                confidence=transcription.language_probability,
                provider="faster-whisper",
                model_profile_id=transcription.profile.profile_id,
                model_profile_sha256=transcription.profile.profile_sha256,
                audio_sha256=request.pcm_sha256,
                duration_ms=request.duration_ms,
                processing_ms=max(0, self._clock_ms() - started_at),
            )
        except RemoteWhisperError as exc:
            event_type = CANCELLED_TYPE if exc.code == "cancelled" else ERROR_TYPE
            result = self._base_payload(
                event_type,
                request.request_id,
                status="cancelled" if exc.code == "cancelled" else "failed",
                error_code=exc.code,
                error_message=str(exc),
                voice_session_id=request.voice_session_id,
                transcript_id=request.transcript_id,
            )
        except Exception as exc:
            result = self._error_payload(request.request_id, "decode_failed", str(exc) or "Remote transcription failed")
        finally:
            if audio_path is not None:
                _secure_delete(audio_path)
            if temporary_directory is not None:
                shutil.rmtree(temporary_directory, ignore_errors=True)
                cleanup_verified = not temporary_directory.exists()
            result["cleanup"] = {
                "policy": "ephemeral_delete_after_decode",
                "requested": request.deletion_requested,
                "verified": cleanup_verified,
            }
            with self._lock:
                self._results[key] = (request.request_digest, dict(result))
                self._results.move_to_end(key)
                while len(self._results) > self.config.cache_entries:
                    self._results.popitem(last=False)
                self._active.pop(key, None)
                active.done.set()
        return result

    def _validate(
        self,
        payload: Mapping[str, Any],
        client_route_id: str,
        paired_client: Mapping[str, Any] | None,
    ) -> ValidatedRemoteWhisperRequest:
        capability = self.capability(client_route_id)
        if not capability["available"]:
            raise RemoteWhisperError("node_unavailable", str(capability.get("reason_code") or "Remote node unavailable"))
        if payload.get("type") != REQUEST_TYPE or payload.get("protocol") != PROTOCOL:
            raise RemoteWhisperError("protocol_invalid", "Unsupported remote Whisper protocol")
        if not paired_client or not str(paired_client.get("signal_name") or ""):
            raise RemoteWhisperError("identity_required", "A paired device identity is required")
        requested_route = str(payload.get("client_route_id") or "")
        if not client_route_id or requested_route != client_route_id:
            raise RemoteWhisperError("identity_mismatch", "Client route does not match the encrypted pairing")
        client_id = str(payload.get("client_id") or "")
        if client_id != str(paired_client.get("signal_name") or ""):
            raise RemoteWhisperError("identity_mismatch", "Client identity does not match the paired device")

        authorization = payload.get("authorization")
        if not isinstance(authorization, Mapping):
            raise RemoteWhisperError("authorization_required", "Explicit remote voice authorization is required")
        if (
            authorization.get("explicit") is not True
            or authorization.get("only_my_devices") is not True
            or authorization.get("scope") != CONSENT_SCOPE
        ):
            raise RemoteWhisperError("authorization_required", "Remote voice authorization is incomplete")
        authorized_at = int(authorization.get("authorized_at_ms") or 0)
        age = self._clock_ms() - authorized_at
        if authorized_at <= 0 or age < -60_000 or age > self.config.consent_max_age_ms:
            raise RemoteWhisperError("authorization_expired", "Remote voice authorization is stale")

        request_id = _valid_uuid(payload.get("request_id"), "request_id")
        voice_session_id = _bounded_text(payload.get("voice_session_id"), "voice_session_id", 160)
        transcript_id = _bounded_text(payload.get("transcript_id"), "transcript_id", 160)
        language = _bounded_text(payload.get("language") or "auto", "language", 32)
        model = payload.get("model")
        if not isinstance(model, Mapping):
            raise RemoteWhisperError("model_profile_required", "Remote model profile is required")
        profile = whisper_profile(str(model.get("profile_id") or ""))
        selected = whisper_profile(self.config.model_profile_id)
        if profile.profile_id != selected.profile_id:
            raise RemoteWhisperError("model_profile_mismatch", "Requested model is not active on this node")
        if str(model.get("profile_sha256") or "").lower() != selected.profile_sha256:
            raise RemoteWhisperError("model_profile_mismatch", "Model profile identity could not be verified")

        audio = payload.get("audio")
        if not isinstance(audio, Mapping) or audio.get("format") != AUDIO_FORMAT:
            raise RemoteWhisperError("audio_format_invalid", "PCM16 16 kHz mono audio is required")
        if int(audio.get("sample_rate_hz") or 0) != 16_000 or int(audio.get("channels") or 0) != 1:
            raise RemoteWhisperError("audio_format_invalid", "PCM16 16 kHz mono audio is required")
        encoded = str(audio.get("data_base64") or "")
        if not encoded or len(encoded) > ((self.config.max_pcm_bytes + 2) // 3 * 4 + 4):
            raise RemoteWhisperError("audio_size_invalid", "Remote audio exceeds the configured limit")
        try:
            pcm = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise RemoteWhisperError("audio_base64_invalid", "Remote audio encoding is invalid") from exc
        if not pcm or len(pcm) % 2 or len(pcm) > self.config.max_pcm_bytes:
            raise RemoteWhisperError("audio_size_invalid", "Remote PCM length is invalid")
        byte_count = int(audio.get("byte_count") or 0)
        sample_count = int(audio.get("sample_count") or 0)
        if byte_count != len(pcm) or sample_count != len(pcm) // 2:
            raise RemoteWhisperError("audio_length_mismatch", "Remote PCM length metadata does not match")
        pcm_sha256 = hashlib.sha256(pcm).hexdigest()
        if str(audio.get("sha256") or "").lower() != pcm_sha256:
            raise RemoteWhisperError("audio_integrity_failed", "Remote PCM integrity check failed")
        duration_ms = sample_count * 1_000 // 16_000
        declared_duration = int(audio.get("duration_ms") or 0)
        if abs(declared_duration - duration_ms) > 1:
            raise RemoteWhisperError("audio_length_mismatch", "Remote PCM duration metadata does not match")

        request_digest = hashlib.sha256(
            "|".join(
                (
                    client_route_id,
                    request_id,
                    voice_session_id,
                    transcript_id,
                    pcm_sha256,
                    selected.profile_sha256,
                )
            ).encode("utf-8")
        ).hexdigest()
        return ValidatedRemoteWhisperRequest(
            request_id=request_id,
            voice_session_id=voice_session_id,
            transcript_id=transcript_id,
            client_route_id=client_route_id,
            client_id=client_id,
            language=language,
            profile=selected,
            pcm=pcm,
            pcm_sha256=pcm_sha256,
            sample_count=sample_count,
            duration_ms=duration_ms,
            request_digest=request_digest,
            deletion_requested=bool(authorization.get("request_audio_deletion", True)),
        )

    def _base_payload(self, event_type: str, request_id: str, **values: Any) -> dict[str, Any]:
        return {
            "type": event_type,
            "protocol": PROTOCOL,
            "request_id": request_id,
            "desktop_id": desktop_id(),
            "desktop_name": desktop_name(),
            "server_time_ms": self._clock_ms(),
            **values,
        }

    def _error_payload(self, request_id: str, code: str, message: str) -> dict[str, Any]:
        return self._base_payload(
            ERROR_TYPE,
            request_id,
            status="failed",
            error_code=code,
            error_message=message[:240],
        )


def _write_pcm_wav(path: Path, pcm: bytes) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16_000)
        output.writeframes(pcm)


def _secure_delete(path: Path) -> None:
    try:
        size = path.stat().st_size
        with path.open("r+b", buffering=0) as handle:
            remaining = size
            zeros = bytes(min(64 * 1024, max(1, size)))
            while remaining > 0:
                chunk = zeros[: min(len(zeros), remaining)]
                handle.write(chunk)
                remaining -= len(chunk)
            handle.flush()
            os.fsync(handle.fileno())
    except OSError:
        pass
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _valid_uuid(value: Any, field_name: str) -> str:
    text = str(value or "").strip()
    try:
        return str(uuid.UUID(text))
    except (ValueError, AttributeError, TypeError) as exc:
        raise RemoteWhisperError("request_invalid", f"{field_name} must be a UUID") from exc


def _bounded_text(value: Any, field_name: str, limit: int) -> str:
    text = str(value or "").strip()
    if not text or len(text) > limit:
        raise RemoteWhisperError("request_invalid", f"{field_name} is invalid")
    return text


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


_remote_whisper_node: RemoteWhisperNodeService | None = None
_remote_whisper_assembler: RemoteWhisperRequestAssembler | None = None
_remote_whisper_lock = threading.RLock()


def remote_whisper_node() -> RemoteWhisperNodeService:
    global _remote_whisper_node
    if _remote_whisper_node is None:
        with _remote_whisper_lock:
            if _remote_whisper_node is None:
                _remote_whisper_node = RemoteWhisperNodeService()
    return _remote_whisper_node


def remote_whisper_assembler() -> RemoteWhisperRequestAssembler:
    global _remote_whisper_assembler
    if _remote_whisper_assembler is None:
        with _remote_whisper_lock:
            if _remote_whisper_assembler is None:
                _remote_whisper_assembler = RemoteWhisperRequestAssembler(
                    max_pcm_bytes=remote_whisper_node().config.max_pcm_bytes
                )
    return _remote_whisper_assembler
