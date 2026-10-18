import asyncio
import io
import threading
import types
import wave

import httpx
import numpy as np
import pytest
from fastapi import FastAPI, HTTPException

import composer_stt as stt


def wav(seconds=1):
    out = io.BytesIO()
    with wave.open(out, "wb") as writer:
        writer.setparams((1, 2, 16000, 0, "NONE", "NONE"))
        writer.writeframes(b"\0\0" * int(16000 * seconds))
    return bytearray(out.getvalue())


def test_decode_and_clear(monkeypatch):
    observed = []
    def recognize(pcm, **kwargs):
        observed.append(pcm)
        assert kwargs["language"] == "zh"
        return iter([types.SimpleNamespace(text="hello")]), types.SimpleNamespace(language="zh")
    monkeypatch.setattr(stt, "_model", types.SimpleNamespace(transcribe=recognize))
    audio = wav()
    assert stt.transcribe(audio, "zh-CN")["text"] == "hello"
    assert not any(audio)
    assert observed[0].size == 16000
    assert np.all(observed[0] == 0)


@pytest.mark.parametrize("audio,code", [(bytearray(b"bad"), "stt_invalid_audio"), (wav(0.1), "stt_audio_too_short"), (wav(120.1), "stt_audio_too_long")])
def test_decode_limits(audio, code):
    with pytest.raises(stt.DictationError, match=code):
        stt.decode_audio(audio)


def test_silence_has_specific_error_and_clears_audio(monkeypatch):
    monkeypatch.setattr(stt, "_model", types.SimpleNamespace(transcribe=lambda *a, **k: (iter([]), types.SimpleNamespace(language="en"))))
    audio = wav()
    with pytest.raises(stt.DictationError, match="stt_no_speech"):
        stt.transcribe(audio, "auto")
    assert not any(audio)


def test_busy_does_not_queue_or_reload_models():
    audio = wav()
    with stt._lock:
        with pytest.raises(stt.DictationError, match="stt_busy"):
            stt.transcribe(audio, "auto")
    assert not any(audio)


def test_model_load_failure_clears_audio(monkeypatch):
    import faster_whisper
    def fail(*args, **kwargs):
        raise OSError("download unavailable")
    monkeypatch.setattr(stt, "_model", None)
    monkeypatch.setattr(faster_whisper, "WhisperModel", fail)
    audio = wav()
    with pytest.raises(stt.DictationError, match="stt_model_unavailable"):
        stt.transcribe(audio, "auto")
    assert not any(audio)
    assert not stt._lock.locked()


def application():
    app = FastAPI()
    def authorize(request):
        if request.headers.get("x-galaxyssi-token") != "test-token":
            raise HTTPException(401)
    app.include_router(stt.create_router(authorize))
    return app


@pytest.mark.parametrize("headers,data,status", [
    ({}, b"x", 401),
    ({"x-galaxyssi-token": "test-token", "content-type": "text/plain"}, b"x", 415),
    ({"x-galaxyssi-token": "test-token", "content-type": "audio/webm"}, b"", 400),
    ({"x-galaxyssi-token": "test-token", "content-type": "audio/webm"}, b"x" * (stt.MAX_AUDIO_BYTES + 1), 413),
], ids=["unauthorized", "unsupported-type", "empty", "oversized"])
def test_endpoint_validates_before_transcription(headers, data, status, monkeypatch):
    monkeypatch.setattr(stt, "transcribe", lambda *a: pytest.fail("must not transcribe"))
    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=application()), base_url="http://local") as client:
            response = await client.post("/api/stt/transcribe", content=data, headers=headers)
            assert response.status_code == status
    asyncio.run(run())


def test_inference_runs_off_event_loop(monkeypatch):
    main_thread = threading.get_ident()
    def transcribe(audio, language):
        assert threading.get_ident() != main_thread
        assert language == "zh-CN"
        audio[:] = b"\0" * len(audio)
        return {"ok": True, "text": "hello"}
    monkeypatch.setattr(stt, "transcribe", transcribe)
    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=application()), base_url="http://local") as client:
            response = await client.post("/api/stt/transcribe", content=b"audio", headers={"content-type": "audio/webm", "x-galaxyssi-token": "test-token", "x-galaxyssi-language": "zh-CN"})
            assert response.json()["text"] == "hello"
    asyncio.run(run())
