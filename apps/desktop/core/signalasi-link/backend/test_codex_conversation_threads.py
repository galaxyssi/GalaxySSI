import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import codex_app_server


class CodexConversationThreadTests(unittest.TestCase):
    def setUp(self):
        self.temporary_workspace = tempfile.TemporaryDirectory()
        self.workspace_environment = patch.dict(
            os.environ,
            {
                "SIGNALASI_WORKSPACE_ROOT": self.temporary_workspace.name,
                "SIGNALASI_STATE_DIR": str(
                    Path(self.temporary_workspace.name) / "state"
                ),
            },
        )
        self.workspace_environment.start()

    def tearDown(self):
        self.workspace_environment.stop()
        self.temporary_workspace.cleanup()

    def test_app_server_exposes_visible_tool_events_without_reasoning_content(self):
        events = []
        server = codex_app_server.CodexAppServer(
            "codex",
            {},
            lambda task_id, event: events.append((task_id, event)),
        )
        server._runs["task-1"] = codex_app_server.CodexRun(
            task_id="task-1",
            thread_id="thread-1",
            turn_id="turn-1",
        )
        server._turn_tasks["turn-1"] = "task-1"

        server._handle_event({
            "method": "item/started",
            "params": {
                "turnId": "turn-1",
                "item": {
                    "id": "command-1",
                    "type": "commandExecution",
                    "command": ["python", "verify.py"],
                },
            },
        })
        server._handle_event({
            "method": "item/started",
            "params": {
                "turnId": "turn-1",
                "item": {
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "private internal reasoning must not leave the server",
                },
            },
        })

        command = events[0][1]
        reasoning = events[1][1]
        self.assertEqual("command", command["event_kind"])
        self.assertEqual("python verify.py", command["event_detail"])
        self.assertEqual("reasoning", reasoning["event_kind"])
        self.assertEqual("", reasoning["event_detail"])
        self.assertNotIn("private internal reasoning", str(reasoning))

    def test_web_search_event_exposes_the_model_selected_query(self):
        events = []
        server = codex_app_server.CodexAppServer(
            "codex",
            {},
            lambda task_id, event: events.append((task_id, event)),
        )
        server._runs["task-search"] = codex_app_server.CodexRun(
            task_id="task-search",
            thread_id="thread-search",
            turn_id="turn-search",
        )
        server._turn_tasks["turn-search"] = "task-search"

        server._handle_event({
            "method": "item/started",
            "params": {
                "turnId": "turn-search",
                "item": {
                    "id": "search-1",
                    "type": "webSearch",
                    "action": {"queries": ["Zhuhai current weather"]},
                },
            },
        })

        event = events[-1][1]
        self.assertEqual("network", event["event_kind"])
        self.assertEqual("Zhuhai current weather", event["event_detail"])
        self.assertEqual("webSearch", event["event_metadata"]["item_type"])

    def test_file_change_event_does_not_start_file_tree_audit(self):
        server, run, events = self._event_server()
        server._handle_event({
            "method": "item/completed",
            "params": {
                "turnId": run.turn_id,
                "item": {
                    "id": "file-1",
                    "type": "fileChange",
                    "changes": [{"path": "result.txt"}],
                },
            },
        })
        self.assertFalse(hasattr(run, "workspace_capture"))
        self.assertEqual("running", events[-1][1]["status"])

    @staticmethod
    def _event_server():
        events = []
        server = codex_app_server.CodexAppServer(
            "codex",
            {},
            lambda task_id, event: events.append((task_id, event)),
        )
        run = codex_app_server.CodexRun(
            task_id="task-visible",
            thread_id="thread-visible",
            turn_id="turn-visible",
        )
        server._runs[run.task_id] = run
        server._turn_tasks[run.turn_id] = run.task_id
        return server, run, events

    def test_visible_codex_progress_preserves_commentary_reasoning_and_image_events(self):
        server, run, events = self._event_server()

        server._handle_event({
            "method": "item/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "item": {
                    "id": "commentary-1",
                    "type": "agentMessage",
                    "phase": "commentary",
                    "text": "I will inspect each answer and flag uncertain regions.",
                },
            },
        })
        server._handle_event({
            "method": "item/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "item": {
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "summary": ["Comparing the written answers with the worksheet prompts."],
                    "content": ["private reasoning must not be forwarded"],
                },
            },
        })
        for method in ("item/started", "item/completed"):
            server._handle_event({
                "method": method,
                "params": {
                    "threadId": run.thread_id,
                    "turnId": run.turn_id,
                    "item": {"id": "image-1", "type": "imageView", "path": "homework.jpg"},
                },
            })
        server._handle_event({
            "method": "item/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "item": {
                    "id": "answer-1",
                    "type": "agentMessage",
                    "phase": "final_answer",
                    "text": "The worksheet is mostly correct.",
                },
            },
        })
        server._handle_event({
            "method": "turn/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "turn": {"id": run.turn_id, "status": "completed"},
            },
        })

        progress = [event["progress_event"] for _, event in events if "progress_event" in event]
        self.assertEqual(
            ["commentary", "reasoning_summary", "image_view", "image_view"],
            [event["code"] for event in progress],
        )
        self.assertEqual(["running", "completed"], [event["status"] for event in progress[-2:]])
        self.assertNotIn("private reasoning", " ".join(event["detail"] for event in progress))
        self.assertEqual("completed", events[-1][1]["status"])
        self.assertEqual("The worksheet is mostly correct.", events[-1][1]["result"])

    def test_reasoning_summary_delta_is_used_without_forwarding_reasoning_text_delta(self):
        server, run, events = self._event_server()

        server._handle_event({
            "method": "item/reasoning/summaryTextDelta",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "reasoning-2",
                "summaryIndex": 0,
                "delta": "Checking the visible worksheet fields.",
            },
        })
        server._handle_event({
            "method": "item/reasoning/textDelta",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "reasoning-2",
                "contentIndex": 0,
                "delta": "hidden chain of thought",
            },
        })
        server._handle_event({
            "method": "item/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "item": {"id": "reasoning-2", "type": "reasoning", "summary": [], "content": []},
            },
        })

        progress = [event["progress_event"] for _, event in events if "progress_event" in event]
        self.assertEqual(1, len(progress))
        self.assertEqual("Checking the visible worksheet fields.", progress[0]["detail"])
        self.assertNotIn("hidden chain", progress[0]["detail"])

    def test_first_agent_output_emits_one_telemetry_milestone(self):
        server, run, events = self._event_server()

        for delta in ("Hello", " world"):
            server._handle_event({
                "method": "item/agentMessage/delta",
                "params": {
                    "threadId": run.thread_id,
                    "turnId": run.turn_id,
                    "itemId": "answer-stream",
                    "delta": delta,
                },
            })
        server._handle_event({
            "method": "item/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "item": {
                    "id": "answer-stream",
                    "type": "agentMessage",
                    "phase": "final_answer",
                    "text": "Hello world",
                },
            },
        })

        telemetry = [
            event for _, event in events
            if event.get("trace_stage") == "agent_first_output"
        ]
        self.assertEqual(1, len(telemetry))
        self.assertTrue(telemetry[0]["telemetry_only"])
        self.assertEqual("codex", telemetry[0]["trace_detail"])

    def test_visible_answer_delta_is_cumulative_and_matches_final(self):
        server, run, events = self._event_server()

        for delta in ("Hello", " world"):
            server._handle_event({
                "method": "item/agentMessage/delta",
                "params": {
                    "threadId": run.thread_id,
                    "turnId": run.turn_id,
                    "itemId": "answer-stream",
                    "phase": "final_answer",
                    "delta": delta,
                },
            })
        server._handle_event({
            "method": "item/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "item": {
                    "id": "answer-stream",
                    "type": "agentMessage",
                    "phase": "final_answer",
                    "text": "Hello world",
                },
            },
        })
        server._handle_event({
            "method": "turn/completed",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "turn": {"status": "completed"},
            },
        })

        deltas = [
            event["output_delta"]
            for _, event in events
            if isinstance(event.get("output_delta"), dict)
        ]
        self.assertEqual([1, 2], [event["sequence"] for event in deltas])
        self.assertEqual("Hello", deltas[0]["text"])
        self.assertEqual("Hello world", deltas[-1]["text"])
        self.assertEqual(events[-1][1]["result"], deltas[-1]["text"])

    def test_private_reasoning_delta_never_becomes_output_delta(self):
        server, run, events = self._event_server()

        server._handle_event({
            "method": "item/reasoning/textDelta",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "reasoning-private",
                "delta": "private chain of thought",
            },
        })
        server._handle_event({
            "method": "item/agentMessage/delta",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "commentary-visible",
                "phase": "commentary",
                "delta": "I am checking the file.",
            },
        })

        self.assertFalse(any("output_delta" in event for _, event in events))
        self.assertNotIn("private chain of thought", str(events))

    def test_command_approval_request_is_accepted_immediately(self):
        server, run, events = self._event_server()
        responses = []
        server._write_server_response = lambda request_id, result: responses.append(
            (request_id, result)
        )

        server._handle_event({
            "jsonrpc": "2.0",
            "id": 41,
            "method": "item/commandExecution/requestApproval",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "command-approval",
                "startedAtMs": int(time.time() * 1000),
                "command": "python verify.py",
                "cwd": "C:/workspace",
                "reason": "Run the generated verification",
            },
        })

        self.assertEqual([(41, {"decision": "accept"})], responses)
        self.assertEqual("running", events[-1][1]["status"])
        self.assertEqual({}, events[-1][1]["approval_request"])
        self.assertEqual({}, run.pending_requests)

    def test_file_change_approval_request_is_accepted_immediately(self):
        server, run, events = self._event_server()
        responses = []
        server._write_server_response = lambda request_id, result: responses.append(
            (request_id, result)
        )
        server._handle_event({
            "jsonrpc": "2.0",
            "id": "approval-request",
            "method": "item/fileChange/requestApproval",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "file-change",
                "startedAtMs": int(time.time() * 1000),
                "reason": "Write outside the task workspace",
                "grantRoot": "C:/shared-output",
            },
        })
        self.assertEqual(
            [("approval-request", {"decision": "accept"})],
            responses,
        )
        self.assertEqual("running", events[-1][1]["status"])
        self.assertEqual({}, events[-1][1]["approval_request"])
        self.assertEqual({}, run.pending_requests)

    def test_plan_only_command_approval_is_declined(self):
        from agent_execution_harness import AgentExecutionMode, execution_policy_for

        server, run, events = self._event_server()
        run.execution_policy = execution_policy_for(
            "Return a phone ActionPlan",
            requested_execution_mode=AgentExecutionMode.PLAN_ONLY,
        )
        responses = []
        server._write_server_response = lambda request_id, result: responses.append(
            (request_id, result)
        )

        server._handle_event({
            "jsonrpc": "2.0",
            "id": 42,
            "method": "item/commandExecution/requestApproval",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "itemId": "blocked-phone-plan-command",
                "startedAtMs": int(time.time() * 1000),
                "command": "git clone https://github.com/signalasi/SignalASI",
                "cwd": "C:/workspace",
                "reason": "Inspect the repository",
            },
        })

        self.assertEqual([(42, {"decision": "decline"})], responses)
        self.assertIn("phone ActionPlan", events[-1][1]["current_step"])

    def test_same_conversation_reuses_thread(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(
            codex_app_server.CodexAppServer,
            "_begin_host_config_guard",
        ) as host_guard:
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method == "thread/start":
                    return {"thread": {"id": "thread-1"}}
                return {"turn": {"id": f"turn-{len(calls)}"}}

            server._request = request
            first = server.start_task("task-1", "first", temporary, conversation_id="conversation-1")
            first.finished = True
            second = server.start_task("task-2", "second", temporary, conversation_id="conversation-1")

            self.assertEqual(first.thread_id, "thread-1")
            self.assertEqual(second.thread_id, "thread-1")
            self.assertEqual([method for method, _, _ in calls].count("thread/start"), 1)
            self.assertEqual([method for method, _, _ in calls].count("turn/start"), 2)
            thread_start = next(params for method, params, _ in calls if method == "thread/start")
            self.assertEqual("never", thread_start["approvalPolicy"])
            self.assertEqual({"web_search": "live"}, thread_start["config"])
            self.assertEqual(
                codex_app_server.CODEX_DYNAMIC_SEARCH_TOOL,
                thread_start["dynamicTools"][0]["name"],
            )
            self.assertEqual(
                codex_app_server.CODEX_DYNAMIC_FETCH_TOOL,
                thread_start["dynamicTools"][1]["name"],
            )
            self.assertIn(
                "Decide for yourself whether current external information is needed",
                thread_start["developerInstructions"],
            )
            self.assertIn(
                "Prefer Codex native live web search",
                thread_start["developerInstructions"],
            )
            self.assertIn(
                "call `signalasi_parallel_web_search` once",
                thread_start["developerInstructions"],
            )
            turn_inputs = [params["input"][0]["text"] for method, params, _ in calls if method == "turn/start"]
            self.assertIn("first", turn_inputs[0])
            self.assertNotIn("Do not synthesize replacement media or data.", turn_inputs[0])
            self.assertNotIn("SignalASI execution contract:", turn_inputs[0])
            self.assertIn("SignalASI response policy:", turn_inputs[0])
            self.assertLess(len(turn_inputs[0]), 1_800)
            turn_starts = [params for method, params, _ in calls if method == "turn/start"]
            self.assertEqual(["low", "low"], [params["effort"] for params in turn_starts])
            host_guard.assert_not_called()
            self.assertTrue(server.delete_conversation("conversation-1"))
            self.assertNotIn(server._conversation_key("conversation-1"), server._conversation_threads)

    def test_build_task_uses_medium_reasoning_without_an_absolute_deadline(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(codex_app_server.threading, "Thread"), patch.object(
            codex_app_server.CodexAppServer,
            "_begin_host_config_guard",
        ) as host_guard:
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method == "thread/start":
                    return {"thread": {"id": "thread-build"}}
                return {"turn": {"id": "turn-build"}}

            server._request = request
            run = server.start_task(
                "task-build",
                "Build an Android phone game and return the APK",
                temporary,
            )

            turn = next(params for method, params, _ in calls if method == "turn/start")
            self.assertEqual("medium", turn["effort"])
            self.assertEqual("build", run.execution_policy.task_kind.value)
            self.assertIsNone(run.execution_policy.public()["absolute_timeout_seconds"])
            self.assertIn(
                "multi-file project must be packaged as ZIP",
                turn["input"][0]["text"],
            )
            host_guard.assert_called_once()

    def test_same_tool_failure_replans_once_then_exhausts_the_budget(self):
        server, run, _events = self._event_server()
        started = []

        class ImmediateThread:
            def __init__(self, target, args=(), kwargs=None, **_ignored):
                self.target = target
                self.args = args
                self.kwargs = kwargs or {}

            def start(self):
                started.append((self.target, self.args, self.kwargs))

        failed_item = {
            "id": "command-failure",
            "type": "commandExecution",
            "status": "failed",
            "command": ["python", "verify.py"],
        }
        with patch.object(codex_app_server.threading, "Thread", ImmediateThread):
            server._record_failed_item(run, failed_item)
            server._record_failed_item(run, failed_item)

        self.assertEqual(2, len(started))
        self.assertEqual(server._attempt_replan, started[0][0])
        self.assertEqual("tool_failure", started[0][2]["source"])
        self.assertEqual(server._stop_repeated_failure, started[1][0])

    def test_dynamic_search_failure_stays_in_the_current_model_turn(self):
        server, run, _events = self._event_server()
        with patch.object(server, "_attempt_replan") as replan:
            server._record_failed_item(run, {
                "id": "dynamic-search-failure",
                "type": "dynamicToolCall",
                "status": "failed",
                "tool": "signalasi_parallel_web_search",
            })

        replan.assert_not_called()
        self.assertEqual({}, run.failure_counts)

    def test_outer_supervisor_can_request_a_guarded_replan(self):
        server, run, _events = self._event_server()
        with patch.object(server, "_attempt_replan", return_value=True) as replan:
            self.assertTrue(
                server.recover_stalled_task(
                    run.task_id,
                    "No meaningful external progress",
                )
            )

        replan.assert_called_once_with(
            run,
            "No meaningful external progress",
            source="task_manager_watchdog",
        )
        self.assertFalse(
            server.recover_stalled_task("missing-task", "No progress")
        )

    def test_reused_thread_moves_workspace_to_each_turn(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(codex_app_server.threading, "Thread"):
            first_workspace = Path(temporary) / "task-1"
            second_workspace = Path(temporary) / "task-2"
            first_workspace.mkdir()
            second_workspace.mkdir()
            server = codex_app_server.CodexAppServer(
                "codex",
                {},
                lambda _task, _event: None,
            )
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method == "thread/start":
                    return {"thread": {"id": "thread-1"}}
                return {"turn": {"id": f"turn-{len(calls)}"}}

            server._request = request
            first = server.start_task(
                "task-1",
                "first",
                str(first_workspace),
                conversation_id="conversation-1",
            )
            first.finished = True
            server.start_task(
                "task-2",
                "continue",
                str(second_workspace),
                conversation_id="conversation-1",
            )

            turns = [params for method, params, _ in calls if method == "turn/start"]
            self.assertEqual(str(first_workspace.resolve()), turns[0]["cwd"])
            self.assertEqual(str(second_workspace.resolve()), turns[1]["cwd"])

    def test_overlapping_tasks_are_steered_without_creating_a_branch(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(codex_app_server.threading, "Thread") as thread:
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            thread_count = 0
            calls = []

            def request(method, params, timeout):
                nonlocal thread_count
                calls.append((method, params, timeout))
                if method == "thread/start":
                    thread_count += 1
                    return {"thread": {"id": f"thread-{thread_count}"}}
                return {"turn": {"id": f"turn-{thread_count}"}}

            server._request = request
            first = server.start_task("task-1", "first", temporary, conversation_id="conversation-1")
            with self.assertRaises(codex_app_server.CodexConversationBusyError) as raised:
                server.start_task("task-2", "second", temporary, conversation_id="conversation-1")
            steered = server.steer_task(raised.exception.active_task_id, "be exact")

            self.assertIs(first, steered)
            self.assertEqual("thread-1", first.thread_id)
            self.assertEqual("thread-1", server._conversation_threads[server._conversation_key("conversation-1")])
            self.assertEqual(1, thread_count)
            self.assertEqual(1, thread.call_count)
            steer = next(params for method, params, _ in calls if method == "turn/steer")
            self.assertEqual("thread-1", steer["threadId"])
            self.assertEqual(first.turn_id, steer["expectedTurnId"])
            self.assertIn("be exact", steer["input"][0]["text"])
            self.assertNotIn(codex_app_server.CODEX_TASK_POLICY, steer["input"][0]["text"])

    def test_dynamic_search_request_is_answered_without_waiting_for_user_input(self):
        server, run, events = self._event_server()
        responses = []
        server._write_server_response = lambda request_id, result: responses.append((request_id, result))
        request = {
            "id": "dynamic-search-1",
            "method": "item/tool/call",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "callId": "call-search-1",
                "tool": codex_app_server.CODEX_DYNAMIC_SEARCH_TOOL,
                "arguments": {"query": "Zhuhai current weather"},
            },
        }
        result = {
            "success": True,
            "contentItems": [{"type": "inputText", "text": "cited evidence"}],
        }

        class ImmediateThread:
            def __init__(self, target, args=(), **_kwargs):
                self.target = target
                self.args = args

            def start(self):
                self.target(*self.args)

        with patch.object(
            codex_app_server,
            "execute_codex_dynamic_search",
            return_value=result,
        ), patch.object(codex_app_server.threading, "Thread", ImmediateThread):
            server._handle_event(request)

        self.assertEqual([("dynamic-search-1", result)], responses)
        event_payloads = [event for _task_id, event in events]
        self.assertFalse(any(event.get("status") == "waiting_input" for event in event_payloads))
        self.assertEqual("model_directed_search_completed", event_payloads[-1]["trace_stage"])
        self.assertIn("Zhuhai current weather", event_payloads[-1]["trace_detail"])

    def test_dynamic_fetch_request_reads_the_url_on_desktop(self):
        server, run, events = self._event_server()
        responses = []
        server._write_server_response = lambda request_id, result: responses.append((request_id, result))
        request = {
            "id": "dynamic-fetch-1",
            "method": "item/tool/call",
            "params": {
                "threadId": run.thread_id,
                "turnId": run.turn_id,
                "callId": "call-fetch-1",
                "tool": codex_app_server.CODEX_DYNAMIC_FETCH_TOOL,
                "arguments": {"urls": ["https://mp.weixin.qq.com/s/example"]},
            },
        }
        result = {
            "success": True,
            "contentItems": [{"type": "inputText", "text": "Desktop article evidence"}],
        }

        class ImmediateThread:
            def __init__(self, target, args=(), **_kwargs):
                self.target = target
                self.args = args

            def start(self):
                self.target(*self.args)

        with patch.object(
            codex_app_server,
            "execute_codex_dynamic_fetch",
            return_value=result,
        ) as fetch, patch.object(codex_app_server.threading, "Thread", ImmediateThread):
            server._handle_event(request)

        self.assertEqual([("dynamic-fetch-1", result)], responses)
        fetch.assert_called_once_with(
            {"urls": ["https://mp.weixin.qq.com/s/example"]},
            run.task_id,
        )
        event_payloads = [event for _task_id, event in events]
        self.assertEqual("model_directed_fetch_completed", event_payloads[-1]["trace_stage"])
        self.assertIn("https://mp.weixin.qq.com/s/example", event_payloads[-1]["trace_detail"])

    def test_missing_persisted_thread_is_recreated(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ):
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            conversation_key = server._conversation_key("conversation-1")
            server._conversation_threads[conversation_key] = "stale-thread"
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method == "thread/resume" and params["threadId"] == "stale-thread":
                    raise RuntimeError("thread not found: stale-thread")
                if method == "thread/start":
                    return {"thread": {"id": "fresh-thread"}}
                return {"turn": {"id": "fresh-turn"}}

            server._request = request
            run = server.start_task("task-1", "hello", temporary, conversation_id="conversation-1")

            self.assertEqual(run.thread_id, "fresh-thread")
            self.assertEqual(run.turn_id, "fresh-turn")
            self.assertEqual(server._conversation_threads[conversation_key], "fresh-thread")
            self.assertEqual([method for method, _, _ in calls], ["thread/resume", "thread/start", "turn/start"])

    def test_prewarm_restores_recent_threads_once_per_process(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ):
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            server._conversation_threads = {
                "v2:legacy": "thread-legacy",
                f"{codex_app_server.CONVERSATION_THREAD_VERSION}:conversation-1": "thread-1",
                f"{codex_app_server.CONVERSATION_THREAD_VERSION}:conversation-2": "thread-2",
                f"{codex_app_server.CONVERSATION_THREAD_VERSION}:conversation-3": "thread-3",
            }
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                return {"thread": {"id": params["threadId"]}}

            server._request = request
            first = server.prewarm_recent_threads(limit=2)
            second = server.prewarm_recent_threads(limit=2)

            self.assertEqual(2, first["resumed"])
            self.assertEqual(0, second["resumed"])
            self.assertEqual(
                ["thread-3", "thread-2"],
                [params["threadId"] for method, params, _ in calls if method == "thread/resume"],
            )

    def test_local_images_are_sent_as_native_app_server_input(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(codex_app_server.threading, "Thread"):
            image = Path(temporary) / "homework.jpg"
            image.write_bytes(b"image")
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method == "thread/start":
                    return {"thread": {"id": "thread-image"}}
                return {"turn": {"id": "turn-image"}}

            server._request = request
            server.start_task("task-image", "grade this", temporary, image_paths=[str(image)])

            turn = next(params for method, params, _ in calls if method == "turn/start")
            self.assertEqual("text", turn["input"][0]["type"])
            self.assertEqual("localImage", turn["input"][1]["type"])
            self.assertEqual(str(image.resolve()), turn["input"][1]["path"])
            self.assertEqual("original", turn["input"][1]["detail"])

    def test_prior_image_is_only_rebound_when_starting_a_fresh_thread(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(codex_app_server.threading, "Thread"):
            prior_image = Path(temporary) / "prior-homework.jpg"
            prior_image.write_bytes(b"image")
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method == "thread/start":
                    return {"thread": {"id": "thread-context"}}
                return {"turn": {"id": f"turn-{len(calls)}"}}

            server._request = request
            first = server.start_task(
                "task-first",
                "grade the prior image",
                temporary,
                conversation_id="conversation-first",
                fresh_thread_image_paths=[str(prior_image)],
            )
            first.finished = True
            second = server.start_task(
                "task-second",
                "continue",
                temporary,
                conversation_id="conversation-first",
                fresh_thread_image_paths=[str(prior_image)],
            )

            turns = [params for method, params, _ in calls if method == "turn/start"]
            self.assertEqual(["text", "localImage"], [item["type"] for item in turns[0]["input"]])
            self.assertEqual(["text"], [item["type"] for item in turns[1]["input"]])
            self.assertEqual(first.thread_id, second.thread_id)

    def test_recover_completed_turn_without_starting_a_duplicate_turn(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ):
            events = []
            server = codex_app_server.CodexAppServer(
                "codex",
                {},
                lambda task_id, event: events.append((task_id, event)),
            )
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append((method, params, timeout))
                if method != "thread/resume":
                    raise AssertionError(f"Unexpected recovery method: {method}")
                return {
                    "thread": {
                        "id": "thread-recovered",
                        "status": {"type": "idle"},
                        "turns": [{
                            "id": "turn-recovered",
                            "status": "completed",
                            "items": [{
                                "id": "answer",
                                "type": "agentMessage",
                                "text": "Recovered final answer",
                            }],
                        }],
                    }
                }

            server._request = request
            run = server.recover_task(
                task_id="task-recovered",
                thread_id="thread-recovered",
                turn_id="turn-recovered",
                original_prompt="continue the work",
            )

            self.assertTrue(run.finished)
            self.assertEqual("Recovered final answer", run.final_text)
            self.assertEqual(["thread/resume"], [method for method, _, _ in calls])
            self.assertEqual({"web_search": "live"}, calls[0][1]["config"])
            self.assertEqual("completed", events[-1][1]["status"])
            self.assertEqual("Recovered final answer", events[-1][1]["result"])

    def test_recover_in_progress_turn_reconnects_without_replaying_prompt(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ), patch.object(codex_app_server.threading, "Thread") as thread:
            events = []
            server = codex_app_server.CodexAppServer(
                "codex",
                {},
                lambda task_id, event: events.append((task_id, event)),
            )
            server._ensure_started = lambda: None

            def request(method, params, timeout):
                self.assertEqual("thread/resume", method)
                return {
                    "thread": {
                        "id": "thread-running",
                        "status": {"type": "active", "activeFlags": []},
                        "turns": [{
                            "id": "turn-running",
                            "status": "inProgress",
                            "items": [],
                        }],
                    }
                }

            server._request = request
            run = server.recover_task(
                task_id="task-running",
                thread_id="thread-running",
                turn_id="turn-running",
                original_prompt="\u7ee7\u7eed\u539f\u4efb\u52a1",
                elapsed_seconds=42,
            )

            self.assertFalse(run.finished)
            self.assertEqual("turn-running", run.turn_id)
            self.assertEqual("task-running", server._turn_tasks["turn-running"])
            self.assertGreaterEqual(time.monotonic() - run.started_monotonic, 41)
            self.assertEqual("running", events[-1][1]["status"])
            self.assertEqual("Reconnected to Codex turn", events[-1][1]["current_step"])
            thread.assert_called_once()

    def test_missing_original_turn_fails_without_replaying_prompt(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            codex_app_server,
            "CONVERSATION_THREADS_PATH",
            Path(temporary) / "threads.json",
        ):
            server = codex_app_server.CodexAppServer("codex", {}, lambda _task, _event: None)
            server._ensure_started = lambda: None
            calls = []

            def request(method, params, timeout):
                calls.append(method)
                return {
                    "thread": {
                        "id": "thread-missing",
                        "status": {"type": "idle"},
                        "turns": [{
                            "id": "different-turn",
                            "status": "completed",
                            "items": [],
                        }],
                    }
                }

            server._request = request
            with self.assertRaisesRegex(RuntimeError, "original Codex turn"):
                server.recover_task(
                    task_id="task-missing",
                    thread_id="thread-missing",
                    turn_id="turn-missing",
                    original_prompt="do not replay this",
                )

            self.assertEqual(["thread/resume"], calls)


if __name__ == "__main__":
    unittest.main()
