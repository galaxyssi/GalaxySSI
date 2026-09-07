import json
import math
import shutil
import subprocess
import wave
from array import array
from unittest.mock import patch

import pytest

from programmatic_video_task import parse_video_plan
from video_quality import alignment, preview_times, verify_video_media
from video_transport import VideoError, inspect_video, transcode_240p


def plan(mode="none", duration=6):
    return {"summary": "Calibration animation", "duration_seconds": duration, "audio_mode": mode,
            "scenes": [{"start": 0, "end": duration / 2, "description": "First", "narration": "First cue"},
                       {"start": duration / 2, "end": duration, "description": "Second", "narration": "Second cue"}]}


def info(audio=True, audio_start=0, audio_end=6, video_end=6):
    return {"duration": 6, "has_audio": audio, "video_timing": {"start": 0, "end": video_end},
            "audio_timing": {"start": audio_start, "end": audio_end} if audio else None}


@pytest.mark.parametrize("metadata,mode,error", [
    (info(audio=False), "narration", "audio_missing"), (info(), "none", "unexpected_audio"),
    (info(audio_start=0.5), "music", "audio_timeline_mismatch"),
    (info(audio_end=3), "music", "audio_timeline_mismatch"),
    (info(video_end=3), "music", "timeline_mismatch"),
])
def test_invalid_tracks_fail_before_success(tmp_path, metadata, mode, error):
    with pytest.raises(VideoError, match=error):
        verify_video_media(tmp_path / "missing.mp4", plan(mode), metadata, private=tmp_path, check=lambda: None)


def test_explicit_narration_requires_text_in_every_scene():
    value = plan("narration")
    assert parse_video_plan(json.dumps(value))["audio_mode"] == "narration"
    value["scenes"][1].pop("narration")
    with pytest.raises(VideoError, match="plan_invalid"):
        parse_video_plan(json.dumps(value))


def test_planner_must_declare_an_audio_mode():
    value = plan()
    value.pop("audio_mode")
    with pytest.raises(VideoError, match="plan_invalid"):
        parse_video_plan(json.dumps(value))


def test_scene_previews_cover_both_sides_of_transitions():
    times = preview_times(plan())
    assert 1.5 in times and 4.5 in times
    assert 2.85 in times and 3.15 in times
    assert all(0 < time < 6 for time in times)


def test_envelope_alignment_measures_delay_and_rejects_silence():
    reference = [0.1, 0.3, 0.0, 0.8, 0.5, 0.2, 0.0, 0.4]
    result = alignment(reference, [0.0] * 15 + reference + [0.0] * 20, 0.1)
    assert result["lag_seconds"] == pytest.approx(0.2)
    assert result["correlation"] == pytest.approx(1.0)
    with pytest.raises(VideoError, match="silent"):
        alignment([0.0] * 20, [0.0] * 100, 0)


@pytest.fixture
def media_tools():
    paths = {name: shutil.which(name) for name in ("ffmpeg", "ffprobe")}
    if not all(paths.values()):
        pytest.skip("FFmpeg and FFprobe required")
    with patch("video_transport.media_executable", side_effect=paths.get), \
         patch("video_quality.media_executable", side_effect=paths.get):
        yield paths


def calibration_video(root, tools, second_delay=0.0, duration=6):
    # Synthetic amplitude markers test timing only, never speech intelligibility.
    clips = []
    for index in range(2):
        clip = root / f"cue-{index}.wav"
        samples = array("h")
        for sample in range(20_000):
            t = sample / 8000
            level = (0.24 if 0.2 < t < 0.43 else 0.42 if 0.71 < t < 1.1 else
                     0.18 if 1.24 < t < 1.83 else 0.35 if 1.99 < t < 2.17 else 0.0)
            samples.append(round(32767 * level * math.sin(2 * math.pi * (330 + index * 170) * t)))
        with wave.open(str(clip), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(8000)
            output.writeframes(samples.tobytes())
        clips.append(clip)
    source = root / "source.mp4"
    delay_ms = round((duration / 2 + 0.2 + second_delay) * 1000)
    filters = (f"[1:a]adelay=200:all=1[a1];[2:a]adelay={delay_ms}:all=1[a2];"
               f"[a1][a2]amix=inputs=2:normalize=0,apad,atrim=duration={duration}[a]")
    subprocess.run([tools["ffmpeg"], "-v", "error", "-f", "lavfi", "-i", f"testsrc2=s=426x240:r=12:d={duration}",
                    "-i", str(clips[0]), "-i", str(clips[1]), "-filter_complex", filters,
                    "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "ultrafast",
                    "-threads", "2", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "64k", str(source)],
                   check=True, capture_output=True, timeout=90)
    cues = [{"scene_index": i, "start": 0.2 + i * duration / 2, "end": 2.7 + i * duration / 2,
             "text": scene["narration"], "clip": clips[i].name}
            for i, scene in enumerate(plan("narration", duration)["scenes"])]
    (root / "narration.json").write_text(json.dumps({"cues": cues}), encoding="utf-8")
    return source


@pytest.mark.parametrize("duration", [6, 60, 120])
def test_real_codec_roundtrip_preserves_per_scene_audio_timing(tmp_path, media_tools, duration):
    source = calibration_video(tmp_path, media_tools, duration=duration)
    report = verify_video_media(source, plan("narration", duration), inspect_video(source), private=tmp_path, check=lambda: None)
    assert len(report["narration_cues"]) == 2
    destination = tmp_path / "240p.mp4"
    result = transcode_240p(source, destination)
    compressed = verify_video_media(destination, plan("narration", duration), result, private=tmp_path, check=lambda: None)
    assert all(cue["correlation"] > 0.9 for cue in compressed["narration_cues"])
    assert all(abs(cue["lag_seconds"]) <= 0.04 for cue in compressed["narration_cues"])


def test_real_desynchronized_scene_fails_even_with_full_length_audio(tmp_path, media_tools):
    source = calibration_video(tmp_path, media_tools, second_delay=0.4)
    with pytest.raises(VideoError, match="narration_sync_failed"):
        verify_video_media(source, plan("narration"), inspect_video(source), private=tmp_path, check=lambda: None)


@pytest.mark.parametrize("change", ["missing_scene", "outside_path", "wrong_text", "truncated_clip"])
def test_narration_manifest_cannot_hide_missing_or_mismatched_speech(tmp_path, media_tools, change):
    source = calibration_video(tmp_path, media_tools)
    path = tmp_path / "narration.json"
    manifest = json.loads(path.read_text())
    if change == "missing_scene":
        manifest["cues"].pop()
    elif change == "outside_path":
        manifest["cues"][0]["clip"] = "../outside.wav"
    elif change == "wrong_text":
        manifest["cues"][0]["text"] = "Other speech"
    else:
        manifest["cues"][0]["end"] = 1.0
    path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(VideoError, match="manifest_invalid"):
        verify_video_media(source, plan("narration"), inspect_video(source), private=tmp_path, check=lambda: None)
