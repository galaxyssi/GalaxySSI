from __future__ import annotations

import asyncio
import json
import os
import sys
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path

from acp_runtime import AcpRuntime


FAKE_AGENT = r'''
import asyncio
import json
import os
import uuid
from pathlib import Path

import acp
from acp.schema import (
    AgentCapabilities,
    AgentPlanUpdate,
    InitializeResponse,
    LoadSessionResponse,
    NewSessionResponse,
    PermissionOption,
    PlanEntry,
    PromptResponse,
    ToolCallStart,
    ToolCallUpdate,
)


class FakeAgent:
    def __init__(self):
        self.client = None
        self.cancelled = set()

    def on_connect(self, client):
        self.client = client

    def log(self, kind, **payload):
        path = Path(os.environ["FAKE_ACP_LOG"])
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"kind": kind, **payload}) + "\n")

    async def initialize(self, protocol_version, **_kwargs):
        self.log("initialize", protocol_version=protocol_version)
        return InitializeResponse(
            protocol_version=protocol_version,
            agent_capabilities=AgentCapabilities(load_session=True),
        )

    async def authenticate(self, **_kwargs):
        return None

    async def new_session(self, cwd, **_kwargs):
        session_id = str(uuid.uuid4())
        self.log("new_session", session_id=session_id, cwd=cwd)
        return NewSessionResponse(session_id=session_id)

    async def load_session(self, cwd, session_id, **_kwargs):
        self.log("load_session", session_id=session_id, cwd=cwd)
        return LoadSessionResponse()

    async def prompt(self, prompt, session_id, **_kwargs):
        text = "".join(getattr(item, "text", "") for item in prompt)
        self.log("prompt", session_id=session_id, text=text)
        await self.client.session_update(
            session_id=session_id,
            update=acp.update_agent_thought_text("Inspecting the request."),
        )
        await self.client.session_update(
            session_id=session_id,
            update=AgentPlanUpdate(
                session_update="plan",
                entries=[
                    PlanEntry(
                        content="Complete the request",
                        priority="high",
                        status="in_progress",
                    )
                ],
            ),
        )
        tool = ToolCallStart(
            session_update="tool_call",
            tool_call_id="fake-tool",
            title="Run fake tool",
            kind="execute",
            status="in_progress",
        )
        await self.client.session_update(session_id=session_id, update=tool)
        if text == "permission":
            try:
                decision = await self.client.request_permission(
                    session_id=session_id,
                    tool_call=ToolCallUpdate(
                        tool_call_id="fake-tool",
                        title="Run fake tool",
                        kind="execute",
                        status="in_progress",
                    ),
                    options=[
                        PermissionOption(
                            option_id="allow",
                            name="Allow once",
                            kind="allow_once",
                        ),
                        PermissionOption(
                            option_id="reject",
                            name="Reject once",
                            kind="reject_once",
                        ),
                    ],
                )
                selected = getattr(decision.outcome, "option_id", "cancelled")
                reply = f"permission:{selected}"
            except Exception as exc:
                reply = f"permission_error:{type(exc).__name__}:{exc}"
        elif text.startswith("read:"):
            result = await self.client.read_text_file(
                session_id=session_id,
                path=text.split(":", 1)[1],
            )
            reply = result.content
        elif text.startswith("write:"):
            try:
                await self.client.write_text_file(
                    session_id=session_id,
                    path=text.split(":", 1)[1],
                    content="agent content",
                )
                reply = "write:ok"
            except Exception as exc:
                reply = f"write_error:{type(exc).__name__}:{exc}"
        elif text == "wait":
            for _ in range(500):
                if session_id in self.cancelled:
                    return PromptResponse(stop_reason="cancelled")
                await asyncio.sleep(0.01)
            reply = "waited"
        else:
            reply = f"reply:{text}"
        await self.client.session_update(
            session_id=session_id,
            update=acp.update_agent_message_text(reply),
        )
        return PromptResponse(stop_reason="end_turn")

    async def cancel(self, session_id, **_kwargs):
        self.cancelled.add(session_id)
        self.log("cancel", session_id=session_id)

    async def ext_method(self, _method, _params):
        return {}

    async def ext_notification(self, _method, _params):
        return None


asyncio.run(acp.run_agent(FakeAgent()))
'''


class AcpRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.agent_script = self.root / "fake_acp_agent.py"
        self.agent_script.write_text(FAKE_AGENT, encoding="utf-8")
        self.log_path = self.root / "agent.jsonl"
        self.previous_log = os.environ.get("FAKE_ACP_LOG")
        self.previous_state = os.environ.get("GALAXYSSI_STATE_DIR")
        os.environ["FAKE_ACP_LOG"] = str(self.log_path)
        os.environ["GALAXYSSI_STATE_DIR"] = str(self.root / "state")
        command = f'"{sys.executable}" "{self.agent_script}"'
        self.config = {
            "enabled": True,
            "max_processes": 5,
            "idle_timeout_seconds": 600,
            "agents": {
                "hermes": {
                    "enabled": True,
                    "command": command,
                    "prewarm": False,
                },
            },
        }
        self.runtime = AcpRuntime(
            state_path=self.root / "acp-runtime.json",
            config_loader=lambda: self.config,
            maintenance_interval_seconds=60,
        )

    def tearDown(self) -> None:
        self.runtime.shutdown()
        if self.previous_log is None:
            os.environ.pop("FAKE_ACP_LOG", None)
        else:
            os.environ["FAKE_ACP_LOG"] = self.previous_log
        if self.previous_state is None:
            os.environ.pop("GALAXYSSI_STATE_DIR", None)
        else:
            os.environ["GALAXYSSI_STATE_DIR"] = self.previous_state
        self.temporary.cleanup()

    def execute(
        self,
        prompt: str,
        *,
        route: str = "phone-a",
        conversation: str = "conversation-a",
        profile: str = "desktop_executor",
        events: list | None = None,
        run_id: str | None = None,
    ) -> str | None:
        sink = None
        if events is not None:
            sink = lambda kind, title, **kwargs: events.append(
                {"kind": kind, "title": title, **kwargs}
            )
        return self.runtime.execute(
            "hermes",
            prompt,
            run_id=run_id or str(uuid.uuid4()),
            client_route_id=route,
            conversation_id=conversation,
            working_directory=self.root / "workspace",
            access_profile=profile,
            timeout_seconds=10,
            event_sink=sink,
        )

    def logs(self) -> list[dict]:
        if not self.log_path.exists():
            return []
        return [
            json.loads(line)
            for line in self.log_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    def test_hermes_acp_streams_events_and_returns_message(self) -> None:
        events = []
        self.assertEqual("reply:hello", self.execute("hello", events=events))
        self.assertEqual("running", self.runtime.agent_health("hermes")["status"])
        self.assertIn("reasoning", {item["kind"] for item in events})
        self.assertIn("plan", {item["kind"] for item in events})
        self.assertIn("tool", {item["kind"] for item in events})

    def test_reuses_session_for_same_phone_conversation(self) -> None:
        self.execute("first")
        self.execute("second")
        logs = self.logs()
        self.assertEqual(1, len([row for row in logs if row["kind"] == "new_session"]))
        prompts = [row for row in logs if row["kind"] == "prompt"]
        self.assertEqual(prompts[0]["session_id"], prompts[1]["session_id"])

    def test_isolates_sessions_by_phone_route(self) -> None:
        self.execute("first", route="phone-a")
        self.execute("second", route="phone-b")
        prompts = [row for row in self.logs() if row["kind"] == "prompt"]
        self.assertNotEqual(prompts[0]["session_id"], prompts[1]["session_id"])

    def test_process_restart_loads_the_persisted_hermes_session(self) -> None:
        self.execute("first")
        first_session = [
            row for row in self.logs() if row["kind"] == "prompt"
        ][0]["session_id"]
        self.runtime.restart("hermes")
        self.execute("second")
        logs = self.logs()
        self.assertTrue(any(
            row["kind"] == "load_session"
            and row["session_id"] == first_session
            for row in logs
        ))
        self.assertEqual(
            first_session,
            [row for row in logs if row["kind"] == "prompt"][-1]["session_id"],
        )

    def test_permission_requests_are_allowed_for_every_access_profile(self) -> None:
        self.assertEqual(
            "permission:allow",
            self.execute("permission", conversation="allow", profile="desktop_executor"),
        )
        self.assertEqual(
            "permission:allow",
            self.execute("permission", conversation="deny", profile="restricted"),
        )

    def test_file_callback_is_scoped_to_session_workspace(self) -> None:
        workspace = self.root / "workspace"
        workspace.mkdir(parents=True, exist_ok=True)
        (workspace / "note.txt").write_text("workspace evidence", encoding="utf-8")
        self.assertEqual("workspace evidence", self.execute("read:note.txt"))
        session_id = next(iter(self.runtime._sessions.values())).external_session_id
        with self.assertRaises(PermissionError):
            self.runtime._session_file("hermes", session_id, "../outside.txt")

    def test_file_callback_rejects_host_execution_configuration(self) -> None:
        workspace = self.root / "workspace"
        workspace.mkdir(parents=True, exist_ok=True)

        reply = self.execute("write:.galaxyssi-task.json")

        self.assertIn(
            "write_error:RequestError:"
            "Host execution configuration write is not allowed",
            reply,
        )
        self.assertFalse((workspace / ".galaxyssi-task.json").exists())
        audit_path = (
            self.root
            / "state"
            / "security"
            / "host-config-write-audit.jsonl"
        )
        self.assertIn(
            ".galaxyssi-task.json",
            audit_path.read_text(encoding="utf-8"),
        )

    def test_cancel_reaches_active_acp_session(self) -> None:
        run_id = str(uuid.uuid4())
        result: dict[str, object] = {}

        def worker() -> None:
            try:
                result["reply"] = self.execute("wait", run_id=run_id)
            except Exception as exc:
                result["error"] = exc

        thread = threading.Thread(target=worker)
        thread.start()
        deadline = time.time() + 5
        while time.time() < deadline:
            if run_id in self.runtime._run_bindings:
                break
            time.sleep(0.01)
        self.assertTrue(self.runtime.cancel(run_id))
        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertIn("error", result)
        self.assertTrue(any(row["kind"] == "cancel" for row in self.logs()))

    def test_missing_command_returns_legacy_fallback_signal(self) -> None:
        self.config["agents"]["hermes"]["command"] = "missing-galaxyssi-acp"
        self.assertIsNone(self.execute("hello"))
        self.assertEqual("needs_setup", self.runtime.agent_health("hermes")["status"])

    def test_prewarmed_process_is_kept_past_idle_timeout(self) -> None:
        self.config["idle_timeout_seconds"] = 1
        self.config["agents"]["hermes"]["prewarm"] = True
        first = self.runtime.prewarm("hermes")
        first_pid = first["pid"]
        self.runtime._processes["hermes"].last_used_at -= 60

        health = self.runtime.maintain()
        current = next(
            item
            for item in health["processes"]
            if item["agent_id"] == "hermes"
        )

        self.assertEqual(first_pid, current["pid"])
        self.assertEqual("running", current["status"])
        self.assertTrue(current["prewarm"])

    def test_keep_alive_restarts_crashed_prewarmed_process(self) -> None:
        self.config["agents"]["hermes"]["prewarm"] = True
        first = self.runtime.prewarm("hermes")
        first_pid = first["pid"]

        async def stop_process() -> None:
            process = self.runtime._processes["hermes"].process
            process.kill()
            await process.wait()

        future = asyncio.run_coroutine_threadsafe(
            stop_process(),
            self.runtime._loop,
        )
        future.result(timeout=5)

        health = self.runtime.maintain()
        current = next(
            item
            for item in health["processes"]
            if item["agent_id"] == "hermes"
        )

        self.assertNotEqual(first_pid, current["pid"])
        self.assertEqual("running", current["status"])
        self.assertEqual(1, health["metrics"]["prewarm_starts"])
        self.assertEqual(1, health["metrics"]["keepalive_restarts"])

    def test_execute_reports_warm_reuse_after_prewarm(self) -> None:
        self.runtime.prewarm("hermes")

        self.assertEqual("reply:hello", self.execute("hello"))
        health = self.runtime.health()
        current = next(
            item
            for item in health["processes"]
            if item["agent_id"] == "hermes"
        )

        self.assertEqual(1, current["warm_reuses"])
        self.assertEqual(1, health["metrics"]["warm_reuses"])
        self.assertGreaterEqual(current["startup_latency_ms"], 0)

    def test_hermes_acp_uses_safe_mode_by_default(self) -> None:
        previous = os.environ.pop(
            "GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS",
            None,
        )
        try:
            environment = self.runtime._agent_environment("hermes")
            self.assertEqual("1", environment["HERMES_SAFE_MODE"])
            self.assertEqual("1", environment["GALAXYSSI_ACP_CLIENT"])
        finally:
            if previous is not None:
                os.environ[
                    "GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS"
                ] = previous

    def test_hermes_acp_can_explicitly_load_user_extensions(self) -> None:
        previous = os.environ.get(
            "GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS"
        )
        previous_safe_mode = os.environ.get("HERMES_SAFE_MODE")
        os.environ["GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS"] = "1"
        os.environ.pop("HERMES_SAFE_MODE", None)
        try:
            environment = self.runtime._agent_environment("hermes")
            self.assertNotIn("HERMES_SAFE_MODE", environment)
        finally:
            if previous is None:
                os.environ.pop(
                    "GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS",
                    None,
                )
            else:
                os.environ[
                    "GALAXYSSI_HERMES_ACP_USE_USER_EXTENSIONS"
                ] = previous
            if previous_safe_mode is not None:
                os.environ["HERMES_SAFE_MODE"] = previous_safe_mode


if __name__ == "__main__":
    unittest.main()
