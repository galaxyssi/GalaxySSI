from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from evolution_v2.agent_adapters import default_evolution_patch_agent
from evolution_v2.legacy import EvolutionError
from evolution_v2.local_implementation import implement_locally, implementation_observer
from evolution_v2.local_planning import LocalPlannerUnavailable
from evolution_v2.local_workspace_tools import WorkspaceTools
from evolution_v2.manager import EvolutionManager


class LocalImplementationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "src").mkdir()
        (self.root / "src/a.py").write_bytes(b"answer = 1\n")
        self.tools = WorkspaceTools(self.root, ["src"])

    def test_read_modify_observe_finish_real_files(self):
        actions = iter([
            {"operation": "read", "path": "src/a.py"},
            {"operation": "write", "path": "src/a.py", "text": "answer = 2\n",
             "expected_sha256": hashlib.sha256(b"answer = 1\n").hexdigest()},
            {"operation": "read", "path": "src/a.py"},
            {"operation": "finish", "summary": "Changed answer; host checks pending"}])
        seen, events = [], []
        def infer(messages):
            seen.append(messages)
            return json.dumps(next(actions))
        with implementation_observer(threading.Event(), lambda event, **data: events.append((event, data))):
            summary = implement_locally("Update source", self.root, scope=["src"], infer=infer)
        self.assertIn("host checks pending", summary)
        self.assertEqual("answer = 2\n", (self.root / "src/a.py").read_text())
        self.assertEqual(3, len(events))
        self.assertIn("answer = 2", seen[-1][-1]["content"])
        self.assertNotIn("text", str(events))

    def test_tool_failure_and_invalid_json_return_observations(self):
        responses = iter(["not json", '["bad"]', '{"operation":"read","path":"missing"}',
                          '{"operation":"finish","summary":"Needs source location"}'])
        seen = []
        def infer(messages):
            seen.append(messages)
            return next(responses)
        implement_locally("Inspect", self.root, infer=infer)
        for messages in seen[1:]:
            self.assertFalse(json.loads(messages[-1]["content"])["observation"]["ok"])
        self.assertEqual("model_action_parse", json.loads(seen[1][-1]["content"])["observation"]["stage"])
        self.assertEqual("file_tool_execution", json.loads(seen[3][-1]["content"])["observation"]["stage"])

    def test_no_aggregate_action_budget_and_bounded_context(self):
        count = 0
        def infer(messages):
            nonlocal count
            count += 1
            self.assertLessEqual(len(messages), 10)
            return json.dumps({"operation": "read", "path": "src/a.py"} if count <= 80 else
                              {"operation": "finish", "summary": "Observed"})
        self.assertEqual("Observed", implement_locally("Inspect", self.root, infer=infer))
        self.assertEqual(81, count)

    def test_cancel_after_model_response_prevents_write(self):
        cancellation = threading.Event()
        def infer(messages):
            cancellation.set()
            return json.dumps({"operation": "write", "path": "src/new", "text": "bad", "expected_sha256": None})
        with implementation_observer(cancellation, lambda *a, **k: None), self.assertRaises(EvolutionError) as caught:
            implement_locally("Edit", self.root, scope=["src"], infer=infer)
        self.assertEqual("cancelled", caught.exception.code)
        self.assertFalse((self.root / "src/new").exists())

    def test_cancel_before_inference(self):
        cancellation = threading.Event()
        cancellation.set()
        with implementation_observer(cancellation, lambda *a, **k: None), self.assertRaises(EvolutionError):
            implement_locally("Edit", self.root, infer=lambda _: self.fail("inference after cancel"))

    def test_model_unavailable_does_not_call_cloud(self):
        with patch("evolution_v2.local_implementation.infer_local_plan", side_effect=LocalPlannerUnavailable("offline")), self.assertRaises(LocalPlannerUnavailable):
            implement_locally("Private goal", self.root)

    def test_scope_path_links_and_stale_write(self):
        for path in ("../outside", "/absolute", "C:/outside", ".git/config", ".GIT/config", "src/../../x", "src\\x"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.tools.execute({"operation": "read", "path": path})
        for tool, path, digest in ((self.tools, "other/file", None),
                                  (WorkspaceTools(self.root), "src/a.py", None),
                                  (self.tools, "src/a.py", "stale")):
            with self.assertRaises(ValueError):
                tool.execute({"operation": "write", "path": path, "text": "bad", "expected_sha256": digest})
        os.link(self.root / "src/a.py", self.root / "shared")
        with self.assertRaises(ValueError):
            self.tools.execute({"operation": "read", "path": "src/a.py"})

    def test_create_atomic_text_and_no_temporary_file(self):
        self.tools.execute({"operation": "write", "path": "src/new/file.txt", "text": "new", "expected_sha256": None})
        self.assertEqual(["file.txt"], [p.name for p in (self.root / "src/new").iterdir()])
        self.assertEqual("new", (self.root / "src/new/file.txt").read_text())

    def test_directory_and_text_pagination(self):
        for index in range(130):
            (self.root / "src" / f"file-{index:03d}").touch()
        names, after = [], ""
        while True:
            result = self.tools.execute({"operation": "list", "path": "src", "after": after})
            names.extend(result["entries"])
            after = result["next_after"]
            if after is None:
                break
        self.assertEqual(131, len(names))
        self.assertEqual(sorted(set(names)), names)
        text = "a" * 40_000
        (self.root / "src/a.py").write_text(text)
        parts, offset = [], 0
        while True:
            page = self.tools.execute({"operation": "read", "path": "src/a.py", "offset": offset})
            parts.append(page["text"])
            offset = page["next_offset"]
            if offset is None:
                break
        self.assertEqual(text, "".join(parts))

    def test_auto_selection_never_calls_external_cli_discovery(self):
        manager = object.__new__(EvolutionManager)
        manager.patch_agent = default_evolution_patch_agent
        for agent in ("auto", "local-llm"):
            with patch("evolution_v2.local_planning.local_plan_endpoint", return_value=None), patch("agent_gateway.select_evolution_agent") as external:
                self.assertEqual("local-llm", manager._select_implementation_agent(SimpleNamespace(agent_id=agent)))
                external.assert_not_called()
        with patch("evolution_v2.local_planning.local_plan_endpoint", side_effect=LocalPlannerUnavailable("configure local")), self.assertRaises(EvolutionError) as caught:
            manager._select_implementation_agent(SimpleNamespace(agent_id="auto"))
        self.assertEqual("agent_unavailable", caught.exception.code)

    def test_review_gateway_is_read_only_local(self):
        from agent_gateway import ask_evolution_agent
        (self.root / ".git").write_text("gitdir: fixture")
        with patch("evolution_v2.local_implementation.implement_locally", return_value="review") as infer:
            self.assertEqual("review", ask_evolution_agent("local-llm", "review", task_id="t", working_directory=self.root))
        self.assertNotIn("scope", infer.call_args.kwargs)

    def test_auto_preflight_does_not_advertise_cloud_fallback(self):
        from agent_gateway import evolution_agent_candidates
        with patch("evolution_v2.local_planning.local_plan_endpoint", side_effect=LocalPlannerUnavailable("missing")), patch("agent_gateway.all_agent_specs") as specs:
            result = evolution_agent_candidates("auto")
        self.assertEqual("", result["selected_agent_id"])
        self.assertEqual(["local-llm"], [row["id"] for row in result["agents"]])
        specs.assert_not_called()

    def test_write_preserves_mode_and_rejects_git_alias(self):
        import stat
        path = self.root / "src/a.py"
        path.chmod(0o755)
        previous = stat.S_IMODE(path.stat().st_mode)
        digest = self.tools.execute({"operation": "read", "path": "src/a.py"})["sha256"]
        self.tools.execute({"operation": "write", "path": "src/a.py", "expected_sha256": digest, "text": "changed"})
        self.assertEqual(previous, stat.S_IMODE(path.stat().st_mode))
        with self.assertRaises(ValueError):
            self.tools.execute({"operation": "read", "path": ".git./config"})


if __name__ == "__main__":
    unittest.main()
