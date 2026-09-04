import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from proactive_dispatcher import DesktopProactiveDispatcher
from proactive_tasks import (
    ProactiveAction,
    ProactivePolicy,
    ProactiveRun,
    ProactiveTask,
    ProactiveTaskError,
    ProactiveTrigger,
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
    (root / "tests").mkdir()
    (root / "src" / "app.py").write_text("value = 1\n", encoding="utf-8")
    (root / ".gitignore").write_text("*.cache\n", encoding="utf-8")
    (root / "tests" / "check_value.py").write_text(
        (
            "from pathlib import Path\n"
            "assert Path('src/app.py').read_text().strip() == 'value = 2'\n"
        ),
        encoding="utf-8",
    )
    git(root, "add", "--all")
    git(root, "commit", "-m", "Initial test repository")
    return root.resolve()


def task_for(action: ProactiveAction) -> ProactiveTask:
    return ProactiveTask(
        task_id="headless-task",
        name="Headless test",
        trigger=ProactiveTrigger(kind="manual"),
        action=action,
        policy=ProactivePolicy(),
        enabled=True,
        next_run_at_millis=0,
        created_at_millis=1,
        updated_at_millis=1,
    )


def run_for(run_id: str = "headless-run") -> ProactiveRun:
    return ProactiveRun(
        run_id=run_id,
        task_id="headless-task",
        scheduled_for_millis=1,
        status="running",
        attempt=1,
        cause={"type": "manual"},
    )


class HeadlessSwarmDispatcherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = repository(self.root / "repo")
        self.progress = []
        self.dispatcher = DesktopProactiveDispatcher(
            progress_sink=lambda run_id, kind, detail, metadata: (
                self.progress.append((run_id, kind, detail, metadata)) or True
            )
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_test_repair_runs_specialists_and_returns_local_candidate(self):
        action = ProactiveAction.parse(
            {
                "kind": "headless_swarm",
                "target_id": "test_repair",
                "prompt": "Set the value to two and verify it",
                "arguments": {
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
                "team": [
                    {"agent_id": "codex", "role": "coordinator"},
                    {"agent_id": "hermes", "role": "specialist"},
                    {"agent_id": "claude", "role": "verifier"},
                ],
            }
        )

        def run_agent(agent_id, prompt, _task, _run, **kwargs):
            if "sole writer" in prompt:
                Path(kwargs["working_directory"], "src", "app.py").write_text(
                    "value = 2\n",
                    encoding="utf-8",
                )
                return {"reply": "Implemented the repair."}
            if "Return one concise final status" in prompt:
                return {"reply": "Candidate is ready and host checks passed."}
            if "Independently verify" in prompt:
                return {"reply": "No concrete defect found."}
            if "Collect concrete repository evidence" in prompt:
                return {"reply": f"{agent_id} found the failing value."}
            return {"reply": "Update src/app.py and run the configured check."}

        with (
            patch.object(
                self.dispatcher,
                "_team_collaboration_channel",
                return_value=None,
            ),
            patch.object(
                self.dispatcher,
                "_run_agent",
                side_effect=run_agent,
            ),
            patch("pairing_state.DATA_DIR", str(self.root / "state")),
        ):
            output = self.dispatcher(task_for(action), run_for())

        self.assertEqual("galaxyssi.headless-swarm.v1", output["protocol"])
        self.assertEqual("test_repair", output["workflow"])
        self.assertEqual("candidate_only", output["publish_state"])
        self.assertEqual(["src/app.py"], output["changed_files"])
        self.assertEqual(2, len(output["checks"]))
        self.assertEqual("value = 1\n", (self.repository / "src" / "app.py").read_text())
        self.assertEqual(
            "value = 2",
            git(
                self.repository,
                "show",
                f"{output['candidate_branch']}:src/app.py",
            ).strip(),
        )
        progress_kinds = [item[1] for item in self.progress]
        self.assertIn("headless_workspace", progress_kinds)
        self.assertIn("headless_candidate", progress_kinds)

    def test_review_fails_closed_when_final_reviewer_writes(self):
        (self.repository / "src" / "app.py").write_text(
            "value = 2\n",
            encoding="utf-8",
        )
        git(self.repository, "add", "--all")
        git(self.repository, "commit", "-m", "Candidate")
        action = ProactiveAction.parse(
            {
                "kind": "headless_swarm",
                "target_id": "pr_review",
                "prompt": "Review the candidate",
                "arguments": {
                    "repository_root": str(self.repository),
                    "base_ref": "HEAD~1",
                    "review_ref": "HEAD",
                },
                "team": [
                    {"agent_id": "codex", "role": "coordinator"},
                    {"agent_id": "hermes", "role": "specialist"},
                ],
            }
        )

        def run_agent(_agent_id, prompt, _task, _run, **kwargs):
            if "only final reviewer" in prompt:
                Path(kwargs["working_directory"], "forbidden.cache").write_text(
                    "mutation",
                    encoding="utf-8",
                )
                return {"reply": "No findings."}
            return {"reply": "Review the changed value."}

        with (
            patch.object(
                self.dispatcher,
                "_team_collaboration_channel",
                return_value=None,
            ),
            patch.object(
                self.dispatcher,
                "_run_agent",
                side_effect=run_agent,
            ),
            patch("pairing_state.DATA_DIR", str(self.root / "state")),
        ):
            with self.assertRaises(ProactiveTaskError) as raised:
                self.dispatcher(task_for(action), run_for("review-run"))

        self.assertEqual("headless_read_only_violation", raised.exception.code)
        self.assertFalse((self.repository / "forbidden.cache").exists())


if __name__ == "__main__":
    unittest.main()
