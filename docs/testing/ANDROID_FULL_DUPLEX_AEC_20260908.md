# Android full-duplex AEC integration

## Scope

- Branch: `fix/android-full-duplex-aec-20260908`.
- Android version: `1.1.2` (`888`). Desktop is unchanged.
- Physical device: Samsung SM-T575, Android 13 / API 33. No other phone was operated.
- Implementation: Android system/hardware AcousticEchoCanceler, not WebRTC AEC3.
- Do not describe an enabled AEC flag alone as acoustic acceptance.

## Audio path

The inline voice call now owns `MODE_IN_COMMUNICATION` and a communication
output device. It prefers a connected communication headset, otherwise the
built-in speaker. The manifest includes `MODIFY_AUDIO_SETTINGS`.

Microsoft MediaPlayer playback, progressive Android TTS, and playback focus
use `USAGE_VOICE_COMMUNICATION` during the call. Ordinary Android TTS explicitly
resets its attributes so a previous voice call does not change later read-aloud
output. Inline capture and barge-in capture use `VOICE_COMMUNICATION`; the
barge-in recorder does not fall back to an unrelated microphone source.

The speaker and AEC microphone remain active concurrently during playback.
A detected utterance stops playback while retaining the microphone capture,
including its pre-roll. A 300 ms speaker-tail drain applies only when returning
to ordinary listening after playback/manual interruption; it is not the
full-duplex barge-in mechanism.

Hangup and background transitions release communication routing and restore
the prior audio mode/volume-control stream. Another active call is not taken
over. If AEC becomes unavailable, existing protection stops acoustic barge-in
instead of interpreting unprotected speaker audio as a new command.

## Physical test method

`AgentDuplexAecDeviceTest` uses actual TTS output through the tablet speaker and
actual microphone capture. It injects a bounded assistant transcript fixture,
not PCM audio or mocked AEC/VAD results. It verifies speaker routing, concurrent
capture, AEC state, absence of unintended input, hangup cleanup, and mode restore.
Provider and volume preferences are restored after the test.

Examples from `apps/android` (use only this device serial):

```powershell
adb -s R52R90282TY shell am instrument -w -r -e provider microsoft_edge -e class 'com.galaxyssi.chat.AgentDuplexAecDeviceTest#speakerOnlyDoesNotBecomeUserInput' com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s R52R90282TY shell am instrument -w -r -e provider microsoft_edge -e quietDurationMs 60000 -e class 'com.galaxyssi.chat.AgentDuplexAecDeviceTest#speakerOnlyDoesNotBecomeUserInput' com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s R52R90282TY shell am instrument -w -r -e provider microsoft_edge -e humanReady true -e class 'com.galaxyssi.chat.AgentDuplexAecDeviceTest#liveHumanSpeechInterruptsTheSpeaker' com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The human test requires a participant to speak only after playback starts. Do
not enable `humanReady` for unattended CI. Test teardown intentionally closes
the activity; tell the participant in advance and reopen the app afterwards.
This teardown must not be reported as an app crash.

## Initial measured results

- Targeted JVM regression: 61 tests, zero failures/skips.
- Speaker-only at maximum voice-call volume: Android TTS 1/1 passed (15 s).
- Microsoft TTS speaker-only: 5 passed, 2 failed (15 s each).
- The two failures immediately followed human participation. Their source was
  not recorded, so ambient/human speech versus residual echo remains unresolved.
  Preserve these failures; do not relabel them as passes or proven noise.
- After explicitly requesting silence again, four consecutive Microsoft runs
  passed, with no input turn and the microphone remaining active throughout.
- A final 60-second Microsoft run passed at maximum voice-call volume. It
  exercised the existing 50-second bounded recorder renewal and verified AEC
  recovery within one second with no new input. This does not claim gapless
  capture during recorder replacement. Log: `build/full-duplex-aec-60s-retest.log`.
- The first 60-second attempt failed in diagnostic-file export during teardown,
  masking its assertion. Raw telemetry showed a 50-second recorder boundary,
  not a detected utterance. Diagnostics now cannot replace the original failure;
  the long test permits one bounded renewal but still rejects input, prolonged
  AEC loss, and incomplete recovery. Original log is retained as
  `build/full-duplex-aec-60s.log` and is not counted as passing.
- One human Microsoft-TTS interruption passed. The participant confirmed speaking
  and hearing playback stop. Telemetry measured 81 ms from the detected-barge-in
  event to playback-stop completion; this is not speech-onset latency.
- Four lifecycle/regression device tests passed: background/resume, hangup,
  real incremental Android TTS returning to listening, and continued playback
  plus return to listening after deliberate AEC loss.
- Background/resume and hangup were rerun on the final installed build: 2/2
  passed, including explicit communication-mode release and reacquisition.
  Log: `build/full-duplex-aec-lifecycle.log`. The normal app was reopened after
  instrumentation and the crash buffer still contained no new fatal exception.
- Crash-buffer inspection showed no new fatal exception for these tests. The
  reported screen exit corresponded to explicit instrumentation teardown.

## Acceptance boundary

This establishes integrated system-AEC routing and initial physical functionality
on one tablet. It does not establish universal echo immunity. The two ambiguous
failures, longer/noisier sessions, different distances/rooms, Bluetooth/USB route
changes, other devices, ERLE measurements, speech-onset interruption latency,
and ASR transcription accuracy are not certified by these tests. No changes to
ASR model choice or unrelated UI are included.

Reference: [Android AcousticEchoCanceler](https://developer.android.com/reference/android/media/audiofx/AcousticEchoCanceler).
