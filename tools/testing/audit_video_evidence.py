"""Offline inspection of MP4 bytes actually received by the Android device.

ASR is an acceptance aid, not a semantic-quality score. Models must already be cached.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scene-seconds", type=float, default=10)
    parser.add_argument("--asr-model", default="small")
    parser.add_argument("--require-narration", action="store_true")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise RuntimeError("FFmpeg and FFprobe required")
    report = {"status": "running", "file": str(args.video.resolve()),
              "sha256": hashlib.sha256(args.video.read_bytes()).hexdigest(),
              "size_bytes": args.video.stat().st_size}
    started = time.monotonic()
    try:
        raw = subprocess.run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json",
                              str(args.video)], capture_output=True, check=True, timeout=30)
        media = json.loads(raw.stdout)
        report["media"] = media
        duration = float(media["format"]["duration"])
        if not 0 < duration <= 600 or args.scene_seconds <= 0:
            raise ValueError("Invalid bounded video/scene duration")
        subprocess.run([ffmpeg, "-v", "error", "-xerror", "-i", str(args.video), "-f", "null", "-"],
                       capture_output=True, check=True, timeout=180)
        report["full_decode"] = "passed"
        has_audio = any(stream["codec_type"] == "audio" for stream in media["streams"])
        report["has_audio"] = has_audio
        if args.require_narration and not has_audio:
            raise RuntimeError("Required narration is missing")
        if has_audio and args.require_narration:
            audio = args.output.with_suffix(".wav")
            subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(args.video), "-map", "0:a:0",
                            "-ar", "16000", "-ac", "1", str(audio)],
                           capture_output=True, check=True, timeout=60)
            from faster_whisper import WhisperModel
            model = WhisperModel(args.asr_model, device="cpu", compute_type="int8", cpu_threads=2,
                                 num_workers=1, local_files_only=True)
            segments, _ = model.transcribe(str(audio), language="zh", beam_size=3, vad_filter=True,
                                           condition_on_previous_text=False, word_timestamps=True)
            speech = [{"start": segment.start, "end": segment.end, "text": segment.text,
                       "words": [{"start": word.start, "end": word.end, "word": word.word}
                                 for word in (segment.words or [])]} for segment in segments]
            report["asr_model"] = args.asr_model
            report["speech_segments"] = speech
            scenes = []
            start = 0.0
            while start < duration - 0.25:
                end = min(start + args.scene_seconds, duration)
                words = [word for segment in speech for word in segment["words"]
                         if start <= (word["start"] + word["end"]) / 2 < end]
                scenes.append({"start": start, "end": end, "recognized_text": "".join(w["word"] for w in words)})
                start = end
            report["scene_speech"] = scenes
            if not speech or any(not scene["recognized_text"].strip() for scene in scenes):
                raise RuntimeError("ASR found a scene without recognizable speech; manual inspection required")
        report["status"] = "passed_technical_checks"
        report["semantic_quality"] = "Requires transcript and frame review, not inferred from ASR presence"
    except Exception as exc:
        report["status"] = "failed"
        report["error"] = str(exc)
        raise
    finally:
        report["audit_seconds"] = round(time.monotonic() - started, 3)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"status": report["status"], "report": str(args.output)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
