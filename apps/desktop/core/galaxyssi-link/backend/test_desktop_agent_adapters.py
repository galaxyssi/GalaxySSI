import tempfile
import threading
import unittest
from pathlib import Path

from desktop_agent_adapters import (
    AgentAdapterConflict,
    AgentAdapterDescriptor,
    AgentAdapterProtocolError,
    AgentAdapterRequest,
    AgentDeliveryMode,
    AgentInvocationMode,
    DesktopAgentProvider,
    DesktopAgentStateStore,
)


def descriptor(agent_id: str = "codex") -> AgentAdapterDescriptor:
    return AgentAdapterDescriptor(
        agent_id=agent_id,
        name=agent_id.title(),
        kind="local-cli",
        adapter_type="test",
        timeout_seconds=2,
        capabilities=("conversation", "tasks"),
    )


class DesktopAgentAdaptersTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.state_path = Path(self.temporary.name) / "adapter-state.json"
        self.calls: list[tuple[str, str]] = []

    def tearDown(self):
        self.temporary.cleanup()

    def provider(self, *descriptors: AgentAdapterDescriptor) -> DesktopAgentProvider:
        def execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            return f"reply:{agent_id}:{request.prompt}"

        return DesktopAgentProvider(
            descriptors=descriptors or (descriptor(),),
            store=DesktopAgentStateStore(self.state_path),
            executor=execute,
        )

    def test_named_adapters_are_enumerated_through_one_provider(self):
        provider = self.provider(
            descriptor("hermes"),
            descriptor("codex"),
            descriptor("claude"),
            descriptor("gemini"),
            descriptor("openclaw"),
            descriptor("local-llm"),
            descriptor("cloud-model"),
            descriptor("windows"),
            descriptor("android"),
        )

        adapters = {item["agent_id"]: item["adapter_type"] for item in provider.enumerate()}

        self.assertEqual("hermes-cli", adapters["hermes"])
        self.assertEqual("codex-app-server-or-cli", adapters["codex"])
        self.assertEqual("claude-code-cli", adapters["claude"])
        self.assertEqual("gemini-cli", adapters["gemini"])
        self.assertEqual("openclaw-cli", adapters["openclaw"])
        self.assertEqual("local-model-api", adapters["local-llm"])
        self.assertEqual("cloud-model-api", adapters["cloud-model"])
        self.assertEqual("windows-host-tools", adapters["windows"])
        self.assertEqual("android-device-tools", adapters["android"])
        codex = next(
            item for item in provider.enumerate()
            if item["agent_id"] == "codex"
        )
        self.assertEqual(
            ["direct", "tool", "handoff"],
            codex["invocation_modes"],
        )

    def test_agent_tool_receipt_preserves_caller_and_response_ownership(self):
        provider = self.provider(descriptor("codex"))
        result = provider.deliver(AgentAdapterRequest(
            agent_id="codex",
            prompt="Inspect this implementation",
            run_id="child-run",
            invocation_mode=AgentInvocationMode.TOOL,
            caller_agent_id="galaxyssi.desktop.super-agent",
            parent_run_id="parent-run",
            handoff_chain=("coordinator",),
        ))

        public = result.public()

        self.assertEqual("completed", result.state)
        self.assertEqual("tool", public["invocation_mode"])
        self.assertEqual("galaxyssi.desktop.super-agent", public["caller_agent_id"])
        self.assertEqual("parent-run", public["parent_run_id"])
        self.assertEqual(
            ["coordinator", "galaxyssi.desktop.super-agent"],
            public["handoff_chain"],
        )
        self.assertEqual(
            "galaxyssi.desktop.super-agent",
            public["response_owner_agent_id"],
        )

    def test_handoff_transfers_response_ownership_to_target_agent(self):
        result = self.provider(descriptor("hermes")).deliver(AgentAdapterRequest(
            agent_id="hermes",
            prompt="Finish the research",
            run_id="handoff-run",
            invocation_mode=AgentInvocationMode.HANDOFF,
            caller_agent_id="coordinator",
            parent_run_id="parent-run",
        ))

        self.assertEqual("handoff", result.public()["invocation_mode"])
        self.assertEqual("hermes", result.public()["response_owner_agent_id"])

    def test_agent_invocation_rejects_self_call_cycle_and_excess_depth(self):
        provider = self.provider(descriptor("codex"))

        with self.assertRaisesRegex(AgentAdapterConflict, "cannot invoke itself"):
            provider.deliver(AgentAdapterRequest(
                agent_id="codex",
                prompt="self call",
                invocation_mode=AgentInvocationMode.TOOL,
                caller_agent_id="codex",
                parent_run_id="parent",
            ))
        with self.assertRaisesRegex(AgentAdapterConflict, "cycle"):
            provider.deliver(AgentAdapterRequest(
                agent_id="codex",
                prompt="cycle",
                invocation_mode=AgentInvocationMode.HANDOFF,
                caller_agent_id="hermes",
                parent_run_id="parent",
                handoff_chain=("codex", "hermes"),
            ))
        with self.assertRaisesRegex(AgentAdapterConflict, "already contains a cycle"):
            provider.deliver(AgentAdapterRequest(
                agent_id="codex",
                prompt="existing cycle",
                invocation_mode=AgentInvocationMode.TOOL,
                caller_agent_id="hermes",
                parent_run_id="parent",
                handoff_chain=("root", "hermes", "root"),
            ))
        with self.assertRaisesRegex(AgentAdapterConflict, "maximum depth"):
            provider.deliver(AgentAdapterRequest(
                agent_id="codex",
                prompt="too deep",
                invocation_mode=AgentInvocationMode.HANDOFF,
                caller_agent_id="openclaw",
                parent_run_id="parent",
                handoff_chain=("root", "hermes", "claude", "openclaw"),
            ))

    def test_acp_descriptor_reports_the_live_transport(self):
        acp_descriptor = AgentAdapterDescriptor(
            agent_id="hermes",
            name="Hermes",
            kind="local-cli",
            adapter_type="acp",
            timeout_seconds=2,
            capabilities=("conversation", "tasks"),
        )

        adapter = self.provider(acp_descriptor).enumerate()[0]

        self.assertEqual("acp", adapter["adapter_type"])

    def test_respond_receipt_survives_provider_recreation(self):
        request = AgentAdapterRequest(
            agent_id="codex",
            prompt="build it",
            run_id="run-1",
            idempotency_key="stable-key",
        )
        first = self.provider().deliver(request)
        replay = self.provider().deliver(request)

        self.assertEqual("completed", first.state)
        self.assertEqual(first.reply, replay.reply)
        self.assertTrue(replay.replayed)
        self.assertFalse(replay.executed)
        self.assertEqual([("codex", "build it")], self.calls)

    def test_same_idempotency_key_rejects_different_request(self):
        provider = self.provider()
        provider.deliver(AgentAdapterRequest(agent_id="codex", prompt="one", idempotency_key="same"))

        with self.assertRaises(AgentAdapterConflict):
            provider.deliver(AgentAdapterRequest(agent_id="codex", prompt="two", idempotency_key="same"))

    def test_observe_persists_context_without_executing_or_replying(self):
        provider = self.provider(descriptor("hermes"))
        result = provider.deliver(AgentAdapterRequest(
            agent_id="hermes",
            prompt="read-only context",
            run_id="observe-1",
            delivery_mode=AgentDeliveryMode.OBSERVE,
            conversation_id="conversation-1",
        ))

        self.assertEqual("observed", result.state)
        self.assertEqual("", result.reply)
        self.assertEqual([], self.calls)
        self.assertEqual("read-only context", provider.observations("hermes")[0]["content"])

    def test_ignore_has_no_execution_observation_or_run_receipt(self):
        provider = self.provider(descriptor("claude"))
        result = provider.deliver(AgentAdapterRequest(
            agent_id="claude",
            prompt="do not expose",
            run_id="ignore-1",
            delivery_mode=AgentDeliveryMode.IGNORE,
        ))

        self.assertEqual("ignored", result.state)
        self.assertEqual([], self.calls)
        self.assertEqual([], provider.observations("claude"))
        self.assertIsNone(provider.status("claude", "ignore-1"))

    def test_missing_required_protocol_feature_fails_before_execution(self):
        provider = self.provider()

        with self.assertRaises(AgentAdapterProtocolError):
            provider.deliver(AgentAdapterRequest(
                agent_id="codex",
                prompt="hello",
                required_features=frozenset({"unsupported-feature"}),
            ))

        self.assertEqual([], self.calls)

    def test_process_restart_marks_nonterminal_run_recoverable(self):
        store = DesktopAgentStateStore(self.state_path)
        request = AgentAdapterRequest(
            agent_id="codex",
            prompt="long task",
            run_id="interrupted-run",
            idempotency_key="interrupted-key",
            checkpoint={"step": 3},
        ).normalized()
        self.assertIsNone(store.claim(request, descriptor(), "1.0"))

        recovered = DesktopAgentStateStore(self.state_path).recoverable("codex")

        self.assertEqual(1, len(recovered))
        self.assertEqual("interrupted", recovered[0].state)
        self.assertEqual({"step": 3}, recovered[0].checkpoint)
        self.assertEqual("run_interrupted", DesktopAgentStateStore(self.state_path).events("interrupted-run")[-1]["type"])

    def test_concurrent_duplicate_waits_and_executes_once(self):
        started = threading.Event()
        release = threading.Event()
        results = []

        def execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            started.set()
            release.wait(timeout=2)
            return "done"

        provider = DesktopAgentProvider(
            descriptors=(descriptor(),),
            store=DesktopAgentStateStore(self.state_path),
            executor=execute,
        )
        request = AgentAdapterRequest(
            agent_id="codex",
            prompt="once",
            run_id="concurrent-run",
            idempotency_key="concurrent-key",
        )
        first = threading.Thread(target=lambda: results.append(provider.deliver(request)))
        second = threading.Thread(target=lambda: results.append(provider.deliver(request)))
        first.start()
        self.assertTrue(started.wait(timeout=1))
        second.start()
        release.set()
        first.join(timeout=2)
        second.join(timeout=2)

        self.assertEqual(2, len(results))
        self.assertEqual([("codex", "once")], self.calls)
        self.assertEqual({"completed"}, {item.state for item in results})


if __name__ == "__main__":
    unittest.main()
