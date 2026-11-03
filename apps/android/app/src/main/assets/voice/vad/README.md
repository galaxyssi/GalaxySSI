# Local speech activity detection

`silero_vad_16k_op15.onnx` is the unmodified 16 kHz Silero VAD model from
snakers4/silero-vad v6.2.3, commit `5cd7945676eb32225748052e2e6a0580e4686a08`.

- Source: https://github.com/snakers4/silero-vad/tree/5cd7945676eb32225748052e2e6a0580e4686a08
- File: `src/silero_vad/data/silero_vad_16k_op15.onnx`
- Size: 1,289,603 bytes
- SHA-256: `7ed98ddbad84ccac4cd0aeb3099049280713df825c610a8ed34543318f1b2c49`
- License: MIT, reproduced in `LICENSE.silero-vad`.

The model runs locally with the existing ONNX Runtime CPU provider and one
non-spinning inference thread. It accepts 512-sample windows plus 64 samples of
context and a private recurrent state. No microphone audio is uploaded by VAD.
Capture continues to use platform noise suppression and acoustic echo
cancellation when available. VAD rejects non-speech; it does not identify the
owner's voice, exclude TV speech, or separate overlapping speakers.

There is no silent fallback to energy-only speech detection if model preparation
or inference fails. Capture reports the failure and releases its resources.
