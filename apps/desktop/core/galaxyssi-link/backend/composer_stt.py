"""Local-only dictation for the Desktop composer, separate from remote ASR profiles."""
from __future__ import annotations

import asyncio
import io
import logging
import os
import threading

from fastapi import APIRouter, HTTPException, Request

MAX_AUDIO_BYTES = 8 * 1024 * 1024
MAX_AUDIO_SECONDS = 120
SAMPLE_RATE = 16_000
MEDIA_TYPES = {"audio/webm", "audio/ogg", "audio/wav", "audio/x-wav"}
log = logging.getLogger(__name__)
_lock = threading.Lock()
_model = None


class DictationError(Exception):
    def __init__(self, code: str, status: int = 422):
        super().__init__(code)
        self.code = code
        self.status = status


def decode_audio(data: bytearray):
    import av
    import numpy as np

    chunks = []
    samples = 0
    try:
        with io.BytesIO(data) as source, av.open(source) as container:
            resampler = av.AudioResampler(format="fltp", layout="mono", rate=SAMPLE_RATE)
            for frame in container.decode(audio=0):
                for converted in resampler.resample(frame):
                    chunk = converted.to_ndarray().reshape(-1).copy()
                    chunks.append(chunk)
                    samples += chunk.size
                    if samples > MAX_AUDIO_SECONDS * SAMPLE_RATE:
                        raise DictationError("stt_audio_too_long")
            for converted in resampler.resample(None):
                chunk = converted.to_ndarray().reshape(-1).copy()
                chunks.append(chunk)
                samples += chunk.size
        if samples > MAX_AUDIO_SECONDS * SAMPLE_RATE:
            raise DictationError("stt_audio_too_long")
        if samples < SAMPLE_RATE // 4:
            raise DictationError("stt_audio_too_short")
        return np.concatenate(chunks)
    except DictationError:
        raise
    except Exception as exc:
        raise DictationError("stt_invalid_audio") from exc
    finally:
        for chunk in chunks:
            chunk.fill(0)


def transcribe(data: bytearray, language: str) -> dict:
    global _model
    if not _lock.acquire(blocking=False):
        data[:] = b"\0" * len(data)
        raise DictationError("stt_busy", 409)
    pcm = None
    try:
        try:
            from faster_whisper import WhisperModel
        except ImportError as exc:
            raise DictationError("stt_runtime_missing", 503) from exc
        pcm = decode_audio(data)
        if _model is None:
            try:
                from huggingface_hub.errors import LocalEntryNotFoundError

                name = os.environ.get("GALAXYSSI_COMPOSER_WHISPER_MODEL", "medium")
                options = dict(device="cpu", compute_type="int8", cpu_threads=min(4, os.cpu_count() or 1), num_workers=1)
                # A fully cached model must not wait for a network metadata check.
                try:
                    _model = WhisperModel(name, local_files_only=True, **options)
                except LocalEntryNotFoundError:
                    _model = WhisperModel(name, **options)
            except Exception as exc:
                log.warning("Composer ASR model preparation failed (%s)", type(exc).__name__)
                raise DictationError("stt_model_unavailable", 503) from exc
        selected_language = str(language or "auto").lower().split("-", 1)[0]
        segments, info = _model.transcribe(
            pcm, language=None if selected_language == "auto" else selected_language,
            vad_filter=True, beam_size=5, condition_on_previous_text=False,
        )
        text = "".join(segment.text for segment in segments).strip()
        if not text:
            raise DictationError("stt_no_speech")
        return {"ok": True, "text": text, "language": info.language}
    except DictationError:
        raise
    except Exception as exc:
        log.warning("Composer ASR failed (%s)", type(exc).__name__)
        raise DictationError("stt_transcription_failed", 500) from exc
    finally:
        if pcm is not None:
            pcm.fill(0)
        data[:] = b"\0" * len(data)
        _lock.release()


def create_router(authorize) -> APIRouter:
    router = APIRouter()

    @router.post("/api/stt/transcribe")
    async def transcribe_request(request: Request):
        authorize(request)
        if request.headers.get("content-type", "").split(";", 1)[0] not in MEDIA_TYPES:
            raise HTTPException(415, detail={"code": "stt_invalid_audio"})
        data = bytearray()
        handed_off = False
        try:
            async for chunk in request.stream():
                if len(data) + len(chunk) > MAX_AUDIO_BYTES:
                    raise HTTPException(413, detail={"code": "stt_audio_too_large"})
                data.extend(chunk)
            if not data:
                raise HTTPException(400, detail={"code": "stt_audio_too_short"})
            language = request.headers.get("x-galaxyssi-language", "auto")[:16]
            # The worker owns and clears audio, even if the HTTP client disconnects.
            worker = asyncio.create_task(asyncio.to_thread(transcribe, data, language))
            handed_off = True
            try:
                result = await asyncio.shield(worker)
            except asyncio.CancelledError:
                worker.add_done_callback(lambda task: task.exception() if not task.cancelled() else None)
                raise
            return result
        except DictationError as exc:
            raise HTTPException(exc.status, detail={"code": exc.code}) from exc
        finally:
            if not handed_off:
                data[:] = b"\0" * len(data)

    return router
