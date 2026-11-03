# Native Health Trends And Revision-Bound Evidence

This increment implements the h12 trend foundation on the existing encrypted
health archive. It does not complete all 32 health screens, physical-device
adapters, automatic interpretation or large-history latency acceptance.

## Data And Calendar Contract

- The native catalog and overview open the selected metric's trend page. Periods
  are 7, 30 and 90 calendar days, plus an explicitly confirmed custom interval.
  Cancelling either date picker retains the previous period.
- Inclusive local dates become a half-open instant range at the selected time
  zone's day boundaries. A daylight-saving day is not assumed to be 24 hours.
- Units are selected explicitly and never clinically converted or mixed in one
  plotted series. The initial unit follows the latest actual scoped record.
- Sources are all records, actual manual records, or one selected original ID.
  Original choices use 30-item keyset pages and encrypted original metadata.
  Two files with the same name remain distinct sources. An unknown source is
  not relabeled as manual. Physical-device identities and health-platform/BLE
  cohorts remain work for h17-h20; no connected device is simulated.
- Only exact numeric values for every required metric component contribute to
  numeric aggregation. Comparisons, ranges and qualitative results remain
  readable records, not thresholds, midpoints or fabricated zeros. Other-unit
  and nonnumeric exclusions are shown separately. Optional BP pulse values do
  not share the blood-pressure axis.
- Means use decimal arithmetic. Minimum/maximum ties select the latest actual
  record, with ID ordering resolving equal timestamps deterministically.
- Calendar-day bitsets count recorded and numeric days separately. Missing days
  are not observations. The chart breaks connections across missing intervals;
  there are no clinical normality bands, risk scores or diagnoses.

## Bounded Reading And Coherent Results

Indexed metric/time/source queries read 30-row keyset chunks with one lookahead,
not OFFSET pages or a full-history list. The aggregate retains at most 120 plot
bins per required field and calendar-day coverage bitsets, rather than every
decrypted observation. Long intervals display their calendar-day bin width.
The source picker and record-cohort pages also display at most 30 rows.

The selected time window is still an O(N) authenticated streaming scan. Unit and
typed-result eligibility are checked after decryption; this is not a new indexed
unit query or precomputed rollup service. Progress is visible, work is off the
main thread and superseded/background reads are cancellable. No fixed total-row
truncation, constant-time claim or universal P95 latency guarantee is introduced.

Schema 4 additively creates a per-metric mutation-clock table. Tokens are opaque
UUIDs, not health values. Confirmed saves, edits and deletions update the clock
inside the observation transaction; moving a record updates both metric clocks.
Drafts, duplicates and rejected conflicts do not advance it. Import save/undo
publishes database-scoped change notifications only after the outer transaction
commits, coalescing writes in that transaction. Rolled-back clock values do not
produce a committed-change notification.

A scan compares its metric token before and after reading. A concurrent change
produces an explicit changed-data state and refresh action, never a mixed result.
After rendering, an event-driven metadata probe detects later changes and marks
the existing chart stale without repeatedly rescanning the archive. A probe
after publication closes the completion/event race. Unrelated metric mutations
do not invalidate the selected metric.

This is detection and explicit refresh, not a long-lived MVCC snapshot. A busy
metric that changes during every scan can require another refresh; automatic
infinite retries are not used.

## Points, Records And Privacy

Single-contributor and extremum points open a read-only encrypted audit revision,
not the current value after a later edit. That view retains measurement time,
conditions, source notation and links to the original, current record and history.
The immutable revision remains readable after ordinary soft deletion, consistent
with the existing audit contract; permanent erasure remains separate work.

A multi-contributor mean opens only its bucket/date/unit/source cohort, pinned to
the metric token used to calculate the point. A changed token stops paging and
offers return to the trend rather than silently replacing contributors. The
ordinary all-record list remains a separate view that can explicitly refresh.

Activities are non-exported. Bundles retain filter/cursor/identity metadata, not
clinical result payloads. Backgrounding cancels reads, unregisters observers,
dismisses source dialogs and drops chart models and result views. Managed UI
Strings are transient plaintext, not overwriteable secure buffers. Recents
screenshots are disabled where supported. No Provider, Desktop, contact or
generic Agent-memory health-data transfer is added.

## Verification Matrix

Domain cases cover empty and explicit-zero histories, missing days, decimal
aggregation, extrema/tie identity, units, qualitative/bounded/range exclusions,
BP components, manual/original source identity, half-open dates, both DST
transitions, timezone bucketing, long-window plot bounds and cohort filtering.

Isolated Android store cases cover raw and eligible keyset pages, original-source
paging, cancellation, selective corruption handling, encrypted revisions,
intent metadata, clock invalidation, concurrent mutation, cross-metric edits,
schema-3 migration and post-commit database-scoped observation. Fixtures use
unique databases/private roots and clean only their own data.

Native Android canvas tests inspect nonblank BP series at phone and tablet
widths, missing-day gaps, actual point taps, vertical-drag nonselection and
background model/pixel clearing. These are actual View/Canvas tests, not browser
screenshots or proof of every physical-device/cohort navigation path.

Visible UI acceptance requires an unlocked tablet. It must separately exercise
native controls, period recreation, cancelled custom dates, catalog navigation
and record return paths. No synthetic measurements are submitted to the user's
archive, and hardware camera capture is not part of this authorization.

## Recorded Results

The 0.1.7.22 / 1435 app and test APK build succeeds offline. All 195 focused JVM
tests in 29 suites pass, with zero failures, errors or skips. This includes 24
new trend-domain tests and the prior health/shared-input regressions.

The APK was cover-installed on Tab Active3 (SM-T575), retaining application
data. Its SHA-256 is
`2b4178f22734cd5f95d7bb776b3b9e76010505c4ae98556e65761f13cb3d693a`.
Desktop package metadata advances to 0.1.7.22; replacement of a running Desktop
process is not claimed by this Android feature.

- All 142 selected non-visual device tests pass in one final run (89.401 seconds)
  with no failed or skipped instrumentation statuses. This includes the prior
  119 health regressions, 18 new trend-store tests and five native canvas tests.
- Phone/tablet-width pixel checks verify both BP series, a real missing-day gap,
  tap identity, drag nonselection and cleared chart models/hit targets.
- After a fresh user unlock, all 14 selected visible UI/lifecycle tests pass
  (13.89 seconds), with no failures or skips. Coverage includes the prior eight
  entry/manual/import/photo-draft checks, three final catalog tests and three
  trend controls/lifecycle tests. Custom-date cancellation retains the selected
  period; background cleanup drops chart models; recreation restores the period.
- Final 0.1.7.22 catalog and empty trend screenshots were pulled and inspected
  at the tablet's 1200x1920 resolution. Search/segmented controls and native
  period/source/unit/aggregation controls render without overlapping text.
  The empty chart is an honest empty state, not a synthetic patient series.
  Generated screenshots remain local build evidence, not committed health data.
  Full populated point-to-audit/cohort and catalog-return interaction acceptance
  remains open; store/canvas tests do not substitute for those complete routes.
- Repository, Desktop structure and whitespace checks pass. No synthetic
  measurements were added to the user's health archive; no camera was opened.

An earlier compilation attempt failed on a click-lambda variable shadowing bug;
the fix and successful final build do not erase that failed-attempt log.
The initial UI run also exposed three expression-body test methods with non-void
return types; JUnit rejected that class. Explicit Unit return types fix discovery,
the test APK rebuild succeeds, and the final 14-test run includes all three.
The main APK/hash is unchanged by that test-only correction. No keyguard bypass
or camera capture was used. The user's separately requested 20-minute screen
wake task only targets this tablet and never unlocks it or changes lock settings.

This is focused validation, not full-repository CI success. Parent PR #3690
still has failing Android gates while its repository, Windows package, Desktop
smoke and core-regression checks pass. Its run 41727680794 reports 7,881 tests,
five failures and six skips: the native-tool catalog, process-state, two
task-intent cases and the untrusted-evidence boundary. Keep those unrelated Agent
failures distinct from this increment's results and keep the complete health
ledger open.
