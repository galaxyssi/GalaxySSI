import copy
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from collaboration_text_artifact import FORMAT, TOOL, execute, tool_spec
from codex_app_server import CodexAppServer, CodexRun


class TextArtifactTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.author = self.root / "author"
        self.peer = self.root / "peer"
        (self.author / "outputs").mkdir(parents=True)
        self.peer.mkdir()
        self.raw = b"\xef\xbb\xbf# exact UTF-8\r\ndef predict(x):\r\n    return x * 2\r\n" + "# \u4e2d\u6587 \U0001f52c\n".encode()
        self.source = self.author / "outputs" / "candidate.py"
        self.source.write_bytes(self.raw)
        self.sent = []
        self.reads = []
        self.saved = None
        self.arguments = {"mode": "publish", "path": "outputs/candidate.py", "milestone_id": "candidate-v1", "title": "Candidate v1"}

    def publish(self, request):
        self.sent.append(copy.deepcopy(request))
        if request["mode"] == "receipt":
            return {**request, "success": True, "status": "recorded", "revisions": [
                {key: self.saved[key] for key in ("object_id", "revision", "sha256")}]}
        value = json.loads(request["artifact"])["workspace"][0]
        self.saved = {"object_id": "a" * 64, "revision": 1, "sha256": "b" * 64,
                      "kind": value["kind"], "body": value["body"], "host_observations": [],
                      "evidence_state": "member_reported_not_verified"}
        return {"success": True, "status": "recorded", "revisions": [
            {key: self.saved[key] for key in ("object_id", "revision", "sha256")}]}

    def recall(self, request):
        self.reads.append(dict(request))
        encoded = json.dumps(self.saved, ensure_ascii=False, separators=(",", ":")).encode("utf-16-le")
        offset = request["offset"]
        total = len(encoded) // 2
        end = min(offset + 37, total)
        return {"success": True, "content": encoded[offset * 2:end * 2].decode("utf-16-le", errors="surrogatepass"),
                "total_characters": total, "next_offset": end if end < total else None}

    def call(self, arguments=None, *, root=None, publish=None, recall=None, active=lambda: True):
        return execute("task", str(root or self.author), arguments or self.arguments,
                       publish=publish or self.publish, recall=recall or self.recall, active=active)

    def materialize(self, **kwargs):
        return self.call({"mode": "materialize", "object_id": "a" * 64, "revision": 1, "sha256": "b" * 64},
                         root=self.peer, **kwargs)

    def test_coordination_is_frozen_with_exact_source_and_retry_identity(self):
        args = {**self.arguments, "coordination": {"mode": "record_only"}}
        self.call(args)
        self.assertEqual(args["coordination"], json.loads(self.sent[0]["artifact"])["coordination"])
        self.source.write_bytes(b"changed")
        self.call(args)
        self.assertEqual("receipt", self.sent[-1]["mode"])
        with self.assertRaisesRegex(ValueError, "different snapshot"):
            self.call({**args, "coordination": {"mode": "request", "decision": "Compare methods", "why_now": "Conflicting measurements"}})
        requested = {**args, "milestone_id": "decision-v2", "coordination": {
            "mode": "request", "decision": "Compare methods", "why_now": "Conflicting measurements"}}
        self.call(requested)
        self.assertEqual(requested["coordination"], json.loads(self.sent[-1]["artifact"])["coordination"])

    def test_malformed_coordination_is_rejected_before_saving_or_sending(self):
        for bad in (None, [], {"mode": []}, {"mode": "request"}, {"mode": "record_only", "decision": "x"},
                    {"mode": "request", "decision": " ", "why_now": "x"},
                    {"mode": "request", "decision": "x", "why_now": False}):
            with self.subTest(value=bad), self.assertRaisesRegex(ValueError, "coordination"):
                self.call({**self.arguments, "coordination": bad})
        self.assertEqual([], self.sent)
        self.assertFalse((self.author / ".collaboration-text-artifacts").exists())
        self.assertIn("coordination", tool_spec()["inputSchema"]["properties"])

    def test_exact_source_survives_complete_paging_and_independent_task_import(self):
        sent = self.call()
        result = self.materialize()
        self.assertEqual(self.raw, Path(result["path"]).read_bytes())
        self.assertEqual(hashlib.sha256(self.raw).hexdigest(), sent["file_sha256"])
        self.assertEqual(sent["file_sha256"], result["file_sha256"])
        self.assertEqual("candidate.py", result["name"])
        self.assertGreater(len(self.reads), 2)
        self.assertTrue(Path(result["path"]).is_relative_to(self.peer / "downloads" / "context"))
        self.assertFalse(result["executed"])
        self.assertFalse(result["verified_claim"])
        self.assertEqual(self.raw, self.source.read_bytes())

    def test_materialized_identity_does_not_double_hash_directories(self):
        self.call()
        result = self.materialize()
        relative = Path(result["relative_path"])
        self.assertEqual(4, len(relative.parts))
        self.assertEqual(64, len(relative.stem))
        self.assertEqual(".py", relative.suffix)

    def test_durable_retry_keeps_snapshot_after_source_changes_or_disappears(self):
        def uncertain(request):
            self.publish(request)
            raise TimeoutError("reply lost")
        with self.assertRaises(TimeoutError):
            self.call(publish=uncertain)
        self.source.write_bytes(b"different")
        self.call()
        self.source.unlink()
        self.call()
        self.assertEqual(["publish", "receipt", "receipt"], [r["mode"] for r in self.sent])
        self.assertEqual(hashlib.sha256(self.sent[0]["artifact"].encode()).hexdigest(), self.sent[1]["artifact_sha256"])
        self.assertEqual(self.sent[1], self.sent[2])
        with self.assertRaisesRegex(ValueError, "different snapshot"):
            self.call({**self.arguments, "title": "changed"})

    def test_substantive_revision_uses_new_id_and_exact_base(self):
        self.call()
        self.source.write_bytes(b"revision 2\n")
        self.call({**self.arguments, "milestone_id": "candidate-v2", "object_id": "a" * 64, "base_revision": 1,
                   "observations": [{"evidence_id": "c" * 64, "sha256": "d" * 64}]})
        value = json.loads(self.sent[-1]["artifact"])["workspace"][0]
        self.assertEqual(1, value["base_revision"])
        self.assertEqual("a" * 64, value["object_id"])
        self.assertEqual("revision 2\n", value["body"]["content"])
        self.assertEqual("c" * 64, value["observations"][0]["evidence_id"])

    def test_repeated_materialization_reauthorizes_and_never_overwrites_modifications(self):
        self.call()
        result = self.materialize()
        self.reads.clear()
        self.materialize()
        self.assertTrue(self.reads)
        target = Path(result["path"])
        target.write_bytes(b"peer edited")
        with self.assertRaisesRegex(ValueError, "will not be overwritten"):
            self.materialize()
        self.assertEqual(b"peer edited", target.read_bytes())

    def test_missing_or_revoked_permission_never_creates_file(self):
        result = self.materialize(recall=lambda _: {"success": False, "reason": "object_unavailable"})
        self.assertFalse(result["success"])
        self.assertEqual([], list(self.peer.iterdir()))

    def test_cancel_before_write_never_creates_file(self):
        self.call()
        active = [True]
        def recall(request):
            result = self.recall(request)
            if result["next_offset"] is None:
                active[0] = False
            return result
        with self.assertRaisesRegex(ValueError, "assignment changed"):
            self.materialize(recall=recall, active=lambda: active[0])
        self.assertEqual([], list(self.peer.iterdir()))

    def test_wrong_hash_size_name_or_identity_never_materializes(self):
        self.call()
        original = copy.deepcopy(self.saved)
        cases = [(None, "object_id", "c" * 64), (None, "revision", True), (None, "sha256", "c" * 64),
                 (None, "kind", "evidence"), ("body", "format", "other"), ("body", "size_bytes", len(self.raw) + 1),
                 ("body", "sha256", "e" * 64), ("body", "encoding", "utf-16"), ("body", "content", "modified"),
                 ("body", "name", "../escape.py"), ("body", "name", "CON.py"), ("body", "name", "file.py:secret"),
                 ("body", "name", "file.py."), ("body", "name", "\\\\server\\share")]
        for scope, key, value in cases:
            with self.subTest(scope=scope, key=key, value=value):
                self.saved = copy.deepcopy(original)
                (self.saved[scope] if scope else self.saved)[key] = value
                with self.assertRaises(ValueError):
                    self.materialize()
                self.assertEqual([], list(self.peer.iterdir()))

    def test_page_gap_loop_changed_total_or_oversize_never_materializes(self):
        self.call()
        for update in ({"next_offset": 0}, {"next_offset": None}, {"content": ""},
                       {"total_characters": 999999}, {"total_characters": True}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                self.materialize(recall=lambda request: {**self.recall(request), **update})
        def change(request):
            result = self.recall(request)
            if request["offset"]:
                result["total_characters"] += 1
            return result
        with self.assertRaises(ValueError):
            self.materialize(recall=change)
        self.assertEqual([], list(self.peer.iterdir()))

    def test_utf16_split_surrogate_is_reassembled_before_json_decode(self):
        self.call()
        encoded = json.dumps(self.saved, ensure_ascii=False).encode("utf-16-le")
        position = encoded.index("\U0001f52c".encode("utf-16-le")) // 2 + 1
        def split(request):
            offset = request["offset"]
            end = position if offset == 0 else len(encoded) // 2
            return {"success": True, "content": encoded[offset * 2:end * 2].decode("utf-16-le", errors="surrogatepass"),
                    "total_characters": len(encoded) // 2, "next_offset": end if offset == 0 else None}
        result = self.materialize(recall=split)
        self.assertEqual(self.raw, Path(result["path"]).read_bytes())

    def test_invalid_arguments_and_authority_fields_never_publish(self):
        bad = [None, [], {}, {"mode": "read"}]
        bad += [{**self.arguments, key: value} for key, value in [
            ("path", "../secret"), ("path", "outputs/../secret"), ("path", "outputs\\candidate.py"),
            ("path", "outputs/candidate.py:secret"), ("path", str(self.source)), ("path", "outputs//candidate.py"),
            ("title", ""), ("milestone_id", ""), ("member_id", "other"), ("destination", "elsewhere"),
            ("base_revision", 1), ("observations", [{"evidence_id": "fake", "sha256": "b" * 64}])]]
        for arguments in bad:
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                execute("task", str(self.author), arguments, publish=self.publish, recall=self.recall, active=lambda: True)
        self.assertEqual([], self.sent)

    def test_binary_and_encoded_envelope_overflow_are_not_truncated(self):
        for raw in (b"\xff", b"a\x00b", b"x" * 131073, b'"' * 50000):
            self.source.write_bytes(raw)
            with self.subTest(size=len(raw)), self.assertRaises(ValueError):
                self.call()
        self.assertEqual([], self.sent)

    def test_source_symlink_is_rejected(self):
        external = self.root / "secret.py"
        external.write_bytes(b"secret")
        self.source.unlink()
        try:
            self.source.symlink_to(external)
        except OSError as exc:
            self.skipTest(f"symlink not available: {exc}")
        with self.assertRaisesRegex(ValueError, "link"):
            self.call()
        self.assertEqual([], self.sent)

    def test_corrupted_retry_snapshot_is_not_replaced(self):
        self.call()
        path = next((self.author / ".collaboration-text-artifacts").glob("*.json"))
        value = json.loads(path.read_text(encoding="utf-8"))
        value["request"]["artifact"] += " "
        path.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "integrity"):
            self.call()

    def test_windows_reparse_point_is_rejected_even_without_symlink_privilege(self):
        original = Path.lstat
        def reparse(path):
            info = original(path)
            if path == self.author / "outputs":
                return SimpleNamespace(st_mode=info.st_mode, st_file_attributes=0x400)
            return info
        with patch.object(Path, "lstat", reparse), self.assertRaisesRegex(ValueError, "reparse point"):
            self.call()
        self.assertEqual([], self.sent)

    def test_dynamic_tool_registration_requires_both_bridges(self):
        server = CodexAppServer("codex", {}, lambda *_: None, collaboration_publish=lambda *_: {})
        self.assertNotIn(TOOL, [tool["name"] for tool in server._dynamic_tools])
        server = CodexAppServer("codex", {}, lambda *_: None,
                               collaboration_publish=lambda *_: {}, collaboration_recall=lambda *_: {})
        self.assertIn(tool_spec(), server._dynamic_tools)

    def test_dynamic_tool_uses_current_task_and_preserves_unverified_progress(self):
        events = []
        def publish(task_id, arguments, active):
            self.assertEqual("task", task_id)
            self.assertTrue(active())
            return self.publish(arguments)
        server = CodexAppServer("codex", {}, lambda *event: events.append(event),
            collaboration_publish=publish, collaboration_recall=lambda *_: {})
        run = CodexRun("task", thread_id="thread", turn_id="turn", working_directory=str(self.author), sandbox="workspace-write")
        server._runs["task"] = run
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": TOOL, "arguments": self.arguments}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual("collaboration_text_artifact_returned", events[-1][1]["trace_stage"])
        self.assertFalse(run.finished)
        self.assertFalse(run.research_observed)

    def test_read_only_and_stale_dynamic_invocations_cannot_write_or_publish(self):
        server = CodexAppServer("codex", {}, lambda *_: None,
            collaboration_publish=lambda _, request, active: self.publish(request), collaboration_recall=lambda *_: {})
        run = CodexRun("task", thread_id="thread", turn_id="turn", working_directory=str(self.author))
        server._runs["task"] = run
        for sandbox, common in (("read-only", {}), ("workspace-write", {"turn_id": "stale"})):
            run.sandbox = sandbox
            with patch.object(server, "_write_server_response") as reply:
                server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": TOOL, "arguments": self.arguments}, common)
            self.assertFalse(reply.call_args.args[1]["success"])
        self.assertEqual([], self.sent)
        self.assertFalse((self.author / ".collaboration-text-artifacts").exists())


if __name__ == "__main__":
    unittest.main()
