from __future__ import annotations

import json
import os
import tempfile
import unittest
from unittest.mock import patch

from desktop_agent_loop import AgentLoopBudget
from desktop_super_agent import DesktopSuperAgent
from task_workspace import task_artifacts, task_workspace


class FakeTaskManager:
    def __init__(self) -> None:
        self.events: list[dict] = []
        self.updates: list[dict] = []

    def add_event(self, task_id, kind, title, **kwargs):
        self.events.append({"task_id": task_id, "kind": kind, "title": title, **kwargs})

    def update(self, task_id, status, **kwargs):
        self.updates.append({"task_id": task_id, "status": status, **kwargs})


class FakeRegistry:
    def __init__(self, results: dict[str, dict]) -> None:
        self.results = results
        self.calls: list[tuple[str, dict, dict]] = []

    def invoke(self, tool_id, arguments, context):
        self.calls.append((tool_id, arguments, context))
        result = self.results[tool_id]
        if isinstance(result, list):
            if not result:
                raise AssertionError(f"No fake result remains for {tool_id}")
            return result.pop(0)
        return result


class FakeMemory:
    def __init__(self, context: str = "") -> None:
        self.context = context
        self.learned: list[tuple[str, str, str, str]] = []

    def compile_context(self, prompt):
        return self.context

    def evolve(self, prompt, reply, *, conversation_id="", task_id=""):
        self.learned.append((prompt, reply, conversation_id, task_id))
        return []


class FakeSkills:
    def compile(self, prompt):
        return "", []


class FakeMcp:
    def match(self, prompt):
        return None


class MatchingMcp:
    class Connection:
        id = "relay"
        name = "Relay MCP"

    def match(self, prompt):
        return self.Connection()

    def explicitly_named(self, connection, prompt):
        return connection.name.casefold() in prompt.casefold()

    def invoke_prompt(self, connection_id, prompt, process_callback=None, **kwargs):
        return {"result": "Relay is on.", "duration_ms": 17}


def succeeded(output: dict, message: str = "ok") -> dict:
    return {
        "status": "succeeded",
        "output": output,
        "message": message,
        "error": None,
        "verification": {"status": "passed"},
        "receipt": {"duration_ms": 2},
    }


def failed(code: str, message: str, *, retryable: bool = False) -> dict:
    return {
        "status": "failed",
        "output": {},
        "message": "",
        "error": {"code": code, "message": message, "retryable": retryable},
        "verification": {},
        "receipt": {"duration_ms": 2},
    }


class DesktopSuperAgentTest(unittest.TestCase):
    def setUp(self):
        self.temporary_workspace = tempfile.TemporaryDirectory()
        self.workspace_environment = patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": self.temporary_workspace.name},
        )
        self.workspace_environment.start()

    def tearDown(self):
        self.workspace_environment.stop()
        self.temporary_workspace.cleanup()

    def test_launches_named_application_as_a_direct_desktop_action(self):
        manager = FakeTaskManager()
        registry = FakeRegistry({
            "signalasi.desktop.windows.app.launch": succeeded({"id": "notepad", "name": "Notepad", "launched": True}),
        })
        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": []},
            deliver=lambda *args, **kwargs: self.fail("Application launch should not call an external Agent"),
            registry=registry,
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-app",
            conversation_id="conversation-app",
            prompt="Open Notepad",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertEqual(outcome.reply, "Launched Notepad.")
        self.assertEqual(registry.calls[0][1], {"name": "Notepad"})

    def test_starting_a_project_is_delegated_instead_of_treated_as_an_app(self):
        manager = FakeTaskManager()
        delivered: list[tuple[str, str]] = []

        def deliver(agent_id, prompt, **_kwargs):
            delivered.append((agent_id, prompt))
            return {"reply": "Project started."}

        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": [{"id": "codex", "status": "ready"}]},
            deliver=deliver,
            registry=FakeRegistry({}),
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-project",
            conversation_id="conversation-project",
            prompt="Start a project for release automation",
            compiled_prompt="compiled project request",
            attachments=[],
        )

        self.assertEqual(outcome.delegate_agent_id, "codex")
        self.assertEqual(delivered[0][0], "codex")

    def test_build_task_uses_medium_policy_checkpoint_and_verified_project_archive(self):
        manager = FakeTaskManager()
        delegated_prompts: list[str] = []

        def deliver(agent_id, delegated_prompt, **kwargs):
            delegated_prompts.append(delegated_prompt)
            root = task_workspace(kwargs["task_id"], agent_id)
            project = root / "demo"
            project.mkdir()
            (project / "main.py").write_text("print('ok')\n", encoding="utf-8")
            (project / "README.md").write_text("# Demo\n", encoding="utf-8")
            return {"reply": "Built and verified the project."}

        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": [{"id": "codex", "status": "ready"}]},
            deliver=deliver,
            registry=FakeRegistry({}),
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-build-policy",
            conversation_id="conversation-build-policy",
            prompt="Build a small program and return the project",
            compiled_prompt="compiled build request",
            attachments=[],
        )

        checkpoint = json.loads(
            (
                task_workspace("task-build-policy", "desktop")
                / ".signalasi"
                / "execution-checkpoint.json"
            ).read_text(encoding="utf-8")
        )
        outputs = task_artifacts("task-build-policy")

        self.assertEqual("codex", outcome.delegate_agent_id)
        self.assertIn("reasoning effort: medium", delegated_prompts[0])
        self.assertEqual("build", checkpoint["policy"]["task_kind"])
        self.assertEqual("medium", checkpoint["policy"]["reasoning_effort"])
        self.assertIsNone(checkpoint["policy"]["absolute_timeout_seconds"])
        self.assertEqual("finalize", checkpoint["phase"])
        self.assertEqual(1, len(outputs))
        self.assertTrue(outputs[0]["name"].endswith(".zip"))

    def test_explicit_mcp_capability_executes_without_external_agent(self):
        manager = FakeTaskManager()
        deliveries = []
        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": []},
            deliver=lambda *args, **kwargs: deliveries.append((args, kwargs)),
            registry=FakeRegistry({}),
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=MatchingMcp(),
        )

        outcome = coordinator.run(
            task_id="task-mcp",
            conversation_id="conversation-mcp",
            prompt="Use Relay MCP to turn it on",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertEqual(outcome.reply, "Relay is on.")
        self.assertEqual(outcome.delegate_agent_id, "mcp:relay")
        self.assertEqual(deliveries, [])
        self.assertTrue(any(
            event["kind"] == "agent_loop" and (event.get("metadata") or {}).get("phase") == "verify"
            for event in manager.events
        ))

    def test_reads_system_status_without_external_agent(self):
        manager = FakeTaskManager()
        registry = FakeRegistry({
            "signalasi.desktop.windows.system.status": succeeded({
                "platform": "Windows",
                "release": "11",
                "architecture": "AMD64",
                "logical_cpu_count": 16,
                "memory_total_bytes": 32 * 1024 ** 3,
                "memory_available_bytes": 20 * 1024 ** 3,
            }),
        })
        deliveries: list[dict] = []
        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": []},
            deliver=lambda *args, **kwargs: deliveries.append(kwargs),
            registry=registry,
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-1",
            conversation_id="conversation-1",
            prompt="Show computer system status and memory usage",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertIn("20.0 GB available", outcome.reply)
        self.assertEqual(deliveries, [])
        self.assertEqual(registry.calls[0][0], "signalasi.desktop.windows.system.status")
        self.assertTrue(any(
            event["kind"] == "agent_loop"
            and (event.get("metadata") or {}).get("phase") == "verify"
            and (event.get("metadata") or {}).get("verified") is True
            for event in manager.events
        ))

    def test_reads_runtime_inventory_without_external_agent(self):
        registry = FakeRegistry({
            "signalasi.desktop.runtime.status": succeeded({
                "summary": {"ready": 2, "partial": 0, "missing": 1, "total": 3},
                "runtimes": [
                    {"id": "python", "title": "Python", "status": "ready", "version": "Python 3.12"},
                    {"id": "ffmpeg", "title": "FFmpeg", "status": "ready", "version": "FFmpeg 7"},
                    {"id": "rust", "title": "Rust", "status": "missing", "version": ""},
                ],
            }),
        })
        coordinator = DesktopSuperAgent(
            task_manager=FakeTaskManager(),
            diagnostics=lambda quick=True: {"agents": []},
            deliver=lambda *args, **kwargs: self.fail("Runtime status should not call an external Agent"),
            registry=registry,
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-runtime",
            conversation_id="conversation-runtime",
            prompt="Show available runtimes and toolchain status",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertIn("2 Desktop runtimes are ready", outcome.reply)
        self.assertIn("Python 3.12", outcome.reply)
        self.assertIn("Not ready: Rust", outcome.reply)
        self.assertEqual("signalasi.desktop.runtime.status", registry.calls[0][0])
        self.assertEqual({"refresh": True}, registry.calls[0][1])

    def test_inspects_attachment_then_delegates_with_observation(self):
        manager = FakeTaskManager()
        registry = FakeRegistry({
            "signalasi.desktop.workspace.file.read.text": succeeded({
                "path": "downloads/input/brief.md",
                "text": "Release notes",
                "size_bytes": 13,
                "sha256": "0" * 64,
            }),
        })
        delivered: list[tuple[str, str, dict]] = []

        def deliver(agent_id, prompt, **kwargs):
            delivered.append((agent_id, prompt, kwargs))
            return {"reply": "Summary complete."}

        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": [{"id": "codex", "status": "ready"}]},
            deliver=deliver,
            registry=registry,
            memory=FakeMemory("- [decision] Use concise release summaries"),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-2",
            conversation_id="conversation-2",
            prompt="Summarize the attached project brief",
            compiled_prompt="compiled request",
            attachments=["downloads/input/brief.md"],
        )

        self.assertEqual(outcome.reply, "Summary complete.")
        self.assertEqual(outcome.delegate_agent_id, "codex")
        self.assertEqual(delivered[0][0], "codex")
        self.assertIn("Release notes", delivered[0][1])
        self.assertIn("Use concise release summaries", delivered[0][1])
        self.assertTrue(any(update.get("delegate_agent_id") == "codex" for update in manager.updates))

    def test_healthy_agent_wins_over_preferred_but_degraded_agent(self):
        coordinator = DesktopSuperAgent(
            task_manager=FakeTaskManager(),
            diagnostics=lambda quick=True: {
                "agents": [
                    {"id": "hermes", "status": "degraded"},
                    {"id": "codex", "status": "ready"},
                ]
            },
            deliver=lambda *args, **kwargs: {"reply": "Current research result."},
            registry=FakeRegistry({}),
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-research",
            conversation_id="conversation-research",
            prompt="Research the latest release news",
            compiled_prompt="compiled research request",
            attachments=[],
        )

        self.assertEqual(outcome.delegate_agent_id, "codex")

    def test_transient_tool_failure_is_replanned_and_retried(self):
        manager = FakeTaskManager()
        registry = FakeRegistry({
            "signalasi.desktop.windows.system.status": [
                failed("desktop_tool_busy", "Desktop tool capacity is busy", retryable=True),
                succeeded({
                    "platform": "Windows",
                    "release": "11",
                    "architecture": "AMD64",
                    "logical_cpu_count": 8,
                    "memory_total_bytes": 16 * 1024 ** 3,
                    "memory_available_bytes": 8 * 1024 ** 3,
                }),
            ],
        })
        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": []},
            deliver=lambda *args, **kwargs: self.fail("Verified direct tool should not delegate"),
            registry=registry,
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-retry",
            conversation_id="conversation-retry",
            prompt="Show computer status",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertIn("8.0 GB available", outcome.reply)
        self.assertEqual(len(registry.calls), 2)
        self.assertTrue(any(
            (event.get("metadata") or {}).get("phase") == "replan"
            for event in manager.events
        ))

    def test_unverified_tool_result_is_never_reported_as_success(self):
        manager = FakeTaskManager()
        unverified = succeeded({"name": "Notepad", "launched": True})
        unverified["verification"] = {"status": "failed", "message": "Launch was not observed"}
        registry = FakeRegistry({
            "signalasi.desktop.windows.app.launch": [dict(unverified), dict(unverified)],
        })
        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {"agents": []},
            deliver=lambda *args, **kwargs: self.fail("Direct action failure should not delegate"),
            registry=registry,
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-unverified",
            conversation_id="conversation-unverified",
            prompt="Open Notepad",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertNotIn("Launched Notepad", outcome.reply)
        self.assertIn("verification did not pass", outcome.reply)
        self.assertEqual(len(registry.calls), 1)

    def test_delegate_failure_is_isolated_and_next_agent_can_finish(self):
        manager = FakeTaskManager()
        deliveries: list[str] = []

        def deliver(agent_id, _prompt, **_kwargs):
            deliveries.append(agent_id)
            if agent_id == "hermes":
                raise TimeoutError("Hermes timed out")
            return {"reply": "Verified research result."}

        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {
                "agents": [
                    {"id": "hermes", "status": "ready"},
                    {"id": "codex", "status": "ready"},
                ]
            },
            deliver=deliver,
            registry=FakeRegistry({}),
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
        )

        outcome = coordinator.run(
            task_id="task-fallback",
            conversation_id="conversation-fallback",
            prompt="Research the latest release news",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertEqual(deliveries, ["hermes", "codex"])
        self.assertEqual(outcome.delegate_agent_id, "codex")
        self.assertEqual(outcome.reply, "Verified research result.")
        self.assertTrue(any(
            (event.get("metadata") or {}).get("phase") == "replan"
            and (event.get("metadata") or {}).get("failed_actor_id") == "hermes"
            for event in manager.events
        ))

    def test_delegate_attempts_are_bounded_and_return_recovery_options(self):
        manager = FakeTaskManager()
        deliveries: list[str] = []

        def deliver(agent_id, _prompt, **_kwargs):
            deliveries.append(agent_id)
            raise RuntimeError(f"{agent_id} unavailable")

        coordinator = DesktopSuperAgent(
            task_manager=manager,
            diagnostics=lambda quick=True: {
                "agents": [
                    {"id": "codex", "status": "ready"},
                    {"id": "hermes", "status": "ready"},
                ]
            },
            deliver=deliver,
            registry=FakeRegistry({}),
            memory=FakeMemory(),
            skills=FakeSkills(),
            mcp=FakeMcp(),
            loop_budget=AgentLoopBudget(max_iterations=4, max_delegate_attempts=1),
        )

        outcome = coordinator.run(
            task_id="task-bounded",
            conversation_id="conversation-bounded",
            prompt="Answer this question",
            compiled_prompt="compiled",
            attachments=[],
        )

        self.assertEqual(deliveries, ["codex"])
        self.assertIn("You can:", outcome.reply)
        finalize_events = [
            event for event in manager.events
            if (event.get("metadata") or {}).get("phase") == "finalize"
        ]
        self.assertTrue(finalize_events)
        self.assertFalse(any(
            (event.get("metadata") or {}).get("phase") == "learn"
            for event in manager.events
        ))


if __name__ == "__main__":
    unittest.main()
