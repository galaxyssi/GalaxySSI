"""Prepare bounded Microsoft neural speech outside the coding Agent's sandbox."""
import asyncio
import json
from pathlib import Path
from tempfile import TemporaryDirectory

from edge_tts_service import synthesize_edge_speech
from video_generation_policy import VIDEO_NARRATION_VOICE
from video_transport import VideoError, media_executable, run_media


async def _speech_with_checks(text, *, rate, check, timeout=45):
    check()
    # The service's language selects a voice, not a translation of the supplied text.
    task = asyncio.create_task(synthesize_edge_speech(text, "zh-CN", rate_percent=rate * 10))
    deadline = asyncio.get_running_loop().time() + timeout
    try:
        while True:
            check()
            remaining = deadline - asyncio.get_running_loop().time()
            if remaining <= 0:
                raise VideoError("video_narration_timeout: Microsoft TTS did not finish; retry when online")
            done, _ = await asyncio.wait({task}, timeout=min(0.2, remaining))
            if done:
                check()
                try:
                    speech = task.result()
                except Exception as exc:
                    raise VideoError("video_narration_unavailable: Microsoft TTS failed; voice was not replaced") from exc
                if not speech.audio:
                    raise VideoError("video_narration_empty: Microsoft TTS returned no samples")
                if speech.voice != VIDEO_NARRATION_VOICE:
                    raise VideoError("video_narration_voice_mismatch: Xiaoxiao is required; voice was not replaced")
                return speech
    finally:
        if not task.done():
            task.cancel()
        await asyncio.gather(task, return_exceptions=True)


def synthesize_neural_clip(text, output, *, rate, check):
    speech = asyncio.run(_speech_with_checks(text, rate=rate, check=check))
    check()
    if output.is_symlink():
        raise VideoError("video_narration_path_rejected")
    with TemporaryDirectory(prefix="speech-", dir=output.parent) as directory:
        compressed = Path(directory) / "speech.mp3"
        compressed.write_bytes(speech.audio)
        run_media([media_executable("ffmpeg"), "-y", "-v", "error", "-i", str(compressed),
                   "-vn", "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", str(output)],
                  check=check, timeout=30)
    if not output.is_file() or output.stat().st_size <= 44:
        raise VideoError("video_narration_empty: decoded speech returned no samples")
    raw = run_media([media_executable("ffprobe"), "-v", "error", "-show_entries", "format=duration",
                     "-of", "json", str(output)], check=check, timeout=15)
    try:
        duration = float(json.loads(raw)["format"]["duration"])
        if not 0 < duration <= 120:
            raise ValueError()
        return duration
    except (ValueError, TypeError, KeyError):
        raise VideoError("video_narration_invalid_duration") from None


def prepare_local_narration(plan, private, *, check, synthesize=None, progress=None):
    if plan.get("audio_mode") != "narration":
        return False
    neural = synthesize is None
    synthesize = synthesize or synthesize_neural_clip
    root = private.resolve()
    manifest = private / "narration.json"
    if private.is_symlink() or manifest.is_symlink():
        raise VideoError("video_narration_path_rejected")
    manifest.unlink(missing_ok=True)
    cues = []
    for index, scene in enumerate(plan["scenes"]):
        check()
        output = private / f"narration-{index}.wav"
        if output.is_symlink() or not output.resolve().is_relative_to(root):
            raise VideoError("video_narration_path_rejected")
        available = scene["end"] - scene["start"] - 0.4
        duration = 0
        for rate in (0, 2):
            check()
            duration = synthesize(scene["narration"], output, rate=rate, check=check)
            if 0 < duration <= available:
                break
        else:
            raise VideoError(f"video_narration_too_long: scene {index}, speech={duration:.2f}s, "
                             f"slot={available:.2f}s; shorten narration, never truncate speech")
        start = scene["start"] + 0.2
        cue = {"scene_index": index, "start": start, "end": start + duration,
               "text": scene["narration"], "clip": output.name}
        if neural:
            cue.update(provider="microsoft-edge-tts", voice=VIDEO_NARRATION_VOICE,
                       rate_percent=rate * 10)
        cues.append(cue)
        if progress:
            progress(f"video_narration_{index}", f"Speech prepared: {index + 1}/{len(plan['scenes'])} scenes", "completed")
    check()
    manifest.write_text(json.dumps({"cues": cues}, ensure_ascii=False, indent=2), encoding="utf-8")
    return True
