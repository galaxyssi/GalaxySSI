from __future__ import annotations

import inspect
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import agent_gateway
from evolution_v2 import legacy
from evolution_v2.agent_adapters import default_evolution_patch_agent
from evolution_v2.manager import EvolutionManager
from evolution_v2.models import TaskMetadata


class MemoryStore:
    def __init__(self) -> None:
        self.saved = []

    def save(self, task) -> None:
        self.saved.append(task.base_commit)


class MetadataStore:
    def __init__(self, metadata: TaskMetadata) -> None:
        self.metadata = metadata
        self.saved = []

    def get_task_metadata(self, _task_id):
        return self.metadata

    def save_task_metadata(self, metadata):
        self.saved.append(metadata.source_commit)


class FakeGitRunner:
    def __init__(self, commit: str) -> None:
        self.commit = commit
        self.calls = []

    def run(self, argv, _cwd, **_kwargs):
        self.calls.append(tuple(argv))
        output = self.commit + "\n" if argv[:2] == ("git", "rev-parse") else ""
        return type("Result", (), {"returncode": 0, "stdout": output})()


class FailedFetchRunner:
    def __init__(self) -> None:
        self.calls = []

    def run(self, argv, _cwd, **_kwargs):
        self.calls.append(tuple(argv))
        return type("Result", (), {"returncode": 1, "stdout": "offline"})()


def spec(agent_id: str, kind: str, capabilities: tuple[str, ...]):
    return agent_gateway.AgentSpec(
        id=agent_id,
        name=agent_id.title(),
        kind=kind,
        command=[agent_id],
        timeout=30,
        capabilities=capabilities,
    )


class ReliableAgentSelectionTests(unittest.TestCase):
    def test_selection_prefers_explicit_healthy_agent_and_excludes_chat_models(self):
        specs = {
            "codex": spec("codex", "local-cli", ("code", "terminal", "files")),
            "claude": spec("claude", "local-cli", ("code", "terminal", "files")),
            "chat": spec("chat", "cloud-model", ("code", "terminal", "files")),
            "weak": spec("weak", "custom-cli", ("files",)),
        }

        def status(value, quick=False):
            return {"name": value.name, "status": "ready", "capabilities": list(value.capabilities)}

        with patch.object(agent_gateway, "all_agent_specs", return_value=specs), patch.object(
            agent_gateway, "agent_status", side_effect=status
        ):
            snapshot = agent_gateway.evolution_agent_candidates("claude")

        self.assertEqual("claude", snapshot["selected_agent_id"])
        self.assertEqual(["claude", "codex"], [row["id"] for row in snapshot["agents"]])
        self.assertNotIn("command", str(snapshot))

    def test_failed_channel_is_quarantined_but_sole_agent_can_retry(self):
        specs = {
            "codex": spec("codex", "local-cli", ("code", "terminal", "files")),
            "claude": spec("claude", "local-cli", ("code", "terminal", "files")),
        }
        status = lambda value, quick=False: {"name": value.name, "status": "ready"}
        with patch.object(agent_gateway, "all_agent_specs", return_value=specs), patch.object(
            agent_gateway, "agent_status", side_effect=status
        ):
            self.assertEqual(
                "claude",
                agent_gateway.select_evolution_agent("codex", excluded_agent_ids={"codex"}),
            )
            specs.pop("claude")
            self.assertEqual(
                "codex",
                agent_gateway.select_evolution_agent("codex", excluded_agent_ids={"codex"}),
            )

    def test_unhealthy_explicit_preference_fails_over(self):
        specs = {
            "codex": spec("codex", "local-cli", ("code", "terminal", "files")),
            "claude": spec("claude", "local-cli", ("code", "terminal", "files")),
        }

        def status(value, quick=False):
            return {"name": value.name, "status": "unavailable" if value.id == "claude" else "ready"}

        with patch.object(agent_gateway, "all_agent_specs", return_value=specs), patch.object(
            agent_gateway, "agent_status", side_effect=status
        ):
            self.assertEqual("codex", agent_gateway.select_evolution_agent("claude"))

    def test_gateway_accepts_local_cli_and_validates_worktree(self):
        local = spec("codex", "local-cli", ("code", "terminal", "files"))
        with tempfile.TemporaryDirectory() as root:
            worktree = Path(root)
            (worktree / ".git").write_text("gitdir: elsewhere", encoding="utf-8")
            with patch.object(agent_gateway, "all_agent_specs", return_value={"codex": local}), patch.object(
                agent_gateway, "ask_cli_agent", return_value="done"
            ) as invoked:
                self.assertEqual(
                    "done",
                    agent_gateway.ask_evolution_agent(
                        "codex", "repair", task_id="task", working_directory=worktree
                    ),
                )
                self.assertEqual(worktree.resolve(), invoked.call_args.kwargs["working_directory"])
        with tempfile.TemporaryDirectory() as root, patch.object(
            agent_gateway, "all_agent_specs", return_value={"codex": local}
        ):
            with self.assertRaisesRegex(RuntimeError, "Git worktree"):
                agent_gateway.ask_evolution_agent(
                    "codex", "repair", task_id="task", working_directory=Path(root)
                )


class ReliableManagerTests(unittest.TestCase):
    def manager(self, root: Path, commit: str):
        manager = object.__new__(EvolutionManager)
        manager.source_root = root
        manager.store = MemoryStore()
        manager.runner = FakeGitRunner(commit)
        metadata = TaskMetadata(task_id="task")
        manager.v2_store = MetadataStore(metadata)
        return manager, metadata

    def test_source_commit_is_fetched_once_and_reused_for_retry(self):
        commit = "a" * 40
        with tempfile.TemporaryDirectory() as root:
            manager, metadata = self.manager(Path(root), commit)
            task = legacy.EvolutionTask(
                task_id="task",
                problem="repair",
                reproduction_steps=[],
                scope=["src"],
                acceptance=["passes"],
                risk_level="low",
                max_attempts=2,
            )
            self.assertEqual(commit, manager._pin_source_commit(task))
            self.assertEqual(commit, metadata.source_commit)
            self.assertEqual(commit, manager._pin_source_commit(task))

        self.assertEqual(
            [("git", "fetch", "--no-tags", "origin", "main")],
            [call for call in manager.runner.calls if call[:2] == ("git", "fetch")],
        )
        self.assertEqual(commit, task.base_commit)

    def test_fetch_failure_blocks_before_any_worktree_command(self):
        with tempfile.TemporaryDirectory() as root:
            manager, _metadata = self.manager(Path(root), "a" * 40)
            manager.runner = FailedFetchRunner()
            task = legacy.EvolutionTask(
                task_id="task",
                problem="repair",
                reproduction_steps=[],
                scope=["src"],
                acceptance=["passes"],
                risk_level="low",
                max_attempts=2,
            )
            with self.assertRaises(legacy.EvolutionError) as raised:
                manager._pin_source_commit(task)
        self.assertEqual("source_fetch_failed", raised.exception.code)
        self.assertFalse(any(call[:3] == ("git", "worktree", "add") for call in manager.runner.calls))

    def test_retry_selection_only_quarantines_implementation_channel_failures(self):
        manager = object.__new__(EvolutionManager)
        manager.patch_agent = default_evolution_patch_agent
        task = legacy.EvolutionTask(
            task_id="task",
            problem="repair",
            reproduction_steps=[],
            scope=["src"],
            acceptance=["passes"],
            risk_level="low",
            max_attempts=3,
            agent_id="codex",
            attempts=[
                legacy.EvolutionAttempt(1, "failed", "one", "", agent_id="codex", failure_code="implementation_channel_failed"),
                legacy.EvolutionAttempt(2, "failed", "two", "", agent_id="claude", failure_code="quality_gate_failed"),
            ],
        )
        with patch("agent_gateway.select_evolution_agent", return_value="claude") as selected:
            self.assertEqual("claude", manager._select_implementation_agent(task))
        self.assertEqual({"codex"}, selected.call_args.kwargs["excluded_agent_ids"])

    def test_trusted_dependency_root_discovers_all_ignored_gate_runtimes(self):
        with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as dependencies:
            manager = object.__new__(EvolutionManager)
            manager.source_root = Path(source)
            root = Path(dependencies)
            for relative in (
                "apps/desktop/.electron-runtime",
                "apps/desktop/.runtime-python",
                "build/runtime/android-jni-libs",
                "build/runtime/android-assets/runtime/qemu",
            ):
                (root / relative).mkdir(parents=True)
            (root / "build/runtime/android-jni-libs/signalasi-qemu-bundle.json").write_text("{}", encoding="utf-8")
            (root / "build/runtime/android-assets/runtime/qemu/bundle.json").write_text("{}", encoding="utf-8")
            manager.dependency_root = root
            self.assertEqual(
                root / "apps/desktop/.electron-runtime",
                manager._gate_dependency_source("apps/desktop/.electron-runtime"),
            )
            self.assertTrue(manager._embedded_android_runtime_available())

    def test_prepare_attempt_override_contract_remains_backward_compatible(self):
        self.assertEqual(
            ["self", "task", "number"],
            list(inspect.signature(legacy.EvolutionManager._prepare_attempt).parameters),
        )

    def test_gate_dependencies_are_detached_before_candidate_staging(self):
        manager = object.__new__(EvolutionManager)
        removed = []
        manager._gate_dependency_source = lambda _relative: Path(__file__).parent
        manager._embedded_android_runtime_available = lambda: True
        manager._remove_gate_dependency_target = removed.append
        worktree = Path("candidate")

        manager._detach_gate_dependencies(worktree)

        self.assertEqual(
            {
                worktree / "apps/desktop/.electron-runtime",
                worktree / "apps/desktop/.runtime-python",
                worktree / "build/runtime",
            },
            set(removed),
        )


if __name__ == "__main__":
    unittest.main()
