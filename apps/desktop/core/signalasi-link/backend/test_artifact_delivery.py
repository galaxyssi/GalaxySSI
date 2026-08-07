import base64
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from artifact_delivery import (
    APK_MIME_TYPE,
    acknowledge_artifact,
    artifact_chunk_payloads,
    prepare_artifacts,
    register_artifact_batch,
    should_deliver_task_artifacts,
)
from task_workspace import task_workspace


class ArtifactDeliveryTests(unittest.TestCase):
    def test_fast_chat_delivers_an_unexpected_generated_artifact(self):
        self.assertTrue(should_deliver_task_artifacts(
            fast_chat_delivery=True,
            plan_only=False,
            generated_output_files=[{"relative_path": "outputs/game.html"}],
        ))
        self.assertTrue(should_deliver_task_artifacts(
            fast_chat_delivery=True,
            plan_only=False,
            referenced_output_paths=[Path("outputs/game.html")],
        ))
        self.assertFalse(should_deliver_task_artifacts(
            fast_chat_delivery=True,
            plan_only=False,
        ))
        self.assertFalse(should_deliver_task_artifacts(
            fast_chat_delivery=True,
            plan_only=True,
            generated_output_files=[{"relative_path": "outputs/game.html"}],
        ))

    def test_apk_is_chunked_with_installable_mime_and_integrity(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"SIGNALASI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("apk-task", "codex")
            source = root / "outputs" / "SnakeGame.apk"
            expected = (b"signalasi-apk" * 30_000)[:320_000]
            source.write_bytes(expected)
            artifacts = prepare_artifacts(
                "apk-task",
                [{"name": source.name, "relative_path": "outputs/SnakeGame.apk"}],
            )
            payloads = list(artifact_chunk_payloads(artifacts[0]))

        self.assertEqual(APK_MIME_TYPE, artifacts[0].mime_type)
        self.assertEqual(2, len(payloads))
        self.assertEqual([0, 1], [item["chunk_index"] for item in payloads])
        reassembled = b"".join(base64.b64decode(item["data_b64"]) for item in payloads)
        self.assertEqual(expected, reassembled)
        self.assertEqual(artifacts[0].sha256, payloads[0]["sha256"])

    def test_signing_sidecars_are_never_prepared(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"SIGNALASI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("sidecar-task", "codex")
            source = root / "outputs" / "SignalASI.apk.idsig"
            source.write_bytes(b"internal")
            artifacts = prepare_artifacts(
                "sidecar-task",
                [{"name": source.name, "relative_path": "outputs/SignalASI.apk.idsig"}],
            )
        self.assertEqual([], artifacts)

    def test_verified_phone_receipt_removes_gateway_workspace(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"SIGNALASI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("handoff-task", "codex")
            source = root / "outputs" / "report.txt"
            source.write_text("phone owned", encoding="utf-8")
            artifact = prepare_artifacts(
                "handoff-task",
                [{"name": source.name, "relative_path": "outputs/report.txt"}],
            )[0]
            register_artifact_batch(
                [artifact],
                client_route_id="client-route",
                retain_on_desktop=False,
            )
            accepted = acknowledge_artifact(
                {
                    "artifact_id": artifact.artifact_id,
                    "sha256": artifact.sha256,
                    "status": "stored",
                },
                client_route_id="client-route",
            )
            self.assertTrue(accepted)
            self.assertFalse(root.exists())

    def test_explicit_desktop_retention_keeps_workspace(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"SIGNALASI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("retained-task", "codex")
            source = root / "outputs" / "report.txt"
            source.write_text("retained", encoding="utf-8")
            artifact = prepare_artifacts(
                "retained-task",
                [{"name": source.name, "relative_path": "outputs/report.txt"}],
            )[0]
            register_artifact_batch(
                [artifact],
                client_route_id="client-route",
                retain_on_desktop=True,
            )
            accepted = acknowledge_artifact(
                {
                    "artifact_id": artifact.artifact_id,
                    "sha256": artifact.sha256,
                    "status": "stored",
                },
                client_route_id="client-route",
            )
            self.assertTrue(accepted)
            self.assertTrue(source.is_file())


if __name__ == "__main__":
    unittest.main()
