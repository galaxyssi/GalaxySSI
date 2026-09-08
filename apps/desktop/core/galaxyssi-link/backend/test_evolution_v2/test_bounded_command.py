import sys
import tempfile
import unittest
from pathlib import Path

from evolution_v2.runner import SafeRunner


class BoundedCommandTests(unittest.TestCase):
    def run_code(self, code, limit=100, timeout=20):
        with tempfile.TemporaryDirectory() as root:
            return SafeRunner().run_bounded([sys.executable, "-c", code], Path(root),
                                            maximum_bytes=limit, timeout_seconds=timeout)

    def test_completed_output_and_nonzero_status_preserved(self):
        result, clipped = self.run_code("print('diagnostic'); raise SystemExit(3)")
        self.assertEqual(3, result.returncode)
        self.assertIn("diagnostic", result.stdout)
        self.assertFalse(clipped)

    def test_exact_limit_is_not_truncation(self):
        result, clipped = self.run_code("import sys; sys.stdout.write('x' * 100)")
        self.assertTrue(result.ok)
        self.assertEqual(100, len(result.stdout))
        self.assertFalse(clipped)

    def test_large_output_is_bounded_before_capture(self):
        result, clipped = self.run_code("import sys; sys.stdout.write('x' * 10000000)")
        self.assertEqual("x" * 100, result.stdout)
        self.assertTrue(clipped)

    def test_stalled_child_is_terminated(self):
        with self.assertRaises(TimeoutError):
            self.run_code("import time; time.sleep(60)", timeout=1)

    def test_tokens_are_redacted(self):
        result, _ = self.run_code("print('Authorization: Bearer example-secret')")
        self.assertNotIn("example-secret", result.stdout)
        self.assertIn("REDACTED", result.stdout)

    def test_invalid_input_does_not_launch(self):
        with self.assertRaises(ValueError):
            self.run_code("raise RuntimeError('must not run')", limit=0)


if __name__ == "__main__":
    unittest.main()
