# Android #3860: latest sleep evidence by default

Android reference: `009d2f5b07e625c36dbd8a046e7f080482e7376f`.
The main saved-evidence feature already shipped in merged iOS #3919, commit
`c2eb41d4afd6184a1d73d2527011b191ad515193`. Both the baseline/recent contributors
and sleep-only weekly report validate the selected saved snapshot. No duplicate
implementation of that feature is needed.

Android starts with its latest evidence selected (`showSleepTrigger = false`).
iOS instead defaulted to the initial evidence when an episode had been updated.
Track the explicitly selected initial-evidence episode in scene state, so an
unselected/new episode shows latest evidence by default. The segmented picker
still supports either snapshot; an episode with no distinct update shows initial
evidence without a redundant picker.

This uses a new scene-local key rather than interpreting the old opposite-polarity
key as an initial-selection preference. Old presentation selection is not migrated;
saved episodes, original/latest evidence and completion/snooze state are unchanged.
All three routes still capture the same selected snapshot. Permission/scene
clearing, contributor revision/window checks, weekly fixed-scope rejection and
privacy boundaries are retained. No health data is recalculated or accepted merely
because a different saved snapshot is initially displayed.

Validation: `node apps/ios/tools/check-sleep-evidence-selection.cjs` checks the
exact three-line production delta, Android default, unchanged evidence/report
backends and eight negative source mutations. These are source checks, not native
selection, SceneStorage restoration, Swift typechecking or device UI acceptance.
No native tests/build, notifications, CI inspection, IPA or Android/Desktop edits.
