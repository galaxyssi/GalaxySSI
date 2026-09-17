# Foreground wake-up

Enable **Hello Hello wake-up** in Settings and allow microphone access. Return to the conversation home screen, say **Hello Hello**, wait for the short vibration, then ask the question in the voice capture screen. Recognition results follow the confirmation countdown described below.

Listening is local and opt-in. It pauses when the app leaves the foreground, while typing, during a reply or narration, and during external speech input. It does not keep the display awake, start from boot, or listen in the background. Narration and voice input are followed by a short cooldown. Captured wake audio and recognized transcripts are not stored or uploaded.

The implementation uses Vosk with a constrained English grammar, confidence checks, and a two-word duration check. It is not a DSP hotword implementation; foreground listening adds CPU and battery use. Quiet/noisy-room accuracy and long-duration power consumption require physical testing.

## Dependencies

- Vosk Android 0.3.75: Apache-2.0, https://github.com/alphacep/vosk-api
- Vosk small US English model 0.15: Apache-2.0, https://alphacephei.com/vosk/models
- JNA 5.18.1: dual LGPL-2.1-or-later / Apache-2.0, https://github.com/java-native-access/jna

The model is downloaded at build time, SHA-256 verified, cached in the Gradle user home, and bundled in the APK. The approximately 40 MB compressed model is copied to app-specific storage on first use; subsequent foreground sessions reuse the loaded model. No API key or runtime network download is needed for wake detection.

## System-assistant entry

Version 0.2.14 adds a launcher alias, **GalaxySSI Voice**, and an opt-in **Start voice input on app open** setting. The alias requests voice input once after the home screen is foreground, focused, unlocked, and local history is loaded. The setting applies the same behavior to ordinary launcher opens (including icon taps). Notification task links do not request speech. Returning from, cancelling, or recreating the speech screen does not replay a consumed request.

Bixby remains responsible for its own wake phrase and screen-off wake behavior. Ask it to open GalaxySSI with the setting enabled, or try the separately named GalaxySSI Voice entry. Whether Bixby resolves the app name on a particular watch/language must be physically verified; successful ADB or launcher entry is not proof of Bixby wake-to-app routing. No custom Samsung hardware wake model, privileged permission, or background microphone is installed.

As of 0.2.16, the voice entry uses the public system RecognitionService in an app-owned preview. On the tested watch this service is Google; Samsung input is available as an explicit manual-confirmation fallback. A final nonblank result starts a two-second countdown. Touch, keys, rotary input, focus loss, or backgrounding cancel automatic submission and retain the transcript for manual sending. Partial results and failed recognition are never sent. Retry clears the previous draft. Returning or recreating the preview does not re-arm automatic sending. Xiaoxiao narration follows the existing reply flow.

Keep Start voice input on app open disabled to open chat from the normal GalaxySSI icon. Bind the watch double-press shortcut to GalaxySSI Voice for direct capture. The two icons share one installation and all settings/history. Lock-screen security is respected; unlock the watch before speech input can start.

## Validation status for 0.2.16

Debug and instrumentation APK builds, lint, and 55 unit tests pass. Device entry-routing tests passed. The device countdown test `finalResultReturnsAfterTwoSecondsWithoutConfirmation` failed its final activity-finished assertion; the watch then became offline before the remaining device tests completed. Automatic submission is therefore not yet verified end to end on hardware. Reproduce with the watch unlocked and the capture window focused, and investigate any focus/lifecycle interruption before treating this feature as verified. Natural spoken Hello Hello accuracy and Bixby screen-off routing also remain unverified.
