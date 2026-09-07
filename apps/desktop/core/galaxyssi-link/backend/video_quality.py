"""Objective stream and per-scene narration checks, without a background ASR model."""
from __future__ import annotations

from array import array
import json
import math
from pathlib import Path
import sys

from video_transport import VideoError, MAX_SOURCE_BYTES, media_executable, run_media

ENVELOPE_SECONDS = 0.02
SAMPLE_RATE = 8000


def audio_envelope(path: Path, *, limit: float, check) -> list[float]:
    raw = run_media([media_executable("ffmpeg"), "-v", "error", "-nostdin", "-protocol_whitelist", "file,pipe",
                     "-i", str(path), "-map", "0:a:0", "-t", str(limit), "-ac", "1", "-ar", str(SAMPLE_RATE),
                     "-f", "s16le", "-"], check=check, timeout=max(30, limit))
    samples = array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    size = round(SAMPLE_RATE * ENVELOPE_SECONDS)
    return [math.sqrt(sum(value * value for value in samples[index:index + size]) /
                      len(samples[index:index + size])) / 32768
            for index in range(0, len(samples), size)]


def alignment(reference: list[float], received: list[float], start: float) -> dict:
    if not reference or max(reference) < 0.001:
        raise VideoError("video_narration_silent: a narration clip contains no audible signal")
    mean = sum(reference) / len(reference)
    centered = [value - mean for value in reference]
    norm = sum(value * value for value in centered)
    if norm <= 1e-10:
        raise VideoError("video_narration_unverifiable: audio envelope has no timing variation")
    offset = round(start / ENVELOPE_SECONDS)
    best = {"correlation": -1.0, "lag_seconds": 0.0}
    for shift in range(-25, 26):
        position = offset + shift
        segment = [received[i] if 0 <= i < len(received) else 0.0
                   for i in range(position, position + len(reference))]
        segment_mean = sum(segment) / len(segment)
        actual = [value - segment_mean for value in segment]
        denominator = math.sqrt(norm * sum(value * value for value in actual))
        score = sum(a * b for a, b in zip(centered, actual)) / denominator if denominator > 0 else -1.0
        if score > best["correlation"]:
            best = {"correlation": score, "lag_seconds": shift * ENVELOPE_SECONDS}
    return best


def verify_video_media(path: Path, plan: dict, info: dict, *, private: Path, check) -> dict:
    duration = plan["duration_seconds"]
    video = info.get("video_timing", {"start": 0, "end": info["duration"]})
    if abs(video["start"]) > 0.12 or abs(video["end"] - duration) > 0.5:
        raise VideoError("video_timeline_mismatch: video stream does not cover the storyboard")
    audio = info.get("audio_timing")
    if audio and (abs(audio["start"] - video["start"]) > 0.12 or abs(audio["end"] - video["end"]) > 0.25):
        raise VideoError("video_audio_timeline_mismatch: pad/trim the soundtrack to the video timeline")
    mode = plan.get("audio_mode", "unspecified")
    if mode == "none" and info["has_audio"]:
        raise VideoError("video_unexpected_audio: the approved plan requests a silent video")
    if mode in {"narration", "music"} and not info["has_audio"]:
        raise VideoError("video_audio_missing: the requested soundtrack was not produced")
    report = {"audio_mode": mode, "stream_timing_verified": True}
    if mode != "narration":
        return report
    manifest = private / "narration.json"
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 128 * 1024:
        raise VideoError("video_narration_manifest_missing: write narration.json with measured per-scene clips")
    try:
        cues = json.loads(manifest.read_text(encoding="utf-8-sig"))["cues"]
        if not isinstance(cues, list) or len(cues) != len(plan["scenes"]):
            raise ValueError("one narration clip per scene is required")
        received = audio_envelope(path, limit=duration + 0.5, check=check)
        results = []
        for index, (cue, scene) in enumerate(zip(cues, plan["scenes"])):
            check()
            start, end = float(cue["start"]), float(cue["end"])
            if (cue["scene_index"] != index or not math.isfinite(start) or not math.isfinite(end)
                    or not scene["start"] <= start < end <= scene["end"] + 0.02
                    or cue["text"].strip() != scene["narration"].strip()):
                raise ValueError("cue text or timing differs from the approved scene")
            clip = private / cue["clip"]
            if (clip.is_symlink() or not clip.resolve().is_relative_to(private.resolve())
                    or not clip.is_file() or not 0 < clip.stat().st_size <= MAX_SOURCE_BYTES):
                raise ValueError("narration clip path rejected")
            reference = audio_envelope(clip, limit=duration + 1, check=check)
            measured = len(reference) * ENVELOPE_SECONDS
            if abs(measured - (end - start)) > 0.12:
                raise ValueError("cue duration must match the actual clip, without truncation")
            result = alignment(reference, received, start)
            if result["correlation"] < 0.75 or abs(result["lag_seconds"]) > 0.12:
                raise VideoError(f"video_narration_sync_failed: scene {index}, "
                                 f"correlation={result['correlation']:.3f}, lag={result['lag_seconds']:.3f}s")
            results.append({"scene_index": index, **result})
        return {**report, "narration_cues": results}
    except (ValueError, KeyError, TypeError, OSError, AttributeError) as exc:
        raise VideoError(f"video_narration_manifest_invalid: {str(exc)[:200]}") from exc


def preview_times(plan: dict) -> list[float]:
    scenes = plan["scenes"]
    times = {(scene["start"] + scene["end"]) / 2 for scene in scenes}
    for previous, following in zip(scenes, scenes[1:]):
        margin = min(0.15, (previous["end"] - previous["start"]) / 4,
                     (following["end"] - following["start"]) / 4)
        times.update((previous["end"] - margin, following["start"] + margin))
    times.update(plan["duration_seconds"] * part for part in (0.05, 0.5, 0.95))
    return sorted(times)


NARRATION_RENDER_CONTRACT = """
If audio_mode is narration, the host supplies measured zh-CN-XiaoxiaoNeural clips for every scene,
including English scenes. Reuse those clips; do not synthesize alternative speech, select another
voice, or install software. If host clips are missing, report the failure instead of substituting TTS.
Use the approved scene narration verbatim. Never replace speech with tones/music, truncate words,
overlap adjacent scenes, or silently drop narration. Keep each clip within its scene's time interval.
If speech cannot fit, report the problem for a corrected plan; do not accelerate it beyond intelligibility.
Use one shared absolute timeline for frames, captions and delayed audio. Pad the soundtrack to the
exact video duration. Render captions from that timeline, not by independent per-frame counters.
Read the host-owned .video-generation/narration.json as {"cues":[{"scene_index":0,"start":0.2,"end":3.4,
"text":"exact approved narration","clip":"narration-0.wav"}, ...]} ordered by scene.
Do not rewrite the manifest or clips. Clip paths are relative to .video-generation. Keep them for
independent waveform alignment checks of both source and compressed video. Cue end equals start
plus the measured clip duration, including any silence. Voice activity should match the shown scene.
"""
