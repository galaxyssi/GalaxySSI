# Android #4435: Guided Function Playback

Source: Android PR #4435, merge `83188e7ce30a174e766e68fcf4db6f751a046d7a`.

## Scope And Dependency

This formal iOS PR targets `main` and depends on the unmerged iOS #4511
and its predecessors. Its incremental base is exactly
`90abe3736bcf95a4ee2891e05d21bcc2a287842e`. The full main diff is cumulative,
not an independent #4435-only diff. No Android/Desktop code is changed.

All 39 original changed files are inventoried with source hashes and per-file
dispositions: five production Kotlin files, 30 test references (including the
test navigation helper and clock unit tests), two resource XMLs, Android version
metadata and the architecture document.

## Native Changes

- One monotonic integer-millisecond clock per player: five active seconds per
  chapter, fractional pause/resume, seek-pauses, stop at end, replay from start.
- Tapping the artwork or its accessibility action toggles the same playback as
  the play button. Complete localized chapters expand and seek to still frames.
  Segmented choices suppress only an identical redundant title.
- System/organ details have Structure, Function and My Measurements tabs.
  Existing models/inputs expand in the same Function scroll, separately from
  collapsed mechanism prose. Cells, tissue and fragments retain Simulation.
- Entry-local expansion persists. Old Simulation destinations migrate to the
  expanded Function section without dropping inputs or lesson state.
- A shared navigation-stack playback owner freezes the losing animation at the
  actual ownership-change uptime. Scene changes, preview and disappearance pause
  and commit. Reduced motion uses the same active clock with discrete artwork.
- Preserve original lesson catalogue, renderer assets, numerical models,
  research modes and personal measurement permissions. Agent prompts retain the
  current lesson and include numerical teaching context only while the inline
  system/organ models are expanded; collapsed, structure and personal values
  screens do not leak hidden teaching inputs. Pause synchronously before taking
  the preview snapshot, not on a later SwiftUI notification.
- Exact two-label English/Chinese resource import and Xcode membership.

## Verification Boundary

The scoped checker reproduces original hashes and bilingual resource deltas,
asserts clock/navigation/lifecycle wiring and unchanged model modules, and chains
the preceding source contracts. Added XCTest sources mirror clock boundary,
pause, seek/replay, ownership timestamp, cache migration and localized-caption
cases, but are not executed here.

Swift grammar parsing, project structure checks and whitespace checks are not
Swift type checking, an iOS build, XCTest, UI gesture/pixel/instance verification,
VoiceOver certification or device acceptance. Sampling uses the existing SwiftUI
timer architecture (30Hz lesson / 10Hz inline model); reduced-motion publishing
is limited to chapter transitions and precise paused snapshots rather than
Android's callback-at-deadline scheduler. No IPA or native tests are requested.
