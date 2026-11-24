# Android #4444: menu-owned related lesson navigation

## Source and dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4444
- Merge: `556cd2c8e452fea8a299e80fc44e03471a7d14ca`.
- Incremental iOS base: `f0c936664048ac9d1908a481ac0b7a61da282ba9`, PR #4520.
- Nine original files: two production Kotlin, four Android device/helper references, two string XML, one version-only change. Source inventory/coverage JSON records every original hash and disposition.

## Native implementation

- Remove inline related rows below the player. Animation options contains Related animations only when valid destinations exist; label each destination with its localized entry and course title. Pause before options, dismiss the menu sheet, then perform the selected native navigation action from its dismissal callback. No arbitrary delayed tap simulation.
- Capture the originating course, precise paused phase and scroll before changing a target. Detail bindings and live phase keys distinguish entry plus navigation depth, so a target lesson for the same organ cannot replace the inactive origin's selection. Give player ownership the same navigation identity.
- Back restores origin selection/phase and scroll but retains the destination course's newly cached progress and entry-scoped numerical settings. Ignore writes from a child removed from the active path, including its late disappearance pause/commit. A related return offset takes precedence over an old research return offset.
- Persist bounded public navigation locations, source snapshots, destination IDs and active leaf selection together in SceneStorage. Validate schema, known entries/courses, contiguous depths, path/return counts and a 128 KB input limit; reuse the existing selection/model/course sanitizers. Reconstruct native links from the root and delegate ordinary-child restoration to the actual ordinary, research or standalone container.
- Retapping the selected detail tab does not pause playback or reconstruct selection. Compact controls ignore identical selections, while the selected Function control on a standalone model still returns to Function.
- Same 138 lessons, 313 routes, 151 valid current related edges and all existing numerical/privacy/rendering kernels. Chapter clock, lifecycle and existing chapter/evidence menu bodies stay exact.
- One exact translated heading pair plus one explicitly pinned positional-placeholder/punctuation format, two entries per locale. The neutral format is not marked `translatable=false` in Android; it is not counted as a translated pair or a source-declared scientific name. No iOS version bump.

## Verification limits

Source/resource/grammar/project/whitespace checks only. New native fixture sources cover same-organ and cross-entry return, independent destination progress, late-child writes, navigation restoration without the separate general selection cache, ordinary ancestor contexts, tab reselect and rejected unbounded/unknown/noncontiguous archives. They have NOT been executed.

Windows has no Xcode: no Swift type checking, XCTest, device/simulator, native menu interaction, Back gesture, recreation timing, scroll pixels, animation timing, screenshots or IPA. Original Android menu-window/emulator and moving-region tests are source references only, not reproduced iOS execution evidence. Restoration wiring and source fixtures do not prove native acceptance.

Historical audits now freeze unchanged player clock/lifecycle, old cache sanitizers and metric renderer rather than asserting the superseded inline links or globally shared entry binding. Earlier resource and model contracts remain checked. Full native navigation/restoration acceptance is still outstanding on an Apple platform.

## Review scope

Formal PR base is `main`, but this branch cumulatively includes preceding unmerged iOS work through #4520. It is NOT an independent #4444 diff against main. Review this port against the exact incremental base above; integrate predecessors in order or deliberately reconstruct integration. The entire Android backlog is not complete.
