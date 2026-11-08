import os
import unittest
from unittest.mock import patch

from command_lookup import command_lookup_scope, which


class CommandLookupTest(unittest.TestCase):
    def test_reuses_missing_and_present_results_only_within_request(self):
        with patch("command_lookup.shutil.which", side_effect=[None, "installed"]) as lookup:
            with command_lookup_scope():
                self.assertIsNone(which("tool"))
                self.assertIsNone(which("tool"))
            with command_lookup_scope():
                self.assertEqual("installed", which("tool"))
            self.assertEqual(2, lookup.call_count)

    def test_environment_change_invalidates_lookup(self):
        with patch("command_lookup.shutil.which", side_effect=[None, "installed"]), command_lookup_scope():
            self.assertIsNone(which("tool"))
            with patch.dict(os.environ, {"PATH": "new-path"}):
                self.assertEqual("installed", which("tool"))

    def test_failure_does_not_leak_request_cache(self):
        with patch("command_lookup.shutil.which", return_value=None) as lookup:
            with self.assertRaises(ValueError), command_lookup_scope():
                which("tool")
                raise ValueError("request failed")
            which("tool")
            which("tool")
            self.assertEqual(3, lookup.call_count)

    def test_nested_adapter_reuses_coordinator_lookup(self):
        @command_lookup_scope()
        def adapter():
            return which("codex")
        with patch("command_lookup.shutil.which", return_value="codex.exe") as lookup:
            with command_lookup_scope():
                self.assertEqual("codex.exe", which("codex"))
                self.assertEqual("codex.exe", adapter())
                self.assertEqual("codex.exe", which("codex"))
            self.assertEqual(1, lookup.call_count)
            adapter()
            self.assertEqual(2, lookup.call_count)

    def test_concurrent_requests_do_not_share_lookup_cache(self):
        from concurrent.futures import ThreadPoolExecutor
        import threading
        barrier = threading.Barrier(2)
        def request():
            with command_lookup_scope():
                which("codex")
                barrier.wait(timeout=2)
                which("codex")
        with patch("command_lookup.shutil.which", return_value="codex.exe") as lookup:
            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(lambda _: request(), range(2)))
            self.assertEqual(2, lookup.call_count)
