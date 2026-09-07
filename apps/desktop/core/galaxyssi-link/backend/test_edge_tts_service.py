import asyncio
import sys
import types

import pytest

from edge_tts_service import (
    MAX_TTS_TEXT_CHARACTERS,
    synthesize_edge_speech,
    voice_for_language,
)


def test_voice_catalog_uses_xiaoxiao_for_simplified_chinese_and_default():
    assert voice_for_language("zh-CN") == "zh-CN-XiaoxiaoNeural"
    assert voice_for_language("") == "zh-CN-XiaoxiaoNeural"
    assert voice_for_language("unsupported") == "zh-CN-XiaoxiaoNeural"


def test_synthesize_edge_speech_collects_only_audio(monkeypatch):
    calls = {}

    class FakeCommunicate:
        def __init__(self, *, text, voice, rate):
            calls.update(text=text, voice=voice, rate=rate)

        async def stream(self):
            yield {"type": "audio", "data": b"ID3"}
            yield {"type": "WordBoundary", "offset": 0}
            yield {"type": "audio", "data": b"payload"}

    monkeypatch.setitem(sys.modules, "edge_tts", types.SimpleNamespace(Communicate=FakeCommunicate))
    result = asyncio.run(synthesize_edge_speech("你好", "zh-CN"))

    assert result.audio == b"ID3payload"
    assert result.media_type == "audio/mpeg"
    assert result.voice == "zh-CN-XiaoxiaoNeural"
    assert calls == {"text": "你好", "voice": "zh-CN-XiaoxiaoNeural", "rate": "+0%"}


@pytest.mark.parametrize("text", ["", "   ", "x" * (MAX_TTS_TEXT_CHARACTERS + 1)])
def test_synthesize_edge_speech_rejects_invalid_text(text):
    with pytest.raises(ValueError):
        asyncio.run(synthesize_edge_speech(text))


@pytest.mark.parametrize("rate", [-51, 101, True, "20", 1.5])
def test_speech_rate_rejects_invalid_values(rate):
    with pytest.raises(ValueError, match="rate"):
        asyncio.run(synthesize_edge_speech("hello", rate_percent=rate))


def test_speech_rate_is_passed_to_edge(monkeypatch):
    calls = []
    class FakeCommunicate:
        def __init__(self, **kwargs):
            calls.append(kwargs)
        async def stream(self):
            yield {"type": "audio", "data": b"mp3"}
    monkeypatch.setitem(sys.modules, "edge_tts", types.SimpleNamespace(Communicate=FakeCommunicate))
    asyncio.run(synthesize_edge_speech("hello", rate_percent=20))
    assert calls[0]["rate"] == "+20%"
