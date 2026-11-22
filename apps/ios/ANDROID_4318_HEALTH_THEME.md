# Android #4318: unified native Health pages

Source: https://github.com/galaxyssi/GalaxySSI/pull/4318

Android merge inspected: `464ca9c5a4e7dbea2fc49a225bd27089afa12cf7`.
Compared the manifest's 37 Health activities, feature menu, common toolbar/row
helpers, day/night themes, button/input resources, Sources retry, and the
Catalog/Data Files/Originals/Profile/History/Camera/Manual-editor changes.

## Feature navigation

`GalaxySSIHealthFunctionsView` replaces the old long popup with the same 14
ordered entries: Care, Actions, Record Center, Originals, Manual Entry, Records,
Catalog, Weekly Report, Assistant, Sources, Data and Files, Profile, Privacy,
Body Explorer. No duplicate Health Center entry or section-heading duplicates.
Each entry uses its existing native workflow and the same owner-scoped records.
Manual entry still resumes a saved draft. Independent NavigationLinks preserve
Back navigation rather than replacing one active destination in place.

The Center ellipsis opens Functions. Catalog, Data and Files, Profile, Sources
and Originals provide the corresponding Functions access from their own screens,
including when reached through another workflow. The scoped environment carries
only a view factory; it does not create a new Health Center or change accounts.
One explicit AnyView boundary terminates the recursive navigation type graph.

Earlier tools remain reachable: Trends through measurement/catalog details;
PDF text and crop from Originals' More menu; Export/Backup from Data and Files;
Movement from Sources; Activity Comparison beside the overview date; last
measurement removal from Privacy. Original navigation keeps restoreRecordsFile
attached to the existing records scope. No records, files or preferences erased.

## Shared style coverage

`GalaxySSIHealthTheme` supplies the Android day/night accent (#006C56/#87E6BF)
and command ink (white/#07352C), semantic native iOS surfaces and text, centered
inline navigation titles, plain native lists, and focused/disabled input states.
Inputs and explicit prominent commands use a minimum 48-point touch height and
8-point corners. Feature rows retain native disclosure, Dynamic Type and stable
IDs; icon commands have accessible names/tooltips. No global UIKit appearance,
forced color scheme or changes to non-Health screens.

The shared modifier is attached at Health screen/modal boundaries, including:

| Android activity family | iOS page boundaries |
| --- | --- |
| Center, Catalog, measurement history, revision, trends and comparisons | Center and its scoped destinations; Catalog/Metric details; Overview history/Record; Trend; Activity/Period comparison and picker |
| Capture, Camera, Table | Import, Selected Files, Photo Capture, table import/source, report context/review/jobs/vision/crop/PDF previews |
| Original library/export/history, record export, Data Files, Backup/Restore | Originals and save/ZIP history; Measurement Export; Data Files/history; Backup and restore views |
| Body, Profile, Background, Privacy | Body Explorer; Profile and Background editor/picker; Center Privacy and deletion/removal history |
| Sources, Connect/rationale, Bluetooth, Sync | Sources; native HealthKit import/coverage/recovery; Bluetooth/session history; Motion settings |
| Assistant, Care, Actions, Visit, Encounters, Follow-up, Documents, Instructions | Health Assistant, Care/Plans/Series/Targets/Profile scopes/Questions/Research authorization; Actions/reminders; Visit/Encounter/Journal; Documents/Instructions/review dialogs |
| Reminder and Weekly | Recording/Sleep/Review reminders, their evidence/details, Weekly Health Report |

Android Health Connect/service-specific UI remains the existing native iOS
HealthKit/CoreMotion workflow; this is not an Android runtime port. Camera's
system capture UI remains system-owned. Existing storage, permissions and
confirmation logic are retained.

## Sources failure recovery

Sources already had a reload action for unavailable records. The previously
passive source-attention/coverage read failure now also has a visible named Retry
command. It reruns the existing scoped source loader, clears failure on success,
and does not fabricate a successful source/coverage state.

## Verification

- `npm run check:ios`: project registration/static structure, not compilation.
- Modified/new Swift grammar parsing against parent baselines and whitespace
  review via `git diff --check`.
- XCTest source added for the 14-entry order/uniqueness/localization and adaptive
  primary color/ink contrast. Tests not executed, per request.

No Xcode build, simulator/device UI test, native screenshots or IPA on Windows.
Navigation-bar alignment, focus rendering, native keyboard interaction, visual
contrast and Back restoration need native validation; source coverage is not
proof of pixel equivalence. No Android/Desktop edits or version bump.
