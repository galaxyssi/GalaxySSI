# Android Edge TTS v2 handshake repair

## Scope

Android 0.1.6.17 (1393) upgrades Sec-MS-GEC from v1 to v2. Both ordinary
synthesis and paragraph prefetch use the shared protocol implementation.
Voice selection, audio format, neutral prosody, cancellation, ASR/QNN and
contact voice messages remain unchanged. Desktop and iOS are outside this change.

The checksum port is based on edge-tts revision
`b2ffbdd9f43f28f03cc939b5de0f3964aa62d60e`. Its LGPL license, source attribution
and rebuild information ship in Android assets/licenses. The adapted file is
separate from the general application code and is not a general-purpose hash.

## Failure evidence

On S26U, the installed v1 implementation returned HTTP 403 before synthesis.
An isolated same-device comparison changed only the GEC token and version to
v2: WebSocket upgrade returned 101 and synthesis produced a valid MP3 in
1,126 ms. This did not change the installed application's voice preferences.
The original playback code falls back to Android TTS after synthesis failure,
which accounts for the unexpected Google voice. Content-free debug diagnostics
now record the requested voice, protocol, error class and handshake status.
The fallback policy itself is unchanged in this narrowly scoped repair.

## Automated coverage

- A known-answer aggregate covers 1,000 distinct time windows from upstream.
- Explicit vectors cover the Unix epoch, five-minute boundaries, current dates,
  the 2038 boundary and 2100.
- Concurrent calls and a non-Latin default locale must produce identical tokens.
- Existing voice catalog, speech controller, chunk scheduler, cancellation and
  prefetch-related regression tests remain applicable.
- `MicrosoftEdgeTtsLiveDeviceTest` is opt-in with `-e edge_tts_live true`.
  It uses fixed synthetic Chinese text, never chat content or saved settings,
  and calls MicrosoftEdgeTts directly without Android system-TTS fallback.
  It verifies playback-start/completion callbacks for one direct utterance
  and two prefetched paragraphs.

## Reproduction

```powershell
cd apps/android
./gradlew.bat :app:testDebugUnitTest --tests '*MicrosoftEdgeTtsProtocolTest' `
  --tests '*MicrosoftTtsVoiceCatalogTest' --tests '*AgentReplySpeechControllerTest' `
  --tests 'com.galaxyssi.chat.voice.tts.*' :app:assembleDebug :app:assembleDebugAndroidTest
adb -s DEVICE install -r app/build/outputs/apk/debug/app-debug.apk
adb -s DEVICE install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s DEVICE shell am instrument -w -r -e edge_tts_live true `
  -e class com.galaxyssi.chat.MicrosoftEdgeTtsLiveDeviceTest `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Use the existing local Rust/NDK toolchain cache required by the Android build.
Do not clear application data, reinstall models, or re-pair devices for this test.

## Validation on 2026-10-25

- Build succeeded; 40 targeted JVM tests passed (including 1,000 independent
  time-window vectors within the protocol test).
- S26U (SM-S9480), Android 17, overinstalled version 0.1.6.17 / 1393.
- Both opt-in device tests passed against the live service; no fallback provider
  exists in the test path. Requested voice: `zh-CN-XiaoxiaoNeural`.
- Direct fixed utterance: playback started at 1,074 ms and completed at 4,122 ms.
- First prefetched paragraph: start 1,106 ms, completion 3,194 ms.
- Second prefetched paragraph: start 9 ms, completion 2,255 ms.
  These are per-utterance request-to-playback timings, not an end-to-end UI gap
  or a percentile performance guarantee.
- No voice/provider setting was changed by these tests. Existing system-TTS
  fallback remains available for other failures.
