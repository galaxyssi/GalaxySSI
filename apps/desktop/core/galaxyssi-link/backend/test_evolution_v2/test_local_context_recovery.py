import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from evolution_v2.local_implementation import implement_locally, implementation_observer
from evolution_v2.local_planning import LocalPlannerContextExceeded, LocalPlannerUnavailable, infer_local_plan, response_error


class Response(io.BytesIO):
    status = 400


class LocalContextRecoveryTests(unittest.TestCase):
    def test_typed_provider_errors_are_distinguished_from_generic_http_failures(self):
        for details in ({"type": "exceed_context_size_error", "n_prompt_tokens": 8982, "n_ctx": 8192},
                        {"code": "context_length_exceeded"}):
            error = response_error(Response(json.dumps({"error": details}).encode()))
            self.assertIsInstance(error, LocalPlannerContextExceeded)
            self.assertNotIn("private", str(error))
        for details in ({"message": "context length exceeded"}, {"type": "schema_error"}, "context_length_exceeded"):
            error = response_error(Response(json.dumps({"error": details}).encode()))
            self.assertIs(type(error), LocalPlannerUnavailable)

    def test_invalid_or_large_error_payload_is_not_a_context_signal(self):
        for body in (b"not json", b"[]", b" " * 65537 + b'{"error":{"code":"context_length_exceeded"}}'):
            self.assertIs(type(response_error(Response(body))), LocalPlannerUnavailable)

    def test_error_metadata_is_optional_numeric_and_never_echoes_server_text(self):
        error = response_error(Response(json.dumps({"error": {"type": "exceed_context_size_error",
            "n_prompt_tokens": "private-input", "n_ctx": True, "message": "private-input"}}).encode()))
        self.assertIsNone(error.requested_tokens)
        self.assertIsNone(error.context_tokens)
        self.assertNotIn("private-input", str(error))

    def test_actual_inference_path_exposes_typed_error_and_closes_connection(self):
        response = Response(b'{"error":{"type":"exceed_context_size_error","n_ctx":8192}}')
        with patch("http.client.HTTPConnection") as connection:
            connection.return_value.getresponse.return_value = response
            with self.assertRaises(LocalPlannerContextExceeded):
                infer_local_plan([], config={"url": "http://127.0.0.1:1234/v1/chat/completions", "model": "local"})
            connection.return_value.close.assert_called_once()

    def test_compaction_preserves_goal_latest_observation_and_does_not_repeat_write(self):
        events, calls = [], []
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "file.txt").write_text("before")
            def infer(messages):
                calls.append(messages)
                if len(calls) == 1:
                    return '{"operation":"read","path":"file.txt"}'
                if len(calls) == 2:
                    revision = json.loads(messages[-1]["content"])["observation"]["result"]["read_revision"]
                    return json.dumps({"operation": "append", "path": "file.txt", "text": "after", "expected_revision": revision})
                if len(calls) == 3:
                    raise LocalPlannerContextExceeded(9000, 8192)
                self.assertEqual("private-original-goal", messages[1]["content"])
                self.assertEqual(calls[2][-1], messages[-1])
                self.assertEqual(4, len(messages))
                return '{"operation":"finish","summary":"done"}'
            with implementation_observer(threading.Event(), lambda name, **data: events.append((name, data))):
                self.assertEqual("done", implement_locally("private-original-goal", root, scope=["file.txt"], infer=infer))
            self.assertEqual("beforeafter", (root / "file.txt").read_text())
        self.assertEqual(1, sum(data.get("operation") == "append" for _, data in events))
        self.assertEqual(1, sum(name == "local_context_compacted" for name, _ in events))
        self.assertNotIn("private-original-goal", str(events))

    def test_goal_or_single_observation_that_cannot_fit_is_not_discarded(self):
        count = 0
        def infer(messages):
            nonlocal count
            count += 1
            if count == 1:
                return '{"operation":"list","path":"."}'
            raise LocalPlannerContextExceeded()
        with tempfile.TemporaryDirectory() as folder, self.assertRaises(LocalPlannerContextExceeded):
            implement_locally("large-original-goal", Path(folder), infer=infer)
        self.assertEqual(2, count)

    def test_other_provider_errors_do_not_trigger_retries_or_goal_changes(self):
        with tempfile.TemporaryDirectory() as folder, patch(
                "evolution_v2.local_implementation.infer_local_plan", side_effect=LocalPlannerUnavailable("HTTP 400")) as infer:
            with self.assertRaises(LocalPlannerUnavailable):
                implement_locally("goal", Path(folder))
            infer.assert_called_once()

    def test_repeated_context_rejection_stops_before_discarding_latest_observation(self):
        calls = []
        def infer(messages):
            calls.append(messages)
            if len(calls) <= 3:
                return '{"operation":"list","path":"."}'
            raise LocalPlannerContextExceeded()
        with tempfile.TemporaryDirectory() as folder, self.assertRaises(LocalPlannerContextExceeded):
            implement_locally("original-goal", Path(folder), infer=infer)
        self.assertEqual([8, 6, 4], [len(messages) for messages in calls[3:]])
        self.assertTrue(all(messages[1]["content"] == "original-goal" for messages in calls))
        self.assertEqual(calls[3][-1], calls[-1][-1])

    def test_cancellation_during_context_rejection_does_not_restart_inference(self):
        from evolution_v2.legacy import EvolutionError
        cancellation, calls = threading.Event(), []
        def infer(messages):
            calls.append(messages)
            if len(calls) <= 2:
                return '{"operation":"list","path":"."}'
            cancellation.set()
            raise LocalPlannerContextExceeded()
        with tempfile.TemporaryDirectory() as folder, implementation_observer(cancellation, lambda *args, **kwargs: None):
            with self.assertRaises(EvolutionError):
                implement_locally("goal", Path(folder), infer=infer)
        self.assertEqual(3, len(calls))


if __name__ == "__main__":
    unittest.main()
