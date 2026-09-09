"""Keep Android-compiling CI gates on the same explicit Gradle memory profile."""

import pathlib
import shlex
import unittest

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]


class AndroidCiMemoryTests(unittest.TestCase):
    def test_repo_gates_share_the_verified_memory_and_worker_profile(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/repo-guard.yml").read_text(encoding="utf-8"))
        jobs = workflow["jobs"]
        for name in ("android-build", "core-regressions"):
            with self.subTest(job=name):
                options = shlex.split(jobs[name]["env"]["GRADLE_OPTS"])
                self.assertIn("-Dorg.gradle.jvmargs=-Xmx6144m", options)
                self.assertIn("-Dorg.gradle.workers.max=2", options)
                self.assertFalse(jobs[name].get("continue-on-error", False))
        self.assertTrue(any(step.get("run") == "npm run test:core-regressions"
                            for step in jobs["core-regressions"]["steps"]))


if __name__ == "__main__":
    unittest.main()
