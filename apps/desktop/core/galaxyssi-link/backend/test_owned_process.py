from __future__ import annotations

import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import owned_process


BASE_PYTHON = getattr(sys, "_base_executable", sys.executable)


class ScopeTests(unittest.TestCase):
    def test_exception_restores_the_normal_execution_scope(self):
        with self.assertRaises(RuntimeError):
            with owned_process.owned_process_scope():
                raise RuntimeError("candidate failed")
        self.assertFalse(owned_process._owned.get())

    def test_normal_chat_process_uses_existing_popen(self):
        with patch.object(subprocess, "Popen") as native:
            self.assertIs(native.return_value, owned_process.popen(["unchanged"]))
        native.assert_called_once_with(["unchanged"])

    def test_scope_is_nested_and_thread_local(self):
        seen = []
        with owned_process.owned_process_scope():
            with owned_process.owned_process_scope():
                self.assertTrue(owned_process._owned.get())
            thread = threading.Thread(target=lambda: seen.append(owned_process._owned.get()))
            thread.start()
            thread.join(5)
            self.assertTrue(owned_process._owned.get())
        self.assertEqual([False], seen)
        self.assertFalse(owned_process._owned.get())


@unittest.skipUnless(os.name == "nt", "Windows Job Object acceptance")
class WindowsOwnedProcessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.kernel.OpenProcess.restype = wintypes.HANDLE
        self.kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        self.kernel.WaitForSingleObject.restype = wintypes.DWORD
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]

    def handle(self, pid):
        handle = self.kernel.OpenProcess(0x100000, False, pid)
        self.assertTrue(handle, f"Cannot open test process {pid}")
        self.addCleanup(self.kernel.CloseHandle, handle)
        return handle

    def await_file(self, path, process):
        deadline = time.monotonic() + 20
        while not path.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(path.exists(), "Test process did not reach its checkpoint")

    def test_binary_stdin_stdout_stderr_and_exit_code_are_preserved(self):
        data = ("Unicode input: \u4f60\u597d\n".encode("utf-8") + b"\x00\xff") * 5000
        code = "import sys; d=sys.stdin.buffer.read(); sys.stdout.buffer.write(d); sys.stderr.write('diagnostic'); sys.exit(7)"
        with owned_process.owned_process_scope():
            process = owned_process.popen([BASE_PYTHON, "-c", code], stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, stderr = process.communicate(data, timeout=20)
            self.assertEqual(data, stdout)
            self.assertEqual(b"diagnostic", stderr)
            self.assertEqual(7, process.returncode)
        finally:
            process.close()

    def test_text_command_runner_preserves_its_contract(self):
        with owned_process.owned_process_scope():
            result = owned_process.run([BASE_PYTHON, "-c", "print('ready')"], stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, encoding="utf-8", timeout=20)
        self.assertEqual(0, result.returncode)
        self.assertEqual("ready", result.stdout.strip())

    def test_guardian_eof_before_assignment_never_starts_command(self):
        marker = self.root / "must-not-run"
        code = "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('ran')"
        guardian = str(Path(owned_process.__file__).with_name("owned_process_guardian.py"))
        result = subprocess.run([BASE_PYTHON, "-I", "-S", guardian, "null", BASE_PYTHON, "-c", code, str(marker)],
                                input=b"", capture_output=True, timeout=20)
        self.assertEqual(125, result.returncode)
        self.assertFalse(marker.exists())

    def test_failed_assignment_cannot_run_the_command(self):
        marker = self.root / "must-not-run"
        code = "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('ran')"
        with patch("windows_process_job.WindowsProcessJob.assign", side_effect=OSError("assignment denied")), \
                owned_process.owned_process_scope():
            with self.assertRaises(OSError):
                owned_process.popen([BASE_PYTHON, "-c", code, str(marker)], stdout=subprocess.PIPE)
        self.assertFalse(marker.exists())

    def test_explicit_kill_stops_the_owned_process(self):
        with owned_process.owned_process_scope():
            process = owned_process.popen([BASE_PYTHON, "-c", "import time; time.sleep(120)"], stdout=subprocess.PIPE)
        handle = self.handle(process.pid)
        try:
            process.kill()
            process.communicate(timeout=20)
            self.assertEqual(0, self.kernel.WaitForSingleObject(handle, 10000))
        finally:
            process.close()

    def test_parent_crash_stops_guardian_child_and_grandchild(self):
        checkpoint = self.root / "processes.json"
        child_code = """
import json, os, subprocess, sys, time
from pathlib import Path
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'])
Path(sys.argv[1]).write_text(json.dumps([os.getpid(), child.pid]), encoding='ascii')
time.sleep(120)
"""
        host_code = """
import os, sys
from pathlib import Path
from owned_process import owned_process_scope, popen
with owned_process_scope():
    p = popen([sys.executable, '-c', sys.argv[1], sys.argv[2]])
Path(sys.argv[3]).write_text(str(p.pid), encoding='ascii')
sys.stdin.buffer.read(1)
os._exit(23)
"""
        guardian_file = self.root / "guardian.pid"
        host = subprocess.Popen([BASE_PYTHON, "-c", host_code, child_code, str(checkpoint), str(guardian_file)],
                                cwd=Path(__file__).resolve().parent, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.await_file(checkpoint, host)
            self.await_file(guardian_file, host)
            pids = [int(guardian_file.read_text()), *json.loads(checkpoint.read_text())]
            handles = [self.handle(pid) for pid in pids]
            self.assertTrue(all(self.kernel.WaitForSingleObject(handle, 0) == 258 for handle in handles))
            _, stderr = host.communicate(input=b"x", timeout=20)
            self.assertEqual(23, host.returncode, stderr.decode(errors="replace"))
            for handle in handles:
                self.assertEqual(0, self.kernel.WaitForSingleObject(handle, 10000))
        finally:
            if host.poll() is None:
                host.communicate(input=b"x", timeout=20)

    def test_exited_command_does_not_leave_descendant_stdout_open(self):
        code = "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)']); print('done')"
        with owned_process.owned_process_scope():
            process = owned_process.popen([BASE_PYTHON, "-c", code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, _ = process.communicate(timeout=20)
            self.assertEqual(b"done", stdout.strip())
            self.assertEqual(0, process.returncode)
        finally:
            process.close()


if __name__ == "__main__":
    unittest.main()
