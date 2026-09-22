# Hello Hello wake-up

Enable **Hello Hello wake-up** in Settings and allow microphone access. Return to the conversation home screen, say **Hello Hello**, wait for the short vibration, then ask the question in Samsung voice input. Once Samsung returns a confirmed transcript, GalaxySSI sends it automatically.

Listening is local and opt-in. It pauses when the app leaves the foreground, while typing, during a reply or narration, and during external speech input. The default mode does not keep the display awake, start from boot, or listen in the background. Narration and voice input are followed by a short cooldown. Captured wake audio and recognized transcripts are not stored or uploaded.

The implementation uses Vosk with a constrained English grammar, confidence checks, and a two-word duration check. It is not a DSP hotword implementation; foreground listening adds CPU and battery use. Quiet/noisy-room accuracy and long-duration power consumption require physical testing.

## Dependencies

- Vosk Android 0.3.75: Apache-2.0, https://github.com/alphacep/vosk-api
- Vosk small US English model 0.15: Apache-2.0, https://alphacephei.com/vosk/models
- JNA 5.18.1: dual LGPL-2.1-or-later / Apache-2.0, https://github.com/java-native-access/jna

The model is downloaded at build time, SHA-256 verified, cached in the Gradle user home, and bundled in the APK. The approximately 40 MB compressed model is copied to app-specific storage on first use; subsequent foreground sessions reuse the loaded model. No API key or runtime network download is needed for wake detection.

## System-assistant entry

The **GalaxySSI Voice** launcher entry forwards a fresh voice command to the main activity. A separate transient activity is used instead of an activity alias: Samsung hardware shortcuts can otherwise merely bring an existing home task forward without delivering a new intent. Voice input starts once after the home screen is foreground, focused, and unlocked. The opt-in **Start voice input on app open** setting applies the same behavior to ordinary launcher opens (including icon taps). Notification task links do not request speech. Returning from, cancelling, or recreating the speech screen does not replay a consumed request.

Bixby remains responsible for its own wake phrase and screen-off wake behavior. Ask it to open GalaxySSI with the setting enabled, or try the separately named GalaxySSI Voice entry. Whether Bixby resolves the app name on a particular watch/language must be physically verified; successful ADB or launcher entry is not proof of Bixby wake-to-app routing. No custom Samsung hardware wake model or privileged permission is installed. Background microphone use requires the separate opt-in mode below.

The voice entry prefers Samsung's speech activity and falls back to the platform speech activity if Samsung cannot be launched. GalaxySSI sends a confirmed nonblank result automatically and uses the existing Xiaoxiao reply narration. Cancellation never sends a message.

## Optional Samsung auto-confirmation

Enable **GalaxySSI voice auto-confirm** in the watch accessibility settings using the shortcut in GalaxySSI settings. Android controls this consent; installing the app does not enable the service. Both the enabled and connected system service and the in-app toggle are required. Disabling or disconnecting the service cancels a pending session; no fallback tap is performed.

Only a Samsung speech session explicitly launched by GalaxySSI arms the in-memory gate, which expires after two minutes. The service requires Samsung's remote-input activity shell and its separate IME window, a visible nonempty result, the microphone-off state, and a visible enabled Done button with verified resource IDs and Chinese/English labels. After that window/text combination remains stable for 1.5 seconds, the gate disarms and performs one semantic ACTION_CLICK. Unknown layouts or labels fall back to manual confirmation. No fixed coordinates, injected hardware keys, root, or ADB runtime dependency are used.

During an armed Samsung session a transparent accessibility overlay detects the first touch without a hint or toast. The first touch anywhere is consumed to cancel automatic confirmation and remove the overlay; later touches operate Samsung normally. This works before a result exists as well as during its countdown. Manual Done still sends the confirmed transcript immediately. If the overlay cannot be installed, automatic confirmation is disabled for the session. Leaving the speech page, screen-off, service interruption and key presses also cancel it. Samsung-generated scrolling restarts stability rather than cancelling. The service does not store or upload inspected text. Recognition and the subsequent chat send retain their existing network behavior. It remains inactive for Samsung input opened by other apps and after process death or restart. Its service dump exposes only state flags and event types, never recognized text.

Keep Start voice input on app open disabled to open chat from the normal GalaxySSI icon. Bind the watch double-press shortcut to GalaxySSI Voice for direct capture. The two icons share one installation and all settings/history. Lock-screen security is respected; unlock the watch before speech input can start.

Natural spoken Hello Hello accuracy and Bixby screen-off routing require physical validation. A successful launcher or ADB entry does not prove either voice wake path.

## Optional screen-off and background mode

Enable **Screen-off and background listening** while GalaxySSI is visible and grant microphone and notification access. This also enables Hello Hello wake-up. A microphone foreground service owns local recognition and holds a partial CPU wake lock only while loading/listening; the display may sleep. This is software recognition, not Samsung low-power DSP wake-up, and increases battery use. The home screen shows only the centered clock, without a wake-status suffix.

The service pauses on other GalaxySSI pages, while typing/replying/narrating on the home screen, and during Samsung speech input. Microphone handoffs wait for the previous recorder to release. Contact recording is stopped when its activity pauses. Returning to the eligible home screen resumes foreground recognition; leaving the app or turning off the screen resumes background recognition after the activity transition.

A foreground home detection vibrates and opens Samsung input. A background detection vibrates and posts **Tap to start voice input**; the user taps the notification and unlocks if necessary. The service does not bypass Android background activity launch or lock-screen restrictions. Detection has an eight-second background cooldown. The notification has **Stop listening**, which disables both listening settings. The microphone service is non-sticky and is not started by boot receivers; reopen GalaxySSI after reboot or process termination to resume an enabled mode.

Physical validation checklist: enable on each watch, verify the microphone foreground service and partial wake lock with the screen asleep, return to Settings and verify the lock is released, exercise Samsung speech and contact recording handoffs, and disable the mode to verify service cleanup. Spoken detection accuracy, notification-to-Samsung interaction and long-duration battery consumption need user testing on the actual watches.
