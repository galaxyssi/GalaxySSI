# Android #4315: sampling-period measurements on iOS

Source: https://github.com/galaxyssi/GalaxySSI/pull/4315

Android merge inspected: `8dfc317f811ce0f5ad81a69e5351718c54f4e2fd`.
This change builds on the activity comparison and source-authentication work in
iOS PR #4419 (Android #4314), now merged into main.

## Behavior mapping

| Android change | iOS implementation |
| --- | --- |
| Date-row activity comparison entry | `GalaxySSIHealthCenterView`: action beside the date; existing step/cycling tiles and permanent history retained. |
| Latest/week/month sampling modes | `GalaxySSIHealthMeasurementPeriods`: Gregorian Monday-Sunday weeks and calendar months in the displayed time zone; exclusive end bounds and epoch floor. No upload, file, job or import-batch dates enter these groups. |
| Occupied-period selector | `GalaxySSIHealthMeasurementPeriodPicker`: 12 occupied periods per page with canonical date cursors; no fabricated empty periods. |
| Metric preview and abnormal filter | `GalaxySSIHealthMeasurementOverviewView`: all highlighted series, then recorded normal readings before missing placeholders, filling to five where possible. Earlier outside-range readings remain visible even when the latest is within range. |
| Inline all-record expansion | Same view: 30 readings per cursor page, measuredAt + UUID ordering, previous-page cursor stack. Period/filter changes reset pages; returning from unchanged details preserves the source view and current page. No separate upper All Records button. |
| A/B comparison | `GalaxySSIHealthMeasurementPeriodComparisonView`: latest occupied A and previous calendar B by default; either period selectable; week/month modes; missing values stay missing rather than zero. |
| Series and deltas | Metric + unit + condition + side grouping; actual latest reading and count, not averages. A minus B requires compatible source/device/context and components; unverified report/table methods suppress deltas. |
| Provenance | `GalaxySSIHealthMeasurementInput` includes authenticated secondary links at exact current revisions, report digests/removal state, and active table source bytes. Earlier provenance cannot silently become a verified manual-method comparison. |
| Historical trends | Reuses the #4314 exact-reading trend anchor and unverified-method protections, including the historical sampling-date window. |
| Retire batch-oriented comparison UI | Removes `GalaxySSIHealthMeasurementBatchesView`; old internal picker/comparison routes now open sampling-period screens. Original files, imports, jobs, evidence and readings are not deleted or migrated. Legacy model helpers remain for provenance continuity. |

## Concurrency and privacy

The existing main-actor encrypted archive loader remains in use. An owned,
value-only snapshot goes to a cancellable detached worker for grouping, source
digest evaluation and paging; no store, Keychain client or UI object crosses that
boundary. Publication revalidates owner, protected-data access, current readings,
sources, summary consent and its event identity. Changed inputs invalidate old
results. Backgrounding, identity changes and device locking clear rendered data.
Navigating to a detail cancels outstanding work without removing its source link.

Ordinary latest/all records remain accessible without local-summary permission;
period summaries, abnormal filtering, selectors and comparison require consent.
English fallbacks and Simplified Chinese resources cover the new screens.
Native SwiftUI controls target iOS 15 and adapt to narrow widths and Dynamic Type.

## Verification

Focused XCTest source covers calendar/year/DST boundaries, canonical keys,
sampling-vs-upload dates, series separation, earlier outliers, sparse and tied
cursor pages, missing periods, consent invalidation, authenticated secondary
sources and cooperative cancellation. Tests have not been executed, as requested.

Static checks: `npm run check:ios`, Swift grammar parsing, localization-key and
format-placeholder review, and `git diff --check`. These are not Swift type
checking or a native build. Windows cannot provide an Xcode build, simulator,
real-device run, or verified native screenshots; UI appearance and navigation
restoration still require native review. No IPA or runtime tests generated here.
