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
