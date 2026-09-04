import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from headless_swarm import (
    HeadlessSwarmError,
    HeadlessSwarmSpec,
    HeadlessSwarmWorkspace,
)


def git(root: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=str(root),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stdout)
    return completed.stdout.strip()


def repository(root: Path) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    git(root, "init")
    git(root, "config", "user.name", "GalaxySSI Test")
    git(root, "config", "user.email", "galaxyssi@hotmail.com")
    (root / "src").mkdir()
    (root / "docs").mkdir()
    (root / "tests").mkdir()
    (root / "src" / "app.py").write_text("value = 1\n", encoding="utf-8")
    (root / "docs" / "guide.md").write_text("# Guide\n", encoding="utf-8")
    (root / ".gitignore").write_text("*.cache\n", encoding="utf-8")
    (root / "tests" / "check_value.py").write_text(
        (
            "from pathlib import Path\n"
            "assert Path('src/app.py').read_text().strip() == 'value = 2'\n"
        ),
        encoding="utf-8",
    )
    (root / "tests" / "fail.py").write_text(
        "raise SystemExit(7)\n",
        encoding="utf-8",
    )
    git(root, "add", "--all")
    git(root, "commit", "-m", "Initial test repository")
    return root.resolve()


class HeadlessSwarmSpecTests(unittest.TestCase):
    def test_test_repair_requires_scope_and_host_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = repository(Path(temporary) / "repo")
            with self.assertRaisesRegex(HeadlessSwarmError, "explicit repository scope"):
                HeadlessSwarmSpec.parse(
                    "test_repair",
                    "Repair the failing test",
                    {"repository_root": str(root)},
                )
            with self.assertRaisesRegex(HeadlessSwarmError, "validation check"):
                HeadlessSwarmSpec.parse(
                    "test_repair",
                    "Repair the failing test",
                    {"repository_root": str(root), "scope": ["src"]},
                )

    def test_check_rejects_shell_and_protected_scope(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = repository(Path(temporary) / "repo")
            with self.assertRaisesRegex(HeadlessSwarmError, "not allowed"):
                HeadlessSwarmSpec.parse(
                    "test_repair",
                    "Repair the failing test",
                    {
                        "repository_root": str(root),
                        "scope": ["src"],
                        "checks": [["powershell", "-Command", "exit 0"]],
                    },
                )
            with self.assertRaisesRegex(HeadlessSwarmError, "Inline code"):
                HeadlessSwarmSpec.parse(
                    "test_repair",
                    "Repair the failing test",
                    {
                        "repository_root": str(root),
                        "scope": ["src"],
                        "checks": [["python", "-c", "print('unsafe')"]],
                    },
                )
            with self.assertRaisesRegex(HeadlessSwarmError, "protected"):
                HeadlessSwarmSpec.parse(
                    "documentation_update",
                    "Update release documentation",
                    {
                        "repository_root": str(root),
                        "scope": [".github/workflows"],
                    },
                )


class HeadlessSwarmWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = repository(self.root / "repo")
        self.state = self.root / "state"

    def tearDown(self):
        self.temporary.cleanup()

    def test_pull_request_review_is_read_only_and_reports_diff(self):
        (self.repository / "src" / "app.py").write_text(
            "value = 2\n",
            encoding="utf-8",
        )
        git(self.repository, "add", "--all")
        git(self.repository, "commit", "-m", "Candidate change")
        spec = HeadlessSwarmSpec.parse(
            "pr_review",
            "Review the candidate",
            {
                "repository_root": str(self.repository),
                "base_ref": "HEAD~1",
                "review_ref": "HEAD",
            },
        )

        with HeadlessSwarmWorkspace(spec, "review-run", self.state) as workspace:
            context = workspace.review_context()
            self.assertEqual(["src/app.py"], context["changed_files"])
            self.assertIn("value = 2", context["diff"])
            (workspace.worktree / "review-note.cache").write_text(
                "not allowed",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                HeadlessSwarmError,
                "attempted to modify",
            ):
                workspace.assert_read_only()

        self.assertFalse((self.repository / "review-note.cache").exists())

    def test_test_repair_creates_checked_candidate_without_touching_source(self):
        spec = HeadlessSwarmSpec.parse(
            "test_repair",
            "Set the value to two",
            {
                "repository_root": str(self.repository),
                "scope": ["src"],
                "checks": [
                    {
                        "argv": [
                            sys.executable,
                            "tests/check_value.py",
                        ]
                    }
                ],
            },
        )

        with HeadlessSwarmWorkspace(spec, "repair-run", self.state) as workspace:
            (workspace.worktree / "src" / "app.py").write_text(
                "value = 2\n",
                encoding="utf-8",
            )
            changed, checks = workspace.validate_candidate()
            candidate = workspace.commit_candidate(changed)
            branch = workspace.branch
            self.assertEqual(["src/app.py"], changed)
            self.assertTrue(all(item["exit_code"] == 0 for item in checks))
            self.assertEqual(40, len(candidate))

        self.assertEqual(
            "value = 1",
            (self.repository / "src" / "app.py").read_text(encoding="utf-8").strip(),
        )
        self.assertEqual(
            "value = 2",
            git(self.repository, "show", f"{branch}:src/app.py").strip(),
        )

    def test_documentation_update_rejects_non_documentation_file(self):
        spec = HeadlessSwarmSpec.parse(
            "documentation_update",
            "Update documentation only",
            {
                "repository_root": str(self.repository),
                "scope": ["docs", "src"],
            },
        )

        with self.assertRaisesRegex(HeadlessSwarmError, "non-documentation"):
            with HeadlessSwarmWorkspace(
                spec,
                "docs-run",
                self.state,
            ) as workspace:
                (workspace.worktree / "src" / "app.py").write_text(
                    "value = 3\n",
                    encoding="utf-8",
                )
                workspace.validate_candidate()

    def test_failed_host_check_does_not_retain_candidate_branch(self):
        spec = HeadlessSwarmSpec.parse(
            "test_repair",
            "Produce a candidate that fails validation",
            {
                "repository_root": str(self.repository),
                "scope": ["src"],
                "checks": [
                    {
                        "argv": [sys.executable, "tests/fail.py"],
                    }
                ],
            },
        )
        branch = ""

        with self.assertRaisesRegex(HeadlessSwarmError, "Validation failed"):
            with HeadlessSwarmWorkspace(
                spec,
                "failed-run",
                self.state,
            ) as workspace:
                branch = workspace.branch
                (workspace.worktree / "src" / "app.py").write_text(
                    "value = 9\n",
                    encoding="utf-8",
                )
                workspace.validate_candidate()

        self.assertNotIn(branch, git(self.repository, "branch", "--list"))


if __name__ == "__main__":
    unittest.main()
