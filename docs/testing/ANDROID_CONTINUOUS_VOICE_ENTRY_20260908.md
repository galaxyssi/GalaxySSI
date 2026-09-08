# Android Continuous Voice Entry

## Cause

The installed Android 1.1.0 (886) did not include the inline voice implementation.
Its code remained uncommitted in the voice-interaction worktree, so merging the
existing PRs could not restore the composer icon.

## Integration

- Restore the waveform button on the right of an empty Agent composer. Drafts
  retain the send action; an active collapsed call keeps its voice entry.
- Open the existing inline panel with captions, waveform, pause/resume, keyboard,
  collapse, hangup, and explicitly authorized camera/screen context.
- Route recognized input through submitAgentGoal in the current conversation
  with the selected Agent/model. Reuse the existing ASR and TTS providers.
- Continue listening after reply speech; reject duplicate and stale callbacks.
- Stop capture/playback on background, end a call on navigation, and preserve
  dispatched Agent tasks on hangup. Foreground wake remains opt-in.
- Preserve main's remote-outcome recovery and latency telemetry. Do not import
  the old worktree's attachment storage, encryption, video renderer, Desktop,
  or model-routing changes.
- Expose only the existing player's pause operation for voice capture; retain
  the main branch's video layout, fullscreen behavior and save implementation.
- Android release version: 1.1.1 (887).

## Verification

- Main Android Kotlin/Java compilation passed.
- Selected voice, reply-speech and terminal-status suites: 456 tests passed,
  zero failures, errors or skips (JUnit XML reports).
- Android instrumentation test sources compiled successfully.
- Combined final Gradle run: BUILD SUCCESSFUL in 1m 34s.
- Kotlin source-size and whitespace checks passed.
- Initial integration compilation exposed the missing player pause interface;
  instrumentation compilation then exposed a missing camera test helper. Both
  were included before the successful final run.

The PR includes unit coverage for call generations, ASR ownership, speech
deduplication, TTS queue backpressure, acoustic-capture policy and wake matching.
Device regression sources cover the missing entry, panel controls, navigation,
backgrounding, captions and operation with legacy diagnostic flags disabled.
Device tests are restricted to SM-T575.

The original voice worktree's historical device results are not a verification
of this integration. This PR does not claim a new APK installation, live acoustic
accuracy, end-to-end model acceptance, or video-playback/voice handoff validation.
