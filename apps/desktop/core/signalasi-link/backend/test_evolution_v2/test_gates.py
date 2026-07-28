from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from evolution_v2.gates import StaticEvolutionGuard
from evolution_v2.policy import EvolutionPolicy


@unittest.skipUnless(shutil.which("git"), "git is required")
class GateTests(unittest.TestCase):
    def repo(self, root: str) -> Path:
        path = Path(root)
        subprocess.run(["git", "init", "-q"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=path, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=path, check=True)
        (path / "apps/desktop/core").mkdir(parents=True)
        (path / "apps/desktop/core/value.py").write_text("VALUE = 1\n", encoding="utf-8")
        (path / "apps/desktop/core/test_value.py").write_text("def test_value():\n    assert True\n", encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=path, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=path, check=True)
        return path

    def test_code_plus_test_passes(self):
        with tempfile.TemporaryDirectory() as root:
            repo = self.repo(root)
            (repo / "apps/desktop/core/value.py").write_text("VALUE = 2\n", encoding="utf-8")
            (repo / "apps/desktop/core/test_value.py").write_text("def test_value():\n    assert 2 == 2\n", encoding="utf-8")
            policy = EvolutionPolicy(repo, repo / "missing.json")
            result = StaticEvolutionGuard(repo, policy).inspect()
            self.assertTrue(result.passed, result.findings)

    def test_secret_marker_fails(self):
        with tempfile.TemporaryDirectory() as root:
            repo = self.repo(root)
            (repo / "apps/desktop/core/value.py").write_text('TOKEN = "ghp_abcdefghijklmnopqrstuvwxyz"\n', encoding="utf-8")
            (repo / "apps/desktop/core/test_value.py").write_text("def test_value():\n    assert True\n", encoding="utf-8")
            policy = EvolutionPolicy(repo, repo / "missing.json")
            result = StaticEvolutionGuard(repo, policy).inspect()
            self.assertFalse(result.passed)
            self.assertTrue(any("secret" in finding.casefold() or "credential" in finding.casefold() for finding in result.findings))


if __name__ == "__main__":
    unittest.main()
