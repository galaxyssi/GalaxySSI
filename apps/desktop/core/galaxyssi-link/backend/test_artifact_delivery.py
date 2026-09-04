import base64
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from artifact_delivery import (
    APK_MIME_TYPE,
    acknowledge_artifact,
    artifact_for_redelivery,
    artifact_chunk_payloads,
    pending_artifacts_for_redelivery,
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
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("apk-task", "codex")
            source = root / "outputs" / "SnakeGame.apk"
            expected = (b"galaxyssi-apk" * 30_000)[:320_000]
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
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("sidecar-task", "codex")
            source = root / "outputs" / "GalaxySSI.apk.idsig"
            source.write_bytes(b"internal")
            artifacts = prepare_artifacts(
                "sidecar-task",
                [{"name": source.name, "relative_path": "outputs/GalaxySSI.apk.idsig"}],
            )
        self.assertEqual([], artifacts)

    def test_verified_phone_receipt_removes_gateway_workspace(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
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
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
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

    def test_pending_artifact_can_only_be_redelivered_to_its_owning_phone(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            root = task_workspace("redelivery-task", "codex")
            source = root / "outputs" / "game.html"
            source.write_text("<canvas>GalaxySSI</canvas>", encoding="utf-8")
            artifact = prepare_artifacts(
                "redelivery-task",
                [{"name": source.name, "relative_path": "outputs/game.html"}],
            )[0]
            register_artifact_batch(
                [artifact],
                client_route_id="owner-route",
                retain_on_desktop=False,
            )
            request = {
                "artifact_id": artifact.artifact_id,
                "artifact_uri": artifact.artifact_uri,
                "sha256": artifact.sha256,
            }
            rejected = artifact_for_redelivery(
                request,
                client_route_id="different-route",
            )
            restored = artifact_for_redelivery(
                request,
                client_route_id="owner-route",
            )
            pending = pending_artifacts_for_redelivery()

        self.assertIsNone(rejected)
        self.assertIsNotNone(restored)
        self.assertEqual(artifact.artifact_id, restored.artifact_id)
        self.assertEqual(artifact.sha256, restored.sha256)
        self.assertEqual([("owner-route", artifact.artifact_id)], [
            (route_id, candidate.artifact_id) for route_id, candidate in pending
        ])


if __name__ == "__main__":
    unittest.main()
