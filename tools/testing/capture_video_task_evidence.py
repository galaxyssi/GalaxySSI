"""Opt-in capture of an owned video test before task-output acknowledgement cleanup."""
import argparse
import json
from pathlib import Path
import re
import shutil
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps/desktop/core/galaxyssi-link/backend"))
from secure_state import read_secure_json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("task_directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()
    source = args.task_directory / ".video-generation"
    args.output.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + args.timeout
    seen = {}
    status = None
    while time.monotonic() < deadline:
        if source.is_dir() and not source.is_symlink():
            for path in source.iterdir():
                if not re.fullmatch(r"render\.py|narration\.json|narration-\d+\.wav|preview-\d+\.png|source\.mp4|playback\.mp4", path.name):
                    continue
                if path.is_symlink() or not path.is_file():
                    continue
                stat = path.stat()
                stamp = (stat.st_size, stat.st_mtime_ns)
                if 0 < stat.st_size <= 64 * 1024 * 1024 and stamp != seen.get(path.name):
                    try:
                        shutil.copy2(path, args.output / path.name)
                        seen[path.name] = stamp
                    except OSError:
                        pass
            checkpoint = source / "job.json"
            if checkpoint.is_file() and not checkpoint.is_symlink():
                try:
                    state = read_secure_json(checkpoint, purpose="programmatic-video-job-v1",
                                             allow_legacy_plaintext=False).value
                    safe = {key: state[key] for key in ("status", "plan", "media", "media_review",
                            "playback_media_review", "visual_review", "review_feedback", "source_sha256",
                            "output_sha256") if key in state}
                    (args.output / "verification.json").write_text(
                        json.dumps(safe, ensure_ascii=False, indent=2), encoding="utf-8")
                    if state.get("status") != status:
                        status = state.get("status")
                        print(f"Video evidence: {status}", flush=True)
                    if status == "completed":
                        return
                except (OSError, ValueError):
                    pass
        time.sleep(2)
    print("Capture timed out; partial evidence retained", flush=True)


if __name__ == "__main__":
    main()
