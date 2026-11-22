# Android #4302: simplify Health overview

Reference: galaxyssi/GalaxySSI#4302, merge
`95f66854b2dd9839e25f28566458ecb1bf5f1d9e`.

## iOS mapping

- No additional My health title is introduced below the navigation bar.
  Keep the existing Health Center navigation title and first-use state.
- Move weekly reports, Health Assistant and Data and Files from standalone
  overview shortcut rows into the navigation bar More menu. Each destination
  retains its existing functional screen and native navigation/back behavior.
  Use the existing iOS 15 programmatic NavigationLink pattern, not newer-only
  navigation APIs or inert menu links. Assistant recording still uses the
  existing editor presentation.
- Make the shared overview metric set exactly blood pressure, sleep duration,
  resting heart rate and steps, in that order, shown in two columns. Steps are
  recent only on the current local day; the other three use the existing
  seven-local-day window. Future/deleted readings remain excluded. Temperature
  and oxygen saturation remain in the full catalog and records but never
  increase the key-metric overview coverage denominator or numerator.
- Put ordering in the Needs attention section, visible for existing records.
  Provide changes-first, reviews-first and most-recent modes with deterministic
  timestamp/ID ties. Persist only this non-health display preference.
- Project existing actionable sleep episodes, visible report/table reviews
  (bounded to 30) and selected-source failures without writing archives,
  creating episodes, scheduling notifications or sending anything. Reuse the
  existing review enabled/snoozed/handled policy. Require current sleep
  evidence and permission; hide completed, stale and snoozed sleep episodes.
  Open existing reminder/review/recovery screens from the attention entries.
  Read failure is shown as unavailable, not as a healthy-source assertion.

## Verification boundaries

Add four XCTest source methods for sorting/ties, four-metric coverage and local
step freshness, read-only projection and sleep revocation/staleness/snooze.
Update the previous overview test to assert the new metric identities.
Register the new projection file in the app target. All UI text uses existing
localization APIs with Chinese resources and English fallbacks.

Static project/Swift grammar checks are not Xcode type checking. Windows cannot
validate SwiftUI layout, navigation gestures, XCTest execution or real device
screens here. No pixel-identical UI claim, Android/Desktop changes, version
bump, CI modification, IPA packaging or automatic merge is included.
