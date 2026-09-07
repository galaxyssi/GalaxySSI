# Complex Video Acceptance

## Scope

Device acceptance: SM-T575 only. Android 1.0.39 (883), Desktop 1.0.35.
PR release metadata: Android 1.0.39 (883), Desktop 1.0.38, coordinated with parallel
PRs to avoid version regression. Device results below predate the final main
merge and metadata bump; they are not relabelled as a new device run.
Production pairing, Signal encryption, MQTT TLS and user data are preserved.
The route is coding Agent + Microsoft neural speech + Python/Pillow/FFmpeg, not a native video model.
Speech reuses the installed Edge TTS integration and requires network access. No
video service, model download or new TTS package is installed.

## Acceptance Matrix

| Case | Content | Delivery/player | Speech/synchronization | Result |
| --- | --- | --- | --- | --- |
| 30 seconds | Three 10-second digital-circuit scenes, Chinese speech/captions | Passed | Passed technical/timeline checks; binary pronunciation refinement noted | Passed on constrained fixed-layout prompt |
| 60 seconds | Six scenes, Chinese speech/captions, original offline voice | Passed | Passed technical/timeline checks | Passed after one visual correction; ASR is not exact-digit proof |
| 120 seconds | Long multi-scene explanation | Pending | Pending | Not run |

These cases do not establish support for arbitrary-length videos, photorealistic
generation, universal scientific correctness, or all device models. The current
storyboard contract supports 2-120 seconds and up to 16 scenes.

## Required Evidence

1. A new phone conversation submits the Chinese request through the normal paired
   Desktop connector. No fixture output replaces the real provider or transport.
2. The received attachment bytes match the advertised SHA-256. Export those exact
   bytes for inspection, not just the Desktop source file.
3. Android prepares and plays the attachment and seeks to the midpoint.
4. FFprobe reports duration/streams; FFmpeg decodes the entire received MP4.
5. Every narrated scene has recognizable Chinese speech. Offline cached ASR helps
   locate speech, but transcript presence alone does not prove semantic quality.
6. Inspect actual rendered frames and transcripts together, including both sides
   of scene transitions. Check captions, factual states, and unintended overlaps.
7. Source and 240p audio envelopes match the measured isolated speech clips.
   Maximum allowed alignment lag is 120 ms; minimum correlation is 0.75.
   Video start tolerance is 120 ms, planned end tolerance 500 ms; audio/video end
   difference must not exceed 250 ms. These are engineering gates, not a human
   perceptual-quality score.

## Fixes Under Test

- Voice projections namespace event IDs by run and use durable indexed replay
  deduplication. Reused producer IDs no longer collide across local projections;
  duplicate events beyond the 96-item recent window remain idempotent.
- Storyboards explicitly declare audio mode. Legacy checkpoints without it are
  replanned instead of bypassing narration checks.
- Desktop prepares bounded per-scene speech with Microsoft Edge TTS before
  invoking the rendering Agent. Chinese defaults to `zh-CN-XiaoxiaoNeural`;
  English retains the existing `en-US-AriaNeural` mapping. The renderer reuses
  measured WAV clips and a cue manifest instead of repeatedly discovering TTS
  inside its restricted child process.
- Speech requests have a 45-second ceiling and check task cancellation every
  200 ms while waiting. Timeout, empty audio or network failure is explicit;
  no silent fallback to a different voice. Completed scenes report real progress.
  The cue manifest records provider, voice, speech rate and measured timing.
- Speech gets a bounded rate retry if it does not fit. It is never truncated to
  claim a successful result. No fitting speech is an actionable failure.
- Verify stream timing and per-scene audio alignment both before and after 240p
  conversion. Check previews at delivery resolution and scene boundaries.
- While the coding Agent runs, track actual code, preview and encoded-file changes
  and report progress to the task manager. Static files, timestamp-only touches,
  empty output and encrypted checkpoint writes do not keep an idle task alive.
  The existing no-progress timeout is not increased.
- The production video route has a 30-minute total ceiling, still clamped by the
  user's task budget. Stage subprocesses receive the remaining budget rather than
  the generic 120-second chat default, and enforce it even for managed tasks.
  On a video timeout, terminate that child process tree, including render children.
  This larger bounded ceiling enables correction; it is not a speed improvement.

## Completed Regression Checks

Final PR preparation merged `origin/main` at `894fd1600`; conflicts were limited
to version metadata. After that merge, repository checks passed, Desktop checks
passed (29 tests plus structure), and the expanded Python selection passed
201 tests plus 5 subtests, including upstream transport/recovery clock coverage.
The earlier device runs below are retained with their actual tested versions.

- SM-T575 VoiceProjectionLedgerDeviceTest: 2/2 passed.
- VoiceAgentRunBridge JVM suite: 15/15 passed.
- Video, narration, progress, CLI execution, artifact ownership/delivery and
  rich-output and Edge TTS Python suites: 171 passed, 5 subtests passed.
- Desktop check: 29 passed; structure check passed.
- Real host speech helper: valid 2.658594-second Chinese WAV generated.
- Initial offline speech measurements above predate the Xiaoxiao switch. A real
  host Xiaoxiao test produced two valid mono 24-kHz WAV clips of 5.880 and 4.128
  seconds in 11.484 seconds total, including network synthesis and conversion.
  This single observation is not a general latency benchmark.
- The same first phrase at +20% rate produced a valid 4.896-second clip in 7.531
  seconds total. Default-rate audio was 5.880 seconds; no truncation was used.
- Real FFmpeg calibration at 6, 60 and 120 seconds passes waveform alignment before
  and after 240p conversion. Synthetic amplitude markers test timing only, not
  narration intelligibility, scientific content or phone delivery.

The real host helper check is not an end-to-end phone acceptance result.

## Real 60-Second Result

Case `narrated-60s-v1`, task `7a7b1ba6-60e8-37cf-b3e8-cc4daf745e2d`:

- Completed before deploying the Xiaoxiao switch; uses the earlier offline voice.
- Phone instrumentation passed in 1085.411 seconds; Desktop task 1045.863 seconds.
- Real received MP4: 1181693 bytes, 426x240, 12 fps, H.264/AAC, 60.011 seconds.
- SHA-256: `946ce2971c50e7b1666613996689be0cad24e7ad23861d33cfc6cb8ecd629653`.
- Phone hash, prepare/play/midpoint seek and full-file FFmpeg decode passed.
- Six 240p narration correlations range from 0.998973 to 0.999359. All best lags
  are zero at 20-ms resolution; audio/video end difference is 11 ms.
- All six intervals contain recognizable Chinese speech in cached offline ASR.
  Repeated digits and homophones are imperfectly transcribed; ASR does not certify
  exact pronunciation. Independent visual review approved the corrected output.
- The first review requested two missing storyboard explanations; the renderer
  corrected them before publication. Evidence is in the ignored
  `build/complex-video-evidence/narrated-60s-v1/` directory.

## Xiaoxiao Integration

Chinese video narration now uses `zh-CN-XiaoxiaoNeural` in the Desktop host,
not System.Speech or a TTS process launched by the coding Agent. Synthesized MP3
is decoded to mono 24-kHz PCM WAV for measured scene timing. The normal rate is
0%; only a clip that cannot fit its slot retries at +20%, still without truncation.
TTS outages fail explicitly and never silently replace the voice.

Regression coverage includes voice/rate selection, invalid rates, network error,
empty audio, in-flight cancellation, timeout cleanup, WAV conversion, stale
manifest removal, scene timing, and progress after actual clip completion.

The first SM-T575 attempt, `xiaoxiao-20s-v1`, completed on Desktop with verified
Xiaoxiao audio, but is not counted as a phone pass. The probe created a draft in
a separate transcript-store instance while the Activity retained its old context:
the request's Desktop conversation ID differed from the ID the probe was awaiting.
The probe now waits for Activity hydration, uses the Activity's store, opens the
new conversation and asserts its context binding before submission. A fresh
end-to-end run is required; no old result is substituted into a passing report.

The updated probe APK built successfully and was installed only on SM-T575.
Fresh case `xiaoxiao-20s-v2`, task `26a95782-d304-3211-b907-4248dd2e9d58`, passed:

- Matching phone/Desktop conversation and turn IDs; no fixture response or media.
- Both scene cues use `zh-CN-XiaoxiaoNeural`, normal rate, measured speech durations
  3.216 and 3.168 seconds. The render script reuses those WAV clips unchanged.
- Desktop generation/review 446.047 seconds; phone instrumentation 467.335 seconds.
  These are full Agent-task times, not TTS synthesis latency or MQTT-only latency.
- Received MP4: 341058 bytes, 426x240, 12 fps, H.264/AAC, 20.011 seconds.
- SHA-256: `e0d34ae81d7d9edf0e1ba9de0ea2affe21af9209121437a7b3656f00f74f6a84`.
- Actual phone bytes match the advertised hash and fully decode without errors.
- Playback/preparation/midpoint seek passed. Separate fullscreen device test
  passed in 3.835 seconds, including no autoplay, width/aspect constraints,
  double-tap fullscreen and preservation of playback position/state on return.
- Two compressed narration correlations are 0.999052 and 0.998365, with zero best
  lag at 20-ms resolution; audio/video end difference is 11 ms.
- Cached offline Chinese ASR found speech in both intended intervals. Visual
  review approved the actual frames; manual frame inspection found matching
  binary states and captions without overlap.
- Generated evidence is under `build/complex-video-evidence/xiaoxiao-20s-v2/`.

The running Desktop has this integration. Android application code did not need
another change or reinstall for the voice switch; only its opt-in test APK was
updated. The separate 120-second real-phone case remains unverified.

## Real 30-Second Result

Case `narrated-30s-v4`, task `aecc2b17-feed-3e78-bccc-1a0ccb976abe`:

- New request submitted from SM-T575 through the paired Codex connector.
- Device instrumentation passed in 756.445 seconds; Desktop task took 736.288
  seconds, with `stall_count=0`. The difference includes startup, delivery, polling
  and player assertions; it is not a measurement of MQTT bandwidth alone.
- Received MP4: 388602 bytes, 426x240, 12 fps, H.264/AAC, container 30.016 seconds.
- SHA-256: `fe6186238bad573f3a771c1bb3f7835bee1ef67c6c21639ea6505fcae71394a8`.
- The received bytes fully decode, prepare, play and seek to the midpoint on SM-T575.
  Normal chat-page touch playback was also checked outside the instrumentation overlay.
- Three compressed narration correlations: 0.999111, 0.998220, 0.999184. All best
  lags were zero at the 20-ms envelope resolution; audio/video end difference 16 ms.
- Cached offline Chinese ASR found the expected explanations in each 10-second
  interval. Homophone transcription differences are not treated as factual speech
  errors. Binary 10 was spoken as Chinese "ten" with the explicit binary qualifier;
  planning guidance now asks for digit-by-digit speech for clearer instruction.
- Fixed-layout frames show binary states, the AND truth table and half-adder outputs.
  This prompt explicitly excluded decorative transitions; earlier unconstrained
  attempts and their failures remain documented below.

Same-host stage durations: storyboard 33.075 s; local narration 5.560 s; coding,
previewing and render self-correction 614.124 s; independent review 75.919 s;
compression/final verification 3.720 s. The coding stage is the dominant latency.

Evidence is local under `build/complex-video-evidence/narrated-30s-v4/`, including
`phone.mp4`, `phone.json`, `phone-audit.json`, `verification.json` and normal-player
screenshots. Generated media is intentionally not committed.

## Failed or Interrupted Attempts

- Initial baseline encountered a duplicate local event ID SQLite constraint crash.
  The device regression tests above cover the resulting fix.
- Task `89aa9d8e-6751-380a-8d00-1c768d8972b7` was interrupted when the user closed
  Desktop. Restart marked it failed rather than fabricating a successful result.
- Task `3acbf27c-e868-3fa3-8a44-be4c5a33f450` spent several minutes exploring TTS;
  observed SAPI/Edge test outputs were empty. It was explicitly cancelled before
  restarting with host-side speech preparation. It is not counted as passed.
- Task `2d865a3c-184d-3d4f-84dc-431deca6f6b3` produced measured local speech,
  animation code and previews. The Agent corrected missing subscript glyphs and
  an obstructing transition during preview inspection. However, file progress
  was not reported to the task manager: the 360-second stall watchdog triggered
  replanning, and the task ended without an MP4 after 442.545 seconds. This is a
  failed end-to-end attempt, not a successful preview-only result.
- Task `4e430b04-44e2-32c6-90e3-32b16dc61ef8` avoided false stalls (`stall_count=0`).
  Its initial 30-second source MP4 fully decoded and contained all three Chinese
  spoken explanations in their corresponding 10-second intervals. Independent
  visual review rejected an obstructing transition and ambiguous crossing wires.
  Automatic correction ran, but exceeded the old 900-second total budget; the
  blocking child did not enforce that deadline until it returned. Final failure
  occurred at 1127.256 seconds. No phone-delivery pass is claimed for this attempt.
  The following revision fixes budget propagation and child-timeout enforcement.

## Reproduction Tools

- `tools/testing/native-video-probe.gradle`: opt-in Android instrumentation source.
- `ProgrammaticVideoMqttDeviceTest`: `videoCase` and UTF-8 `videoPromptBase64`
  instrumentation arguments; exports JSON, screenshot and actual received MP4.
  `videoTimeoutSeconds` is bounded to 60-2100 seconds (default 2100) so the probe
  can observe the bounded production task and final transport/player checks.
- `tools/testing/capture_video_task_evidence.py`: opt-in capture for an explicitly
  owned test task before acknowledgement cleanup. Copies only allowlisted media,
  render code and selected verification fields; never exports state keys/tokens.
- `tools/testing/audit_video_evidence.py`: full-decode and cached offline Chinese
  ASR of the received MP4. Use `--require-narration --scene-seconds 10` for these cases.

Keep generated media and private test evidence under ignored `build/`, not in Git.
