# Collaboration team panel

## Scope

Android 1.4.39 (1124). Presentation-only changes; the Desktop executor, scheduler,
transport, research workflow, and task recovery policies are unchanged.

- Merge member count, team state, execution count, and waiting count into the
  existing top member strip. The strip expands and collapses the team roster.
- Show each member's current research action, provider/model, status, elapsed
  time, latest progress, and existing process disclosure. Include unassigned
  members and dynamically recruited members; never confuse an attempt with a
  person.
- Move the collaboration settings entry inside the expanded panel. Member,
  workflow, provider, and model settings use full-width bottom sheets.
- Keep published replies and approval/control messages in the transcript; move
  status-only rows to the panel. Do not rewrite or delete stored messages.
- Reuse persisted execution timestamps. Completed or paused work does not tick;
  reconnection is distinct from proven execution. Existing process long-press
  controls still provide pause, resume, stop, and team details.
- Recycle member rows and bound the expanded viewport, preserving room for the
  conversation and composer. A collapsed panel creates no detailed member rows.
  No model calls, new polling, or database access are added to the rendering path.

## Regression coverage

`CollaborationTeamPanelPolicyTest` covers unassigned/dynamic members, current
attempt precedence, cold-history restoration, cross-conversation isolation,
published reply preservation, waiting/recovery counts, paused/completed states,
process details, and a 1,024-member roster.

`CollaborationTeamPanelDeviceTest` uses isolated display fixtures, not model calls.
It covers the collapsed header, explicit action labels, running/completed clocks,
full-width settings, persistence after recreation, a 1,024-member scrolling list,
and continued access to the composer. Fixture conversations are removed after
the test; the previous conversation is restored.

Existing collaboration page and timing device tests are updated to open the
new status panel when inspecting in-progress members.

## Commands

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*Test' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --console=plain
```

Native memory compilation uses the already-built local native library.

## Results

- Final build: 628 unit tests in 50 suites, zero failures, errors, or skips.
  Both debug APK targets built successfully.
- S26U (SM-S9480): all five display-only device tests passed again on the final
  APK, in 53.265 seconds. The installed version is 1.4.39 (1124).
- Verified collapsed/expanded panel, explicit actions, current-phase priority,
  prior-run isolation, full-width settings, running/completed durations,
  recreation, 1,024-member recycling, keyboard clearance, existing search
  details, and unchanged published replies. Test conversations were removed and
  the previous conversation restored. No real model tasks were started.
- Actual screenshots were inspected. The settings screenshot waits for the
  native transition animation before capture.
- Kotlin source-size and staged whitespace checks passed.
- The repository-wide check remains blocked by pre-existing i18n violations in
  unrelated files and local runtime artifacts. Those files were not changed or
  included in this PR. The initial non-elevated check also encountered the
  existing Desktop pytest-cache permission issue.

This is UI acceptance, not a new scientific, real-model, or recovery benchmark.
Desktop and other connected-device software were not changed.
