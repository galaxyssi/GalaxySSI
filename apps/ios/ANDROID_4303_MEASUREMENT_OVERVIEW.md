# Android #4303: compact Health measurement overview

Reference: galaxyssi/GalaxySSI#4303, merge
`9c12460747e34d6955257a57a941196f712f3caa`.

## iOS mapping

- Replace the key-metric grid, separate attention block and repeated recent
  records on the Health landing screen with a compact measurement list.
  Keep the four base metrics; add other recorded metrics only when a current
  recorded reference or confirmed target proves them outside its bounds.
  Sort outside entries first, newest first, with deterministic catalog ties.
  Temperature and oxygen saturation remain outside this overview but remain
  fully available in the record center and metric catalog.
- Each row displays the value, unit, timestamp and actual saved source. Show
  the exact comparable range and whether it came from report evidence, a
  recorded reference or a user-confirmed target. Compare only exact values
  in the recorded unit, honoring inclusive/exclusive endpoints. Do not
  interpret unit-bearing/free-text references, convert units or invent
  default clinical ranges. Nonexact values remain not comparable.
- Color comparable values green within bounds and orange outside bounds.
  Unknown/unavailable comparisons remain neutral. For blood pressure, color
  only the explicitly bound component. Expand rows for a read-only exact
  measurement/revision detail and metric-specific saved history. Selecting a
  historical revision never edits it. An explicit Edit command uses the
  existing editor only for the live revision. Revalidate exact reading identity
  before editing; resume an existing draft rather than overwrite it. Missing
  base measurements open manual entry.
- Keep comparisons behind local-summary consent. Confirmed targets also
  require local-care and local-profile-use consent, current assessment,
  current scoped profile, target basis, exact record/revision, component and
  matching unit. Paused/closed, stale or revoked targets are not displayed.
  Bind the read-only comparison map to the archive rendered by the UI; do not
  reconcile care, mutate health data, send network requests or schedule work
  while rendering. Unknown comparisons are not reported as healthy readings.
- Pin Photo, Manual entry/Resume draft, Import file and Connect devices below
  the scrolling content using iOS 15 safeAreaInset. Use four columns normally
  and two at large text sizes. Photo opens the existing camera collection
  flow once per explicit navigation. File import retains existing consent
  and local/online choices; it does not send files automatically.
- Retain all previous functional destinations in More, including record center,
  reminders, Body Explorer, profile, originals, PDF text, crop, export,
  privacy, backup, weekly report, assistant and data/files. Move actionable
  source failures into Devices rather than dropping source recovery. Keep
  existing first-use profile/source steps and care summaries below metrics.

## Verification boundaries

Added nine XCTest source methods for recorded-bound endpoints, nonexact
results, unsupported references/units, report provenance, target identity and
components, outside-only ordering and permission/read-only behavior. Register
the range policy, native row/history view and tests in the Xcode targets.

Windows static project/grammar checks are not Swift type checking. Xcode,
XCTest, camera/device navigation, rendered SwiftUI screenshots and live device
validation were not executed here. Source Android device results are not iOS
evidence. No Android/Desktop edit, version bump, CI change or IPA is included.
This ports #4303 only; later Android overview changes remain separate.
