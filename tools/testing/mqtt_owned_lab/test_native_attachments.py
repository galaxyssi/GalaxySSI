import base64
import hashlib
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "apps/desktop/core/galaxyssi-link/backend"))
from native_attachment_endpoint import AttachmentEndpoint, digest


class AttachmentFixtureTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="galaxyssi-owned-attachment-unit-")
        self.addCleanup(temp.cleanup)
        self.endpoint = SimpleNamespace(root=Path(temp.name), remote="owned-peer", route="A" * 22,
            client=object(), bridge=SimpleNamespace(_publish_phone_payload=Mock(return_value=True)))
        self.fixture = AttachmentEndpoint(self.endpoint)

    def prepare(self, **kwargs):
        return self.fixture.prepare({"kind": "file", "size": 262145, "receiver_route": "B" * 22, **kwargs})

    def test_invalid_requests_have_no_filesystem_side_effect(self):
        for values in ({"size": 0}, {"size": True}, {"size": 33 * 1024 * 1024}, {"kind": "unknown"},
                       {"receiver_route": "../outside"}):
            with self.assertRaises(ValueError):
                self.prepare(**values)
        self.assertEqual([], list(self.fixture.root.iterdir()))
        for case in ("../outside", "C:/outside", None, "A" * 32):
            with self.assertRaises(ValueError):
                self.fixture.case_path(case)

    def test_chunks_match_production_manifest_and_exact_file_bytes(self):
        record = self.prepare()
        manifest, case = record["manifest"], record["case"]
        self.assertEqual(2, manifest["chunk_count"])
        directory, saved = self.fixture.load(case)
        self.assertEqual(record, saved)
        self.assertEqual(manifest["sha256"], digest(directory / record["source"]))
        chunks = []
        for index, size in ((0, 262144), (1, 1)):
            self.fixture.send(case, "chunk", index)
            payload = self.endpoint.bridge._publish_phone_payload.call_args.args[2]
            data = base64.b64decode(payload["data_b64"], validate=True)
            self.assertEqual(size, len(data))
            self.assertEqual(hashlib.sha256(data).hexdigest(), payload["chunk_sha256"])
            chunks.append(data)
        self.assertEqual((directory / record["source"]).read_bytes(), b"".join(chunks))
        for index in (-1, 2, True):
            with self.assertRaises(ValueError):
                self.fixture.send(case, "chunk", index)

    def test_receipts_are_scope_bound_and_survive_fixture_restart(self):
        record = self.prepare(size=1)
        payload = {**record["manifest"], "type": "input_attachment_receipt", "status": "stored"}
        for key in ("transfer_id", "sha256", "client_route_id", "conversation_id", "contact_id", "task_id", "turn_id", "attachment_id"):
            with self.assertRaises(ValueError):
                self.fixture.capture_receipt({**payload, key: "wrong"})
        self.fixture.capture_receipt(payload)
        restored = AttachmentEndpoint(self.endpoint)
        self.assertEqual(payload, restored.command({"operation": "receipt", "transfer_id": payload["transfer_id"]}))

    def test_png_is_real_decodable_image_and_cases_are_bounded(self):
        from PIL import Image
        record = self.prepare(kind="png")
        directory, _ = self.fixture.load(record["case"])
        with Image.open(directory / record["source"]) as image:
            self.assertEqual((200, 170), image.size)
            image.verify()
        for _ in range(15):
            self.prepare(size=1)
        with self.assertRaises(ValueError):
            self.prepare(size=1)
        self.assertEqual(16, len(list(self.fixture.root.iterdir())))


if __name__ == "__main__":
    unittest.main()
