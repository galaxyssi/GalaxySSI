from __future__ import annotations

import base64
import hashlib
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

from remote_whisper_node import (
    AUDIO_FORMAT,
    CHUNK_TYPE,
    CONSENT_SCOPE,
    PROTOCOL,
    RemoteWhisperNodeConfig,
    RemoteWhisperRequestAssembler,
    RemoteWhisperNodeService,
)
from stt_bridge import WhisperTranscription, whisper_profile


NOW = 1_900_000_000_000
ROUTE = "a" * 32
CLIENT = "galaxyssi:test-phone"


def request_payload(
    service: RemoteWhisperNodeService,
    *,
    pcm: bytes = b"\x01\x00" * 16_000,
    request_id: str | None = None,
) -> dict:
    profile = service.capability(ROUTE)["active_profile"]
    return {
        "type": "remote_whisper_request",
        "protocol": PROTOCOL,
        "request_id": request_id or str(uuid.uuid4()),
        "voice_session_id": "voice-session-1",
        "transcript_id": "transcript-1",
        "client_route_id": ROUTE,
        "client_id": CLIENT,
        "language": "en",
        "authorization": {
            "explicit": True,
            "only_my_devices": True,
            "scope": CONSENT_SCOPE,
            "authorized_at_ms": NOW,
            "request_audio_deletion": True,
        },
        "model": {
            "profile_id": profile["profile_id"],
            "profile_sha256": profile["profile_sha256"],
        },
        "audio": {
            "format": AUDIO_FORMAT,
            "sample_rate_hz": 16_000,
            "channels": 1,
            "sample_count": len(pcm) // 2,
            "byte_count": len(pcm),
            "duration_ms": len(pcm) // 2 * 1_000 // 16_000,
            "sha256": hashlib.sha256(pcm).hexdigest(),
            "data_base64": base64.b64encode(pcm).decode("ascii"),
        },
    }


def chunked_payloads(payload: dict, chunk_size: int = 4_096):
    manifest = {**payload, "audio": dict(payload["audio"])}
    pcm = base64.b64decode(manifest["audio"].pop("data_base64"))
    chunks = [pcm[index:index + chunk_size] for index in range(0, len(pcm), chunk_size)]
    manifest["audio"]["chunk_count"] = len(chunks)
    manifest["audio"]["chunk_size_bytes"] = chunk_size
    packets = [
        {
            "type": CHUNK_TYPE,
            "protocol": PROTOCOL,
            "request_id": manifest["request_id"],
            "client_route_id": manifest["client_route_id"],
            "client_id": manifest["client_id"],
            "chunk_index": index,
            "chunk_count": len(chunks),
            "chunk_sha256": hashlib.sha256(chunk).hexdigest(),
            "data_base64": base64.b64encode(chunk).decode("ascii"),
        }
        for index, chunk in enumerate(chunks)
    ]
    return manifest, packets


class RemoteWhisperNodeTests(unittest.TestCase):
    def make_service(self, temporary: str, transcriber=None, **config_values):
        config = RemoteWhisperNodeConfig(
            enabled=config_values.pop("enabled", True),
            model_profile_id=config_values.pop("model_profile_id", "medium"),
            temp_root=Path(temporary) / "voice-temp",
            **config_values,
        )

        def default_transcriber(path, _language, profile):
            return WhisperTranscription("correct text", "en", 0.99, 1.0, profile)

        return RemoteWhisperNodeService(
            config,
            transcriber=transcriber or default_transcriber,
            clock_ms=lambda: NOW,
            dependency_available=lambda: True,
        )

    @staticmethod
    def paired_client():
        return {"client_route_id": ROUTE, "signal_name": CLIENT}

    def test_capability_declares_identity_profiles_and_privacy_policy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary)
            capability = service.capability(ROUTE)
            service.shutdown()

        self.assertTrue(capability["available"])
        self.assertEqual(PROTOCOL, capability["protocol"])
        self.assertEqual(AUDIO_FORMAT, capability["supported_audio"][0])
        self.assertEqual("medium", capability["active_profile"]["profile_id"])
        self.assertRegex(capability["active_profile"]["profile_sha256"], r"^[0-9a-f]{64}$")
        self.assertTrue(capability["authorization"]["explicit_user_consent_required"])
        self.assertEqual("ephemeral", capability["retention"]["raw_audio"])

    def test_complete_verified_audio_is_transcribed_and_deleted(self) -> None:
        observed_paths = []

        def transcribe(path, _language, profile):
            observed_paths.append(path)
            self.assertTrue(path.is_file())
            return WhisperTranscription("verified result", "en", 0.95, 1.0, profile)

        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary, transcriber=transcribe)
            result = service.process(
                request_payload(service),
                client_route_id=ROUTE,
                paired_client=self.paired_client(),
            )
            service.shutdown()

        self.assertEqual("completed", result["status"])
        self.assertEqual("verified result", result["content"])
        self.assertTrue(result["cleanup"]["verified"])
        self.assertFalse(observed_paths[0].exists())
        self.assertNotIn("data_base64", repr(result))

    def test_unpaired_mismatched_or_unapproved_device_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary)
            payload = request_payload(service)
            unpaired = service.process(payload, client_route_id=ROUTE, paired_client=None)
            mismatch = service.process(payload, client_route_id="b" * 32, paired_client=self.paired_client())
            payload["authorization"]["explicit"] = False
            unapproved = service.process(payload, client_route_id=ROUTE, paired_client=self.paired_client())
            service.shutdown()

        self.assertEqual("identity_required", unpaired["error_code"])
        self.assertEqual("identity_mismatch", mismatch["error_code"])
        self.assertEqual("authorization_required", unapproved["error_code"])

    def test_truncated_or_corrupted_pcm_never_reaches_transcriber(self) -> None:
        calls = []
        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(
                temporary,
                transcriber=lambda *args: calls.append(args),
            )
            truncated = request_payload(service)
            truncated["audio"]["byte_count"] += 2
            truncated_result = service.process(
                truncated,
                client_route_id=ROUTE,
                paired_client=self.paired_client(),
            )
            corrupt = request_payload(service)
            corrupt["audio"]["sha256"] = "0" * 64
            corrupt_result = service.process(
                corrupt,
                client_route_id=ROUTE,
                paired_client=self.paired_client(),
            )
            service.shutdown()

        self.assertEqual("audio_length_mismatch", truncated_result["error_code"])
        self.assertEqual("audio_integrity_failed", corrupt_result["error_code"])
        self.assertEqual([], calls)

    def test_encrypted_message_chunks_reassemble_out_of_order_before_decode(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary)
            assembler = RemoteWhisperRequestAssembler(
                max_chunk_bytes=4_096,
                clock_ms=lambda: NOW,
            )
            manifest, chunks = chunked_payloads(request_payload(service), 4_096)
            self.assertIsNone(assembler.accept(manifest, client_route_id=ROUTE))
            completed = None
            for chunk in reversed(chunks):
                completed = assembler.accept(chunk, client_route_id=ROUTE)
            result = service.process(
                completed,
                client_route_id=ROUTE,
                paired_client=self.paired_client(),
            )
            service.shutdown()

        self.assertEqual("completed", result["status"])
        self.assertEqual(0, assembler.active_count())

    def test_incomplete_transfer_never_produces_a_request_and_expires_cleanly(self) -> None:
        clock = [NOW]
        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary)
            assembler = RemoteWhisperRequestAssembler(
                max_chunk_bytes=4_096,
                transfer_ttl_ms=1_000,
                clock_ms=lambda: clock[0],
            )
            manifest, chunks = chunked_payloads(request_payload(service), 4_096)
            assembler.accept(manifest, client_route_id=ROUTE)
            self.assertIsNone(assembler.accept(chunks[0], client_route_id=ROUTE))
            self.assertEqual(1, assembler.active_count())
            clock[0] += 1_001
            self.assertEqual(0, assembler.active_count())
            service.shutdown()

    def test_duplicate_request_is_transcribed_once_and_conflicts_fail_closed(self) -> None:
        calls = []

        def transcribe(_path, _language, profile):
            calls.append(profile.profile_id)
            return WhisperTranscription("once", "en", 0.9, 1.0, profile)

        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary, transcriber=transcribe)
            request_id = str(uuid.uuid4())
            payload = request_payload(service, request_id=request_id)
            first = service.process(payload, client_route_id=ROUTE, paired_client=self.paired_client())
            duplicate = service.process(payload, client_route_id=ROUTE, paired_client=self.paired_client())
            changed = request_payload(service, pcm=b"\x02\x00" * 16_000, request_id=request_id)
            conflict = service.process(changed, client_route_id=ROUTE, paired_client=self.paired_client())
            service.shutdown()

        self.assertEqual("completed", first["status"])
        self.assertTrue(duplicate["duplicate"])
        self.assertEqual("idempotency_conflict", conflict["error_code"])
        self.assertEqual(["medium"], calls)

    def test_cancelled_request_does_not_publish_a_transcript(self) -> None:
        started = threading.Event()
        release = threading.Event()
        completed = threading.Event()
        results = []

        def transcribe(_path, _language, profile):
            started.set()
            release.wait(2.0)
            return WhisperTranscription("must not execute", "en", 0.9, 1.0, profile)

        with tempfile.TemporaryDirectory() as temporary:
            service = self.make_service(temporary, transcriber=transcribe)
            payload = request_payload(service)
            service.submit(
                payload,
                client_route_id=ROUTE,
                paired_client=self.paired_client(),
                on_result=lambda result: (results.append(result), completed.set()),
            )
            self.assertTrue(started.wait(1.0))
            acknowledgement = service.cancel(
                {"request_id": payload["request_id"], "client_route_id": ROUTE},
                client_route_id=ROUTE,
            )
            release.set()
            self.assertTrue(completed.wait(2.0))
            service.shutdown()

        self.assertEqual("cancelled", acknowledgement["status"])
        self.assertEqual("cancelled", results[0]["status"])
        self.assertNotIn("content", results[0])


if __name__ == "__main__":
    unittest.main()
