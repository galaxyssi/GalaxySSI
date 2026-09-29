import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import office_preview_worker as worker


class OfficePreviewWorkerTests(unittest.TestCase):
    def test_timeout_cleans_only_recorded_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def run(args, **kwargs):
                if "-InputPath" in args:
                    owner = Path(args[args.index("-OwnerPath") + 1])
                    owner.write_text(json.dumps({"id": 12345, "name": "WINWORD", "ticks": 42}))
                    raise subprocess.TimeoutExpired(args, 1)
                return SimpleNamespace(returncode=0)

            with patch.object(worker.subprocess, "run", side_effect=run) as execute, \
                 self.assertRaises(subprocess.TimeoutExpired):
                worker.convert(root / "a.docx", root / "a.pdf", root, "powershell", timeout=1)
            self.assertEqual(2, execute.call_count)
            cleanup_args = execute.call_args.args[0]
            self.assertIn(str(root / "office-cleanup.ps1"), cleanup_args)
            self.assertIn("StartTime.ToUniversalTime().Ticks", worker._CLEANUP)
            self.assertNotIn("Stop-Process -Name", worker._CLEANUP)

    def test_failure_without_owner_does_not_kill_any_process(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(worker.subprocess, "run", return_value=SimpleNamespace(
                returncode=1, stdout="", stderr="office_busy"
            )) as execute, self.assertRaisesRegex(RuntimeError, "office_busy"):
                worker.convert(root / "a.xlsx", root / "a.pdf", root, "powershell")
            self.assertEqual(1, execute.call_count)
            self.assertEqual("replace", execute.call_args.kwargs["errors"])

    def test_success_without_owner_does_not_run_global_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(worker.subprocess, "run", return_value=SimpleNamespace(
                returncode=0, stdout="", stderr=""
            )) as execute:
                worker.convert(root / "a.pptx", root / "a.pdf", root, "powershell")
            self.assertEqual(1, execute.call_count)


if __name__ == "__main__":
    unittest.main()
