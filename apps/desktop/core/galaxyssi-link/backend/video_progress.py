"""Report actual render-file changes without keeping an idle Agent alive."""
from contextlib import contextmanager
import hashlib
from pathlib import Path
import threading


def render_fingerprint(directory):
    result = {}
    paths = [directory / "render.py", directory / "source.mp4"]
    for folder in (directory, directory / "previews"):
        if folder.is_dir() and not folder.is_symlink():
            paths.extend(list(folder.glob("*.png"))[:64])
    for path in paths:
        try:
            if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(directory.resolve()):
                continue
            size = path.stat().st_size
            if not 0 < size <= 64 * 1024 * 1024:
                continue
            if path.suffix == ".mp4":
                value = size
            elif size <= 5 * 1024 * 1024:
                value = hashlib.sha256(path.read_bytes()).hexdigest()
            else:
                continue
            result[path.name] = value
        except OSError:
            continue
    return result


@contextmanager
def track_render_progress(directory: Path, progress, *, interval=5):
    previous = render_fingerprint(directory)
    stopped = threading.Event()
    errors = []

    def watch():
        nonlocal previous
        sequence = 0
        while not stopped.wait(interval):
            current = render_fingerprint(directory)
            changed = [name for name, value in current.items() if previous.get(name) != value]
            previous = current
            if not changed:
                continue
            sequence += 1
            title = ("Encoding animation frames" if "source.mp4" in changed else
                     "Animation code and preview updated" if "render.py" in changed else
                     "Rendered preview frames updated")
            try:
                progress(f"video_render_work_{sequence}", title, "running")
            except Exception as exc:
                errors.append(exc)
                return

    worker = threading.Thread(target=watch, name="video-render-progress", daemon=True)
    worker.start()
    try:
        yield
    finally:
        stopped.set()
        worker.join()
    if errors:
        raise errors[0]
