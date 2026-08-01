# Whisper benchmark audio

`zh_cn_v1.wav` is a deterministic, non-user benchmark fixture generated from a
project-authored sentence with the operating system speech synthesizer. It is
PCM16, 16 kHz, mono, and contains no recorded human voice or private user data.

- Version: `zh_cn_v2` (the PCM is unchanged; correctness now covers the full fixture and normalizes Chinese script variants)
- SHA-256: `9a3505df8e1d6c1a60c87c7f7cc6e303e882189512d218f075a20f4784db05da`
- Duration: approximately 15.84 seconds

Changing the fixture or its expected checksum invalidates existing device
certifications through the benchmark key.
