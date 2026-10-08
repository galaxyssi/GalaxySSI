import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from collaboration_file_artifact import TOOL, authenticated_scope, execute, tool_spec
from codex_app_server import CodexAppServer, CodexRun


class FileArtifactTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.author, self.peer, self.store = (self.root / name for name in ("author", "peer", "store"))
        (self.author / "outputs").mkdir(parents=True)
        self.peer.mkdir()
        self.source = self.author / "outputs" / "data.bin"
        self.raw = bytes(range(256)) * 8192
        self.source.write_bytes(self.raw)
        self.args = {"mode": "publish", "path": "outputs/data.bin", "milestone_id": "complete-v1", "title": "Full evidence"}
        self.scope = {"desktop_id": "desktop", "client_route_id": "route", "contact_id": "contact",
                      "peer_fingerprint": "phone-key", "local_fingerprint": "desktop-key",
                      "conversation_id": "conversation", "turn_id": "turn", "source_message_id": "source", "agent_id": "codex",
                      "task_id": "author-task", "execution_generation": 1}
        self.sent, self.reads, self.saved = [], [], None

    def publish(self, request):
        self.sent.append(copy.deepcopy(request))
        item = json.loads(request["artifact"])["workspace"][0]
        self.saved = {"object_id": item.get("object_id", "a" * 64), "revision": item.get("base_revision", 0) + 1,
                      "sha256": hashlib.sha256(request["artifact"].encode()).hexdigest(), "kind": "artifact", "body": item["body"]}
        return {"success": True, "status": "recorded", "revisions": [
            {key: self.saved[key] for key in ("object_id", "revision", "sha256")}]}

    def recall(self, request):
        self.reads.append(request)
        raw = json.dumps(self.saved, ensure_ascii=False).encode("utf-16-le")
        offset, total = request["offset"], len(raw) // 2
        end = min(total, offset + 79)
        return {"success": True, "content": raw[offset * 2:end * 2].decode("utf-16-le", errors="surrogatepass"),
                "total_characters": total, "next_offset": end if end < total else None}

    def call(self, args=None, *, root=None, scope=None, publish=None, recall=None, active=lambda: True):
        return execute(self.store, str(root or self.author), scope or self.scope, args or self.args,
                       publish=publish or self.publish, recall=recall or self.recall, active=active)

    def materialize(self, **kwargs):
        args = {"mode": "materialize", **{key: self.saved[key] for key in ("object_id", "revision", "sha256")}}
        return self.call(args, root=self.peer, scope=kwargs.pop("scope", {**self.scope, "task_id": "peer-task"}), **kwargs)

    def test_large_binary_file_has_small_control_receipt_and_exact_peer_copy(self):
        published = self.call()
        self.assertLess(len(json.dumps(self.sent[0]).encode()), 2048)
        self.assertNotIn("content", self.saved["body"])
        result = self.materialize()
        self.assertEqual(self.raw, Path(result["path"]).read_bytes())
        self.assertEqual(published["file_sha256"], result["file_sha256"])
        self.assertEqual(len(self.raw), result["size_bytes"])
        self.assertEqual("originating_desktop", result["availability"])
        self.assertFalse(result["executed"])
        self.assertFalse(result["verified_claim"])
        self.assertTrue(Path(result["path"]).is_relative_to(self.peer / "downloads" / "context"))
        self.assertEqual([], list(self.peer.glob("outputs/*")))

    def test_uncertain_publication_is_retried_from_snapshot_not_modified_source(self):
        def uncertain(request):
            self.publish(request)
            raise TimeoutError("response lost")
        with self.assertRaises(TimeoutError):
            self.call(publish=uncertain)
        with self.assertRaisesRegex(ValueError, "not confirmed"):
            self.materialize()
        self.source.write_bytes(b"different candidate")
        self.call()
        self.source.unlink()
        self.call()
        self.assertEqual(self.sent[0], self.sent[1])
        self.assertEqual(self.sent[0], self.sent[2])
        self.assertEqual(self.raw, Path(self.materialize()["path"]).read_bytes())
        with self.assertRaisesRegex(ValueError, "different snapshot"):
            self.call({**self.args, "title": "Different"})

    def test_process_restart_and_deleted_producer_workspace_preserve_receipted_file(self):
        self.call()
        self.source.unlink()
        record = self.root / "test-input.json"
        record.write_text(json.dumps({"store": str(self.store), "root": str(self.peer),
            "scope": {**self.scope, "task_id": "peer-task"}, "saved": self.saved}), encoding="utf-8")
        code = """import json,sys
from collaboration_file_artifact import execute
v=json.load(open(sys.argv[1],encoding='utf-8')); s=v['saved']
def recall(a):
    text=json.dumps(s); return {'success':True,'content':text,'total_characters':len(text),'next_offset':None}
r=execute(v['store'],v['root'],v['scope'],{'mode':'materialize',**{k:s[k] for k in ('object_id','revision','sha256')}},publish=lambda a:None,recall=recall,active=lambda:True)
print(json.dumps(r))
"""
        result = subprocess.run([sys.executable, "-c", code, str(record)], cwd=Path(__file__).parent,
                                check=True, capture_output=True, text=True)
        self.assertEqual(self.raw, Path(json.loads(result.stdout)["path"]).read_bytes())

    def test_new_revision_retains_original_bytes_and_exact_version_bindings(self):
        self.call()
        old = copy.deepcopy(self.saved)
        self.source.write_bytes(b"version two")
        self.call({**self.args, "milestone_id": "v2", "object_id": old["object_id"], "base_revision": 1})
        self.assertEqual(b"version two", Path(self.materialize()["path"]).read_bytes())
        self.saved = old
        self.assertEqual(self.raw, Path(self.materialize()["path"]).read_bytes())

    def test_every_materialization_reauthorizes_and_revocation_blocks_cached_file(self):
        self.call()
        first = self.materialize()
        self.reads.clear()
        self.materialize()
        self.assertTrue(self.reads)
        failed = self.materialize(recall=lambda _: {"success": False, "reason": "revoked"})
        self.assertFalse(failed["success"])
        self.assertNotIn("path", failed)
        self.assertEqual(self.raw, Path(first["path"]).read_bytes())

    def test_other_phone_repaired_identity_or_desktop_cannot_read_copy(self):
        self.call()
        for key in ("client_route_id", "desktop_id", "contact_id", "peer_fingerprint", "local_fingerprint"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "not available"):
                self.materialize(scope={**self.scope, key: "another"})
        self.assertEqual([], list(self.peer.iterdir()))

    def test_copying_a_descriptor_into_another_workspace_object_does_not_grant_access(self):
        self.call()
        self.saved["object_id"] = "c" * 64
        with self.assertRaisesRegex(ValueError, "not confirmed"):
            self.materialize()
        self.assertEqual([], list(self.peer.iterdir()))

    def test_corrupt_descriptor_blob_and_checkpoint_do_not_produce_file(self):
        self.call()
        original = copy.deepcopy(self.saved)
        self.saved["body"]["size_bytes"] += 1
        with self.assertRaisesRegex(ValueError, "immutable"):
            self.materialize()
        self.saved = original
        blob = next(self.store.rglob("*.bin"))
        blob.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "hash or size"):
            self.materialize()
        self.assertEqual([], list(self.peer.rglob("*.bin")))
        with self.assertRaisesRegex(ValueError, "missing or has changed"):
            self.call()
        record = next(self.store.rglob("*.json"))
        record.write_text(record.read_text().replace("Full evidence", "Altered title"))
        with self.assertRaisesRegex(ValueError, "checkpoint integrity"):
            self.call()

    def test_peer_modifications_are_not_overwritten(self):
        self.call()
        path = Path(self.materialize()["path"])
        path.write_bytes(b"peer changes")
        with self.assertRaisesRegex(ValueError, "not be overwritten"):
            self.materialize()
        self.assertEqual(b"peer changes", path.read_bytes())

    def test_cancel_during_copy_discards_temporary_output(self):
        self.call()
        current = [True]
        def recall(args):
            result = self.recall(args)
            if result["next_offset"] is None:
                current[0] = False
            return result
        with self.assertRaisesRegex(ValueError, "assignment changed"):
            self.materialize(recall=recall, active=lambda: current[0])
        self.assertFalse(any(p.is_file() for p in self.peer.rglob("*")))

    def test_source_paths_authority_fields_and_reparse_points_are_rejected(self):
        for change in ({"path": "../other"}, {"path": str(self.source)}, {"task_id": "other"},
                       {"path": "outputs/../secret"}, {"destination": "elsewhere"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.call({**self.args, **change})
        original = Path.lstat
        def reparse(path):
            value = original(path)
            return SimpleNamespace(st_mode=value.st_mode, st_file_attributes=0x400) if path == self.source else value
        with patch.object(Path, "lstat", reparse), self.assertRaisesRegex(ValueError, "reparse"):
            self.call()
        self.assertEqual([], self.sent)

    def test_file_size_limit_and_source_mutation_are_checked(self):
        with patch("collaboration_file_artifact.MAX_FILE_BYTES", 1024), self.assertRaisesRegex(ValueError, "file limit"):
            self.call()
        original = __import__("os").fstat
        calls = [0]
        def changed(fd):
            value = original(fd)
            calls[0] += 1
            return SimpleNamespace(st_mode=value.st_mode, st_size=value.st_size, st_ino=value.st_ino,
                                   st_mtime_ns=value.st_mtime_ns + calls[0])
        with patch("collaboration_file_artifact.os.fstat", changed), self.assertRaisesRegex(ValueError, "source changed"):
            self.call()
        self.assertEqual([], self.sent)

    def test_authentication_requires_active_scope_and_current_pair(self):
        task = {"status": "running", "agent_id": "codex", "task_id": "task", "client_route_id": "route",
                "client_conversation_id": "conversation", "client_turn_id": "turn", "contact_id": "contact",
                "source_message_id": "message", "execution_generation": 1}
        peer = {"client_route_id": "route", "identity_fingerprint": "phone-key", "local_identity_fingerprint": "desktop-key"}
        self.assertEqual("route", authenticated_scope(task, peer, "desktop")["client_route_id"])
        for change in ({"status": "completed"}, {"pause_requested": True}, {"cancel_requested": True}):
            with self.assertRaises(ValueError):
                authenticated_scope({**task, **change}, peer, "desktop")
        for change in ({"revoked": True}, {"client_route_id": "other"}, {"identity_fingerprint": None}):
            with self.assertRaises(ValueError):
                authenticated_scope(task, {**peer, **change}, "desktop")

    def test_dynamic_tool_registration_permissions_and_telemetry(self):
        events, calls = [], []
        def callback(task_id, directory, arguments, active):
            calls.append(task_id)
            self.assertTrue(active())
            return self.call(arguments, root=Path(directory))
        server = CodexAppServer("codex", {}, lambda *event: events.append(event),
            collaboration_recall=lambda *_: {}, collaboration_publish=lambda *_: {}, collaboration_file=callback)
        self.assertIn(tool_spec(), server._dynamic_tools)
        run = CodexRun("task", thread_id="thread", turn_id="turn", working_directory=str(self.author), sandbox="read-only")
        server._runs["task"] = run
        for sandbox, context in (("read-only", {}), ("workspace-write", {"turn_id": "stale"})):
            run.sandbox = sandbox
            with patch.object(server, "_write_server_response") as reply:
                server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": TOOL, "arguments": self.args}, context)
            self.assertFalse(reply.call_args.args[1]["success"])
        self.assertEqual([], calls)
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 2}, {"tool": TOOL, "arguments": self.args}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual("collaboration_file_artifact_returned", events[-1][1]["trace_stage"])
        self.assertFalse(run.finished)
        self.assertFalse(run.research_observed)
        partial = CodexAppServer("codex", {}, lambda *_: None, collaboration_file=callback)
        self.assertNotIn(TOOL, [tool["name"] for tool in partial._dynamic_tools])

    def test_bridge_rechecks_assignment_and_pair_identity_during_handoff(self):
        import mqtt_bridge
        original_task = {"status": "running", "agent_id": "codex", "task_id": "task", "client_route_id": "route",
            "client_conversation_id": "conversation", "client_turn_id": "turn", "contact_id": "contact",
            "source_message_id": "message", "execution_generation": 1}
        original_peer = {"client_route_id": "route", "identity_fingerprint": "phone-key",
            "local_identity_fingerprint": "desktop-key"}
        changes = [("task", key, value) for key, value in {
            "task_id": "other", "client_route_id": "other", "client_conversation_id": "other",
            "client_turn_id": "other", "contact_id": "other", "source_message_id": "other",
            "agent_id": "deepseek", "execution_generation": 2, "pause_requested": True,
            "cancel_requested": True, "status": "completed"}.items()]
        changes += [("peer", key, value) for key, value in {
            "identity_fingerprint": "changed", "local_identity_fingerprint": "changed",
            "client_route_id": "other", "revoked": True}.items()]
        for owner, key, value in changes:
            task, peer = dict(original_task), dict(original_peer)
            def handoff(store, directory, scope, arguments, *, active, publish, recall):
                self.assertEqual(self.author, directory)
                self.assertEqual("conversation", scope["conversation_id"])
                self.assertTrue(active())
                (task if owner == "task" else peer)[key] = value
                self.assertFalse(active())
                return {"success": False}
            with self.subTest(owner=owner, key=key), \
                    patch.object(mqtt_bridge.agent_task_manager, "get", return_value=SimpleNamespace(public=lambda: task)), \
                    patch.object(mqtt_bridge, "get_client", return_value=peer), \
                    patch.object(mqtt_bridge, "desktop_id", return_value="desktop"), \
                    patch("collaboration_file_artifact.execute", side_effect=handoff) as invoked:
                result = mqtt_bridge._codex_collaboration_file("task", self.author, self.args, lambda: True)
                self.assertFalse(result["success"])
                invoked.assert_called_once()

    def test_bridge_does_not_open_store_for_missing_or_revoked_phone(self):
        import mqtt_bridge
        task = {"status": "running", "agent_id": "codex", "task_id": "task", "client_route_id": "route",
            "client_conversation_id": "conversation", "client_turn_id": "turn", "contact_id": "contact",
            "source_message_id": "message", "execution_generation": 1}
        for peer in (None, {"client_route_id": "route", "revoked": True}):
            with self.subTest(peer=peer), \
                    patch.object(mqtt_bridge.agent_task_manager, "get", return_value=SimpleNamespace(public=lambda: task)), \
                    patch.object(mqtt_bridge, "get_client", return_value=peer), \
                    patch.object(mqtt_bridge, "desktop_id", return_value="desktop"), \
                    patch("collaboration_file_artifact.execute") as invoked, self.assertRaises(ValueError):
                mqtt_bridge._codex_collaboration_file("task", self.author, self.args, lambda: True)
            invoked.assert_not_called()


if __name__ == "__main__":
    unittest.main()
