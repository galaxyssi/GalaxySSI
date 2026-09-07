import asyncio
import json
from types import SimpleNamespace

import pytest

import video_narration
from video_narration import _speech_with_checks, prepare_local_narration, synthesize_neural_clip
from video_transport import VideoError


def plan():
    return {"audio_mode": "narration", "scenes": [
        {"start": 0, "end": 10, "narration": "First"},
        {"start": 10, "end": 20, "narration": "Second"}]}


def test_local_speech_precedes_render_and_uses_measured_timing(tmp_path):
    calls = []
    def synthesize(text, output, **kwargs):
        calls.append(text)
        output.write_bytes(b"test fixture")
        return 3.5
    assert prepare_local_narration(plan(), tmp_path, check=lambda: None, synthesize=synthesize)
    cues = json.loads((tmp_path / "narration.json").read_text())["cues"]
    assert calls == ["First", "Second"]
    assert cues[1]["start"] == 10.2
    assert cues[1]["end"] == 13.7


def test_too_long_speech_is_not_silently_truncated(tmp_path):
    rates = []
    def synthesize(*args, rate, **kwargs):
        rates.append(rate)
        return 15
    with pytest.raises(VideoError, match="too_long"):
        prepare_local_narration(plan(), tmp_path, check=lambda: None, synthesize=synthesize)
    assert rates == [0, 2]
    assert not (tmp_path / "narration.json").exists()


def test_speech_preparation_checks_cancellation(tmp_path):
    def cancelled():
        raise VideoError("cancelled")
    with pytest.raises(VideoError, match="cancelled"):
        prepare_local_narration(plan(), tmp_path, check=cancelled, synthesize=lambda *a, **k: 1)


def test_silent_plan_never_calls_tts(tmp_path):
    def unexpected(*args, **kwargs):
        raise AssertionError("TTS must not run")
    assert not prepare_local_narration({"audio_mode": "none"}, tmp_path,
                                       check=lambda: None, synthesize=unexpected)


def test_default_uses_neural_voice_and_records_measured_cues(tmp_path, monkeypatch):
    monkeypatch.setattr(video_narration, "synthesize_neural_clip", lambda *a, **k: 2.5)
    value = plan()
    value["scenes"][0]["narration"] = "\u4e8c\u8fdb\u5236\u4e00\u96f6"
    assert prepare_local_narration(value, tmp_path, check=lambda: None)
    cues = json.loads((tmp_path / "narration.json").read_text(encoding="utf-8"))["cues"]
    assert cues[0]["voice"] == "zh-CN-XiaoxiaoNeural"
    assert cues[1]["voice"] == "en-US-AriaNeural"
    assert cues[0]["provider"] == "microsoft-edge-tts"
    assert cues[0]["rate_percent"] == 0
    assert cues[0]["end"] == 2.7


def test_neural_service_receives_language_and_bounded_rate(monkeypatch):
    calls = []
    async def speech(text, language, **kwargs):
        calls.append((text, language, kwargs))
        return SimpleNamespace(audio=b"mp3")
    monkeypatch.setattr(video_narration, "synthesize_edge_speech", speech)
    result = asyncio.run(_speech_with_checks("\u4f60\u597d", rate=2, check=lambda: None))
    assert result.audio == b"mp3"
    assert calls == [("\u4f60\u597d", "zh-CN", {"rate_percent": 20})]


@pytest.mark.parametrize("failure", ["empty", "network"])
def test_neural_failure_is_explicit_without_offline_voice_fallback(monkeypatch, failure):
    async def speech(*args, **kwargs):
        if failure == "network":
            raise ConnectionError("offline")
        return SimpleNamespace(audio=b"")
    monkeypatch.setattr(video_narration, "synthesize_edge_speech", speech)
    with pytest.raises(VideoError, match="narration_empty|narration_unavailable"):
        asyncio.run(_speech_with_checks("hello", rate=0, check=lambda: None))


@pytest.mark.parametrize("cancel", [False, True])
def test_inflight_speech_is_cancelled_and_drained(monkeypatch, cancel):
    closed = []
    async def speech(*args, **kwargs):
        try:
            await asyncio.sleep(60)
        finally:
            closed.append(True)
    checks = []
    def check():
        checks.append(True)
        if cancel and len(checks) >= 3:
            raise VideoError("cancelled")
    monkeypatch.setattr(video_narration, "synthesize_edge_speech", speech)
    with pytest.raises(VideoError, match="cancelled" if cancel else "narration_timeout"):
        asyncio.run(_speech_with_checks("hello", rate=0, check=check, timeout=1 if cancel else 0.02))
    assert closed == [True]


def test_neural_clip_converts_mp3_and_cleans_temporary_file(tmp_path, monkeypatch):
    async def speech(*args, **kwargs):
        return SimpleNamespace(audio=b"mp3")
    commands = []
    def media(command, **kwargs):
        commands.append(command)
        if command[0] == "ffmpeg":
            (tmp_path / "clip.wav").write_bytes(b"w" * 100)
            assert (tmp_path / command[command.index("-i") + 1]).read_bytes() == b"mp3"
            return b""
        return b'{"format":{"duration":"3.48"}}'
    monkeypatch.setattr(video_narration, "synthesize_edge_speech", speech)
    monkeypatch.setattr(video_narration, "media_executable", lambda name: name)
    monkeypatch.setattr(video_narration, "run_media", media)
    assert synthesize_neural_clip("hello", tmp_path / "clip.wav", rate=0, check=lambda: None) == 3.48
    assert list(tmp_path.iterdir()) == [tmp_path / "clip.wav"]
    assert "pcm_s16le" in commands[0]


def test_failed_refresh_does_not_leave_old_manifest(tmp_path):
    (tmp_path / "narration.json").write_text('{"cues":[]}')
    def speech(*args, **kwargs):
        raise VideoError("video_narration_unavailable")
    with pytest.raises(VideoError):
        prepare_local_narration(plan(), tmp_path, check=lambda: None, synthesize=speech)
    assert not (tmp_path / "narration.json").exists()


def test_progress_only_reports_prepared_cues(tmp_path):
    events = []
    assert prepare_local_narration(plan(), tmp_path, check=lambda: None,
                                   synthesize=lambda *a, **k: 1,
                                   progress=lambda *event: events.append(event))
    assert events == [("video_narration_0", "Speech prepared: 1/2 scenes", "completed"),
                      ("video_narration_1", "Speech prepared: 2/2 scenes", "completed")]
