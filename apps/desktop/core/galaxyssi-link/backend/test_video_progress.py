import threading
import time

from video_progress import render_fingerprint, track_render_progress


def test_idle_files_and_metadata_touches_do_not_fake_progress(tmp_path):
    path = tmp_path / "render.py"
    path.write_text("unchanged")
    observed = []
    with track_render_progress(tmp_path, lambda *args: observed.append(args), interval=0.01):
        path.touch()
        time.sleep(0.06)
    assert not observed


def test_new_render_bytes_report_progress_and_stop_cleanly(tmp_path):
    notified = threading.Event()
    observed = []
    def progress(*args):
        observed.append(args)
        notified.set()
    with track_render_progress(tmp_path, progress, interval=0.01):
        (tmp_path / "render.py").write_text("draw a frame")
        assert notified.wait(2)
    (tmp_path / "source.mp4").write_bytes(b"later")
    time.sleep(0.03)
    assert len(observed) == 1
    assert observed[0][0] == "video_render_work_1"


def test_secret_state_and_zero_byte_outputs_are_not_render_progress(tmp_path):
    (tmp_path / "job.json").write_text("sensitive checkpoint")
    (tmp_path / ".galaxyssi-state-key").write_text("secret")
    (tmp_path / "source.mp4").touch()
    assert render_fingerprint(tmp_path) == {}
