# GalaxySSI AR Glasses

A standalone Android application alongside `apps/watch`. The initial adapted device is QIDI VENUS / VEN-A0 (serial `MTT20M170108`), running Android 11 / API 30 with an approximately 640 x 360 dp landscape layout and `armeabi-v7a`. The tested device provides microphone and audio output but no system speech-recognition or TTS service for ordinary apps. The Watch app requires API 33 and cannot be installed directly on this device.

## Implemented

- Pure-black windows and backgrounds suit the optical display and prevent launcher icons from showing through a genuinely transparent Android window. The centered GalaxySSI title, waveform, wake phrase, replies and controls share one viewing area.
- VENUS touchpad navigation: one-finger tap activates the highlighted control, two-finger tap goes back, a short left swipe selects the next control, and a short right swipe selects the previous one. Focus uses blue and white outlines; selected conversations scroll into view. The app supports multitouch, relative motion, mouse buttons and directional-key events. External gallery and settings apps handle their own touchpad input.
- A small English Vosk model listens for `Hello Hello`, spoken together or in two parts within seven seconds. After waking, each recording lasts up to two seconds and local multilingual Whisper Tiny Q5_1 recognizes commands and questions. Recognized text is sent after 1.5 seconds; continued speech resets that timer. The microphone remains enabled while the app is in the foreground, including before Agent setup. Prior VENUS measurements took roughly 7-51 seconds for short utterances and sometimes returned empty results, so this is not established as usable real-time recognition. Decoding has a 30-second bound to avoid monopolizing the device CPU.
- Wake-prefixed commands cover photos, video recording, back, gallery, home, Wi-Fi/Bluetooth settings, volume, battery, time, send, cancel, reading replies and conversation navigation. Exact localized phrases live in `VoiceCommandCatalog.kt`. The in-app camera records video without audio so offline recognition can continue. Media is saved in `DCIM/GalaxySSI`. Ordinary apps can use only operations exposed by Android, not arbitrary ADB shell commands.
- Foreground, network-connected glasses automatically advertise phone setup without requiring the glasses settings page. On the phone, open My Agent > Devices > Configure AR glasses and compare the six-digit code on both devices. The glasses support voice confirmation. Existing or new cloud settings are tested on the phone and transferred with encryption, reusing the watch's certificate-bound TLS protocol with a separate `_galaxyssi-glasses._tcp.` discovery service.
- The phone can prepare an Agent/provider/endpoint/model/key draft before the glasses join Wi-Fi. After discovery and code confirmation, the draft returns to the transfer confirmation page. The glasses show the synchronized Agent and model. Only cloud Agents can currently be synchronized; the Desktop remote-Agent connection runtime has not been ported.
- Initial Wi-Fi setup scans WPA2-compatible networks on the phone or accepts a hidden SSID manually, then creates a QR code from the entered credentials. Scanning requires precise location permission and the phone Location setting; manual input remains available after denial. On the glasses, use the localized scan-Wi-Fi command or camera-page button, inspect the SSID, and confirm. Android Wi-Fi suggestions request the connection; first-use system approval remains necessary and immediate connection is not guaranteed.
- Direct calls use user-configured OpenAI-compatible, Anthropic Messages or Gemini generateContent HTTPS endpoints, with bounded context/response size and request cancellation.
- Android Keystore AES-GCM protects API keys and conversation records. System TTS is preferred when available; otherwise the app reuses Microsoft Edge online speech synthesis from Android/Watch. Online synthesis sends the spoken text to that service.

## Build and Install

Requires JDK 17/21, Android SDK 36, NDK 29 and CMake 3.22.1. Put the SDK path in untracked `local.properties`. The first build downloads and verifies the English Vosk wake-word model and multilingual Whisper Tiny Q5_1 into the Gradle cache, not Git.

```powershell
cd apps/ar-glasses
.\gradlew.bat :app:assembleDebug
adb -s MTT20M170108 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s MTT20M170108 shell am start -n com.galaxyssi.glasses/.MainActivity
```

On first launch, Vosk and Whisper Tiny are copied from the APK into private storage and loaded; later launches reuse those files. Wake-word listening is foreground-only. Recognition can work offline; phone configuration transfer requires the same Wi-Fi, while model replies and Edge speech synthesis need Internet access.

## Current Scope

This version provides glasses voice chat, common device operations, phone-generated Wi-Fi QR codes and cloud-model configuration. Watch Desktop QR pairing, Signal messaging, contacts, web tools and background wake have not been ported; phone-side remote-Agent pairing therefore does not yet apply to glasses. Ordinary apps cannot bypass first-use Wi-Fi approval or camera/microphone permissions, and a system `VOICE_COMMAND` entry point is not continuous wake-word support. Without API credentials, local recognition and device operations remain available but model replies do not. When VENUS ADB connectivity is unstable, camera, Wi-Fi QR and end-to-end voice behavior still require device verification after reconnecting.
