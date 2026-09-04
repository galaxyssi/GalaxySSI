from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import stt_bridge


class _FakeModel:
    def __init__(self, text: str = " accurate transcript") -> None:
        self.text = text
        self.calls = []

    def transcribe(self, path: str, **kwargs):
        self.calls.append((path, kwargs))
        return [SimpleNamespace(text=self.text)], SimpleNamespace(
            language="en",
            language_probability=0.97,
            duration=1.25,
        )


class SttBridgeTests(unittest.TestCase):
    def tearDown(self) -> None:
        stt_bridge.reset_model_cache()

    def test_profile_identity_is_deterministic_and_aliases_are_canonical(self) -> None:
        turbo = stt_bridge.whisper_profile("turbo")
        self.assertEqual("large-v3-turbo", turbo.profile_id)
        self.assertEqual("turbo", turbo.model_name)
        self.assertRegex(turbo.profile_sha256, r"^[0-9a-f]{64}$")
        self.assertEqual(turbo.profile_sha256, stt_bridge.whisper_profile("large-v3-turbo").profile_sha256)

    def test_detailed_transcription_returns_profile_and_metrics(self) -> None:
        model = _FakeModel()
        with tempfile.TemporaryDirectory() as temporary:
            audio = Path(temporary) / "audio.wav"
            audio.write_bytes(b"RIFF-test")
            result = stt_bridge.transcribe_audio_detailed(
                audio,
                "en",
                profile="medium",
                model_factory=lambda _profile: model,
            )

        self.assertEqual("accurate transcript", result.text)
        self.assertEqual("en", result.language)
        self.assertEqual(0.97, result.language_probability)
        self.assertEqual(1.25, result.duration_seconds)
        self.assertEqual("medium", result.profile.profile_id)
        self.assertEqual(5, model.calls[0][1]["beam_size"])
        self.assertTrue(model.calls[0][1]["vad_filter"])

    def test_runtime_keeps_only_one_profile_loaded(self) -> None:
        created = []

        def factory(profile):
            created.append(profile.profile_id)
            return _FakeModel(profile.profile_id)

        with tempfile.TemporaryDirectory() as temporary:
            audio = Path(temporary) / "audio.wav"
            audio.write_bytes(b"RIFF-test")
            stt_bridge.transcribe_audio_detailed(audio, profile="medium", model_factory=factory)
            stt_bridge.transcribe_audio_detailed(audio, profile="medium", model_factory=factory)
            stt_bridge.transcribe_audio_detailed(audio, profile="large-v3", model_factory=factory)

        self.assertEqual(["medium", "large-v3"], created)


if __name__ == "__main__":
    unittest.main()
