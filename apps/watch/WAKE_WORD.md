# Foreground wake-up

Enable **Hello Hello wake-up** in Settings and allow microphone access. Return to the conversation home screen, say **Hello Hello**, wait for the short vibration, then ask the question in Samsung voice input. Once Samsung returns a confirmed transcript, GalaxySSI sends it automatically.

Listening is local and opt-in. It pauses when the app leaves the foreground, while typing, during a reply or narration, and during external speech input. It does not keep the display awake, start from boot, or listen in the background. Narration and voice input are followed by a short cooldown. Captured wake audio and recognized transcripts are not stored or uploaded.

The implementation uses Vosk with a constrained English grammar, confidence checks, and a two-word duration check. It is not a DSP hotword implementation; foreground listening adds CPU and battery use. Quiet/noisy-room accuracy and long-duration power consumption require physical testing.

## Dependencies

- Vosk Android 0.3.75: Apache-2.0, https://github.com/alphacep/vosk-api
- Vosk small US English model 0.15: Apache-2.0, https://alphacephei.com/vosk/models
- JNA 5.18.1: dual LGPL-2.1-or-later / Apache-2.0, https://github.com/java-native-access/jna

The model is downloaded at build time, SHA-256 verified, cached in the Gradle user home, and bundled in the APK. The approximately 40 MB compressed model is copied to app-specific storage on first use; subsequent foreground sessions reuse the loaded model. No API key or runtime network download is needed for wake detection.

## System-assistant entry

The **GalaxySSI Voice** launcher entry forwards a fresh voice command to the main activity. A separate transient activity is used instead of an activity alias: Samsung hardware shortcuts can otherwise merely bring an existing home task forward without delivering a new intent. Voice input starts once after the home screen is foreground, focused, unlocked, and local history is loaded. The opt-in **Start voice input on app open** setting applies the same behavior to ordinary launcher opens (including icon taps). Notification task links do not request speech. Returning from, cancelling, or recreating the speech screen does not replay a consumed request.

Bixby remains responsible for its own wake phrase and screen-off wake behavior. Ask it to open GalaxySSI with the setting enabled, or try the separately named GalaxySSI Voice entry. Whether Bixby resolves the app name on a particular watch/language must be physically verified; successful ADB or launcher entry is not proof of Bixby wake-to-app routing. No custom Samsung hardware wake model, privileged permission, or background microphone is installed.

The voice entry prefers Samsung's speech activity and falls back to the platform speech activity if Samsung cannot be launched. GalaxySSI sends a confirmed nonblank result automatically and uses the existing Xiaoxiao reply narration. Cancellation never sends a message.

## Optional Samsung auto-confirmation

Enable **GalaxySSI voice auto-confirm** in the watch accessibility settings using the shortcut in GalaxySSI settings. Android controls this consent; installing the app does not enable the service. Both the enabled and connected system service and the in-app toggle are required. Disabling or disconnecting the service cancels a pending session; no fallback tap is performed.

Only a Samsung speech session explicitly launched by GalaxySSI arms the in-memory gate, which expires after two minutes. The service requires Samsung's remote-input activity shell and its separate IME window, a visible nonempty result, the microphone-off state, and a visible enabled Done button with verified resource IDs and Chinese/English labels. After that window/text combination remains stable for 1.5 seconds, the gate disarms and performs one semantic ACTION_CLICK. Unknown layouts or labels fall back to manual confirmation. No fixed coordinates, injected hardware keys, root, or ADB runtime dependency are used.

Leaving the speech page, screen-off, service interruption, key presses, and observed clicks during the confirmation countdown cancel the session. Samsung also scrolls its result view programmatically, so scroll events restart stability rather than cancelling the whole session. Accessibility does not reliably expose every arbitrary screen touch; blanket touch cancellation is not claimed. The service does not store or upload inspected text. Recognition and the subsequent chat send retain their existing network behavior. It remains inactive for Samsung input opened by other apps and after process death or restart. Its service dump exposes only state flags and event types, never recognized text.

Keep Start voice input on app open disabled to open chat from the normal GalaxySSI icon. Bind the watch double-press shortcut to GalaxySSI Voice for direct capture. The two icons share one installation and all settings/history. Lock-screen security is respected; unlock the watch before speech input can start.

Natural spoken Hello Hello accuracy and Bixby screen-off routing require physical validation. A successful launcher or ADB entry does not prove either voice wake path.
