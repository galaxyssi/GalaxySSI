# Android #4417 iOS Port

Pinned source: `071062afe8059506c9958906f708780d80437f55`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4417

## Review Scope

Base remains main. Inherits OPEN formal #4507, #4506, #4505, #4504, #4503,
#4502, #4501, #4500, #4499, #4498, #4496, #4495, #4494, #4492 and #4491;
none is assumed merged. Full main diff contains inherited work, not only this
feature. Incremental review base: `27cae906cbd1e9948d59e6191142b098178b927a`
(#4507 head). Only iOS files change; no Android/Desktop changes or IPA.

All seven original files have pinned hashes/dispositions: activity, quick-action
UI, measurements, two resource XMLs, device-test reference and Android version.
See ANDROID_4417_SOURCE_INVENTORY.json and ANDROID_4417_PORT_COVERAGE.json.

## Implementation

- Replace the two static whole-body links with the current structure's illustrated
  summary and Structure / Metrics / Trend actions directly under whole-body art.
  Preserve system context, a 38-point thumbnail, separate button identifiers,
  equal action columns, scalable wrapping labels and 48-point minimum hit heights.
  Existing artwork/hotspot navigation is unchanged.
- Remember root artwork hotspot/menu selection. Default/fallback to heart; retain
  valid focus in SceneStorage and recover it when the atlas loads. Quick actions
  keep focus and enter the same native detail with its selected tab. Trend is
  disabled for structures without associated metrics; Metrics retains the native
  no-metrics page. Other entry selections, controls and periods are not reset.
- Whole-body Ask Agent uses only the focused entry's public structure context,
  with a fresh structure selection, not the selected personal measurements.
- Pass an optional, backward-compatible entry-local trend reveal request to the
  existing metric-scoped trend view. ScrollViewReader targets the real chart
  after readiness/layout dispatch, rechecks foreground/permitted/unchanged/error
  state, then consumes the request. Manual tab changes clear obsolete requests.
- Existing record reload, permission gate, filters, invalidation and background/
  protected-data behavior are preserved. Empty iOS trends retain their existing
  empty state; missing/restricted data never receives synthetic teaching values.
  No new health-data reader or transport is introduced.
- Extract/register both original English/Chinese resource pairs and the new
  native Swift view in Xcode. Add XCTest SOURCE contracts for focus/fallback,
  supported/unsupported trend actions, retained controls/window, restoration
  and public prompt scoping. These tests were not executed.

## Source Verification And Limits

Passed seven original source hashes/dispositions, exact bilingual extraction,
focus/action/chart/permission source wiring and inherited #4414 source checks.
The existing record reload/permission logic is byte-identical to #4507.
Seven changed/added Swift files parsed without grammar errors after conditional
directives were removed. iOS project structure and whitespace checks passed.

No Swift type checking/Xcode build, Android tests, XCTest execution, simulator/
device launch, native chart visibility/denial, process recreation, large-label,
pixel or VoiceOver acceptance, and no IPA. Source contracts do not establish
native UI parity or certify inherited runtime/vector gaps. Formal PR status is
requested; Android verification is not iOS evidence.
