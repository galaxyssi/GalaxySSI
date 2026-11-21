# Android #4325: Scoped Atlas Agent Actions

## Source and PR Scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4325
- Source merge: `3e7e4f48508119bd6594eb6fc023987d714c6936`.
- This independent main-based increment adds the public context policy, pinned personal-analysis policy, native trend integration, regression source and build condition. It does not copy the unmerged atlas or physiology implementations, change Android/Desktop versions, install a provider or produce an IPA.
- Atlas views and the generic snapshot/pause adapter are in https://github.com/galaxyssi/GalaxySSI/pull/4428. The opt-in `GALAXYSSI_ATLAS_AGENT_CONTEXT` condition selects this implementation only when the increment is included. Both app target configurations enable it through inherited `OTHER_SWIFT_FLAGS`; the separate #4430 physiology condition remains intact.
- Full functionality requires #4428 and this PR. Quantitative physiology context additionally requires https://github.com/galaxyssi/GalaxySSI/pull/4430. Organ images remain a separate increment in https://github.com/galaxyssi/GalaxySSI/pull/4429. Dependencies are functional and explicitly stated, not hidden as repeated predecessor diffs.

## Personal Values

The native trend view has an opt-in pinned `Analyze changes with Agent` action, enabled only by the atlas consumer. The duplicate inline action is removed in this mode; other trend screens retain their original inline action. Empty charts have a disabled action rather than a public anatomy-question fallback.

An ephemeral loaded identity is compared with the current metric, component, unit, source/device/origin, aggregation, interval, snapshot, calendars/timezone, comparison anchor/revision and parent atlas selection key. The parent key makes metric/period changes invalidate readiness even before the trend view's change callback reloads its day count. The identity is never serialized into public atlas state.

The action is unavailable without a completed matching snapshot, in the background, after access revocation, with changed data or with no plotted measurements. Reload and invalidation clear the identity first. Before presenting the existing scoped Health Assistant review, the existing flow reloads the archive, checks permission, timezone and exact cohort revisions, and validates the scoped result. This does not directly send personal records or start a public conversation.

Protected-data shutdown closes a reload gate before clearing chart, source/device and review state. This prevents state-change callbacks from repopulating data while the protected-data notification is being handled. Availability can reopen the gate and reload only while the scene is active. The existing encrypted archive and consent flow are reused, not replaced with Android's SQLite storage engine.

## Public Teaching

`GalaxySSIHealthAtlasAgentContext` accepts public anatomy and synthetic descriptors only. Values explicitly returns no public prompt, even with no anatomy/metric available. It cannot load a Health archive or initiate transport.

- Whole body keeps the general learning question.
- Simulation and Physiology include the selected mechanism's current four-stage position. Heart/cardio additionally include rate, stroke volume, current cardiac output and fixed-volume assumptions.
- Quantitative context must belong to the selected entry and is appended only on the active teaching screens. It carries the model's inputs, output, companion quantity, limits, equation and source from #4430.
- Drug research includes only its current half-life/elapsed-time example, assumptions and pharmacology sources; aging includes its evidence limits and aging/structure sources. Inactive teaching/drug/aging state is excluded.
- Invalid/nonfinite phase/cardio/elimination descriptors are rejected. Integer parameter semantics match the source.

The foundation pins public Ask outside the scroll area, requests playback pause, then reads a fresh per-entry snapshot and freezes the prompt string. A transient binding also blocks timer advancement during confirmation. Cancel/background/disappearance clear preview state without automatically restarting playback. The existing explicit confirmation, new `body-atlas` conversation, owner-bound one-use capability and empty-attachment submission remain unchanged.

## Verification Boundaries

- `npm run check:ios` and `git diff --check`: static checks only.
- Static scope/i18n audit passed: all changed files are under `apps/ios`, Chinese remains in localization resources, the app target's Debug and Release configurations receive the context condition, and approval retains the existing permission/cohort-revision checks. The action's Chinese label matches the Android XML.
- `git merge-tree --write-tree` succeeded against each of #4428 (`225736e5d`), #4429 and #4430, without changing the worktree or merging those PRs. This proves absence of pairwise text conflicts at those heads, not native execution.
- Swift grammar parsing covers new context/action/test sources and the changed trend view. Conditional foundation adapters are checked in the supported feature-condition combinations. This is not Apple SDK type checking.
- Regression XCTest source covers stage/cardio context, inactive/foreign model exclusion, drug/aging source boundaries, no public Values fallback, invalid synthetic descriptors, frozen prompt values, control/selection identity changes, loading, background, permission revocation and empty charts. **Not executed**, per request.
- No XCTest suite, simulator/device run, Xcode build, IPA, real-provider response or follow-up acceptance was performed on Windows. Android's opt-in live-provider acceptance was also explicitly incomplete in the source PR; its device results are not presented as iOS evidence.
- No credentials, pairing, authorization policy or user's health data are changed. Native layout, lock/background timing, actual consent presentation and configured-provider handoff still need Apple runtime acceptance before claiming device validation.
