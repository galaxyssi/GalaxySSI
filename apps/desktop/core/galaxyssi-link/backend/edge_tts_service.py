"""In-memory Microsoft Edge speech synthesis for Desktop reply playback."""

from __future__ import annotations

from dataclasses import dataclass


MAX_TTS_TEXT_CHARACTERS = 20_000
MAX_TTS_AUDIO_BYTES = 24 * 1024 * 1024

VOICE_BY_LANGUAGE = {
    "zh-CN": "zh-CN-XiaoxiaoNeural",
    "zh-HK": "zh-HK-HiuGaaiNeural",
    "zh-TW": "zh-TW-HsiaoChenNeural",
    "en-US": "en-US-AriaNeural",
}


@dataclass(frozen=True)
class SynthesizedSpeech:
    audio: bytes
    voice: str
    media_type: str = "audio/mpeg"


def voice_for_language(language: str) -> str:
    normalized = str(language or "").strip()
    return VOICE_BY_LANGUAGE.get(normalized, VOICE_BY_LANGUAGE["zh-CN"])


async def synthesize_edge_speech(text: str, language: str = "zh-CN") -> SynthesizedSpeech:
    normalized_text = str(text or "").strip()
    if not normalized_text:
        raise ValueError("Speech text is empty")
    if len(normalized_text) > MAX_TTS_TEXT_CHARACTERS:
        raise ValueError(f"Speech text exceeds {MAX_TTS_TEXT_CHARACTERS} characters")

    try:
        import edge_tts
    except ImportError as exc:
        raise RuntimeError("edge-tts is not installed in the Desktop runtime") from exc

    voice = voice_for_language(language)
    communicate = edge_tts.Communicate(text=normalized_text, voice=voice)
    audio = bytearray()
    try:
        async for chunk in communicate.stream():
            if chunk.get("type") != "audio":
                continue
            data = bytes(chunk.get("data") or b"")
            if len(audio) + len(data) > MAX_TTS_AUDIO_BYTES:
                raise RuntimeError("Synthesized speech exceeds the Desktop playback limit")
            audio.extend(data)
        if not audio:
            raise RuntimeError("Microsoft Edge TTS returned no audio")
        return SynthesizedSpeech(audio=bytes(audio), voice=voice)
    finally:
        audio.clear()
