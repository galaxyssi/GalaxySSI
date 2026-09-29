"""Final images are downloadable originals, not renamed transport thumbnails."""
import base64
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from PIL import Image

import artifact_delivery as delivery
import blob_artifact_publication as publication
from task_workspace import task_workspace


class ArtifactImageFidelityTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        env = patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": directory.name})
        env.start()
        self.addCleanup(env.stop)
        self.root = task_workspace("image-fidelity")
        self.path = self.root / "outputs" / "preview.png"
        Image.frombytes("RGBA", (320, 320), os.urandom(320 * 320 * 4)).save(self.path)
        self.raw = self.path.read_bytes()
        self.assertGreater(len(self.raw), delivery.MAX_IMAGE_TRANSPORT_BYTES)
        self.files = [{"relative_path": "outputs/preview.png", "name": "preview.png"}]

    def test_default_image_is_byte_exact_chunked_without_full_file_allocation(self):
        with patch.object(delivery, "compress_image_file", side_effect=AssertionError("lossy conversion")), \
                patch.object(Path, "read_bytes", side_effect=AssertionError("whole-file allocation")):
            artifact = delivery.prepare_artifacts("image-fidelity", self.files)[0]
        restored = b"".join(base64.b64decode(chunk["data_b64"])
                            for chunk in delivery.artifact_chunk_payloads(artifact))
        self.assertEqual(self.raw, restored)
        self.assertEqual("image/png", artifact.mime_type)
        self.assertEqual("preview.png", artifact.name)
        self.assertEqual(hashlib.sha256(self.raw).hexdigest(), artifact.sha256)
        self.assertEqual(artifact.original_sha256, artifact.sha256)
        self.assertEqual(artifact.original_size_bytes, artifact.size_bytes)
        self.assertIsNone(artifact.transport_bytes)
        self.assertFalse(artifact.compress_images)
        self.assertGreater(artifact.chunk_count, 1)

    def test_blob_and_fallback_route_preparation_both_preserve_original(self):
        for enabled in (True, False):
            with self.subTest(blob=enabled), \
                    patch("blob_pair_configuration.can_receive_artifacts", return_value=enabled), \
                    patch("blob_pair_configuration.private_settings", return_value={"enabled": enabled}):
                artifact = publication.prepare_for_route(Mock(), "phone", "image-fidelity", self.files)[0]
                self.assertEqual(hashlib.sha256(self.raw).hexdigest(), artifact.sha256)
                self.assertEqual("image/png", artifact.mime_type)
                self.assertFalse(artifact.compress_images)

    def test_original_policy_and_hash_survive_ledger_redelivery(self):
        artifact = delivery.prepare_artifacts("image-fidelity", self.files)[0]
        delivery.register_artifact_batch([artifact], client_route_id="phone", retain_on_desktop=True)
        restored = delivery.artifact_for_redelivery(
            {"artifact_id": artifact.artifact_id, "artifact_uri": artifact.artifact_uri, "sha256": artifact.sha256},
            client_route_id="phone")
        self.assertIsNotNone(restored)
        self.assertEqual(artifact.sha256, restored.sha256)
        self.assertEqual(artifact.artifact_id, restored.artifact_id)
        self.assertFalse(restored.compress_images)
        self.assertEqual(self.raw, b"".join(data for _, data in restored.chunks()))

    def test_old_explicit_compressed_receipt_keeps_its_original_identity(self):
        artifact = delivery.prepare_artifacts("image-fidelity", self.files, compress_images=True)[0]
        self.assertTrue(artifact.compress_images)
        self.assertNotEqual(artifact.original_sha256, artifact.sha256)
        delivery.register_artifact_batch([artifact], client_route_id="phone", retain_on_desktop=True)
        restored = delivery.artifact_for_redelivery(
            {"artifact_id": artifact.artifact_id, "artifact_uri": artifact.artifact_uri, "sha256": artifact.sha256},
            client_route_id="phone")
        self.assertEqual(artifact.artifact_id, restored.artifact_id)
        self.assertEqual(artifact.transport_bytes, restored.transport_bytes)

    def test_animated_gif_and_lossless_webp_are_not_flattened(self):
        for suffix, options in (("gif", {"save_all": True, "append_images": [Image.new("RGB", (20, 20), "blue")]}),
                                ("webp", {"lossless": True})):
            with self.subTest(format=suffix):
                path = self.path.with_suffix("." + suffix)
                Image.new("RGB", (20, 20), "red").save(path, **options)
                artifact = delivery.prepare_artifacts("image-fidelity", [{"relative_path": "outputs/" + path.name}])[0]
                self.assertEqual(path.read_bytes(), b"".join(data for _, data in artifact.chunks()))
                self.assertEqual("image/" + suffix, artifact.mime_type)


if __name__ == "__main__":
    unittest.main()
