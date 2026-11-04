# Native Health Metric Catalog And Reported Results

This increment implements the classified/searchable h11 catalog and the result
semantics shared by manual measurements, reviewed imports and record details.
It does not complete trends, automatic clinical interpretation, device adapters,
exports or all 32 design screens.

## Catalog And Navigation

- One native catalog contains 27 metric definitions, grouped into cardiovascular,
  metabolic, sleep, activity, body, blood, liver, kidney, thyroid and urine tests.
- Daily, laboratory and all-record sections share the same encrypted observation
  system. Glucose is discoverable in both daily and laboratory catalogs; this
  does not duplicate its measurements or change their source.
- Search matches Chinese/English names, abbreviations, common aliases and unit
  notation. Category and section filters intersect the search. Zero matches do
  not fall back to unrelated records.
- Catalog rows query only the most recent observation for each matching metric.
  The all-record section uses parameterized metric IDs and 30-row keyset pages,
  not a full-history decrypt/filter operation.
  Multi-metric searches merge at most 31 candidate IDs per indexed metric before
  decrypting at most 31 final payloads. An unfiltered catalog uses the existing
  chronological index directly rather than sorting every metric match.
- A metric opens its actual record list, then the existing native manual editor
  or record details. The feature menu and overview link to the catalog. There
  are no bottom navigation tabs.

The initial catalog is an explicit supported set, not a claim to include every
medical test. Arbitrary custom clinical-code definitions are not implemented.
Existing OCR heuristics still recognize their original subset; the new metrics
are available for manual entry/correction and explicit structured mapping, not
claimed as automatically recognized from every report.
Numeric laboratory definitions accept common explicitly reported qualitative
labels/grades; arbitrary custom qualitative value-type selection remains an
open extension. Unrecognized text stays an invalid editable draft, not a guessed
negative or normal result. The dedicated qualitative urine definition retains
its literal nonnumeric label.

## Result Integrity

`HealthResult` distinguishes exact numbers, comparisons, ranges and qualitative
labels. Only an exact number exposes `exactNumber`. A bound such as `<0.1`, a
range such as `120-130`, and a label such as `negative` are not converted to an
exact threshold, midpoint, Boolean or zero. Reversed/incomplete bounds, invalid
number syntax and missing results are rejected rather than repaired silently.

Step counts require explicit nonnegative whole numbers; separators such as
`1,000` are rejected rather than guessed. Sleep duration may explicitly be zero,
but absence of an input remains missing. Existing vital-sign positivity rules
remain separate from laboratory result syntax. This is syntactic validation,
not a clinical normality rule.

Normalized numeric notation and the reported input notation are retained
separately. Typed JSON metadata must agree with the actual value. Canonical
duplicate identities distinguish bounds/ranges/exact values but ignore
irrelevant decimal formatting. Existing persisted enum names/ordinals and
numeric duplicate identities remain stable; no database reset is performed.
Legacy payloads without the added optional fields remain readable.

The report reference interval is optional source text, not a built-in population
range or diagnosis. Manual entry and structured mapping preserve it, revisions
retain its changes, and record details show it alongside the reported value.
Qualitative urine-protein results and explicitly reported laboratory labels may
have no physical unit. Numeric values, bounds and ranges still require an
explicitly supported unit. Original unit text also remains in
the import evidence; no clinical unit/value conversion is performed.

Reference-column formulas participate in the same explicit formula-cache
consent as other selected cells. Missing caches remain missing. Confirmation,
deduplication, source identity and batch undo use the existing transactional
import contract.

## Privacy And Acceptance

Reported notation, typed results and reference text live inside the existing
authenticated encrypted payload. The catalog does not send health data to
Providers, Desktop, contacts or generic Agent memory. Views, detached result
children and search inputs are cleared on stop; generation checks discard stale
asynchronous results. Recent-app screenshots are disabled on supported Android
versions. Managed parser/UI Strings are transient plaintext, not overwriteable
secure buffers.

Tests must cover the old record format, all supported metric definitions,
comparisons/ranges/labels, zero versus missing values, explicit units, reference
provenance, canonical deduplication, isolated encrypted persistence, filtering,
pagination, table save/undo and native search/lifecycle/input controls.

On 0.1.7.20, after the user unlocked Tab Active3, all eight existing native
Health Center/import/photo-draft UI tests passed. The empty photo-draft
screenshot was inspected; hardware capture was explicitly not started. That
does not prove the XLSX worksheet/mapping/time-preview UI or the new catalog UI.
Record this increment's final build, device and screenshot results separately.

See the complete [32-screen ledger](../architecture/android-health-screen-status.md)
for requirements still open outside this functional increment.

## Recorded Results

The final 0.1.7.21 / 1434 APK was cover-installed on Tab Active3 (SM-T575) without
clearing application data. Its SHA-256 is
`10b34ac617d9c3883fbba2ab3a43d9e6d0bb65cbe89415f92cd7d9c3c1252cfa`.
Desktop package metadata also advances to 0.1.7.21; no running Desktop process
replacement is claimed by this Android-health increment.

- The final offline app/test APK build and focused JVM selection succeed. All
  171 tests in 28 suites pass, with zero failures, errors or skips. New coverage
  includes 21 result-policy tests and nine catalog/mapping tests.
- All 119 selected non-visual device regressions pass in one final run, including
  the prior 106 health regressions plus 13 catalog/typed-result store tests.
  These exercise all 27 definitions, encrypted persistence, legacy payloads,
  reference revisions, unitless labels versus numeric unit requirements, mixed
  metric ordering/pagination, selective decryption and table save/undo.
- Before the final visual refinement, all 16 catalog store/UI candidate tests
  passed on the unlocked tablet. Its three UI tests exercise search/section
  selection, single selected mode, background view cleanup, recreation and a
  qualitative native input/reference field. A stable candidate screenshot was
  inspected; an earlier transition-frame screenshot is not visual acceptance.
- The final page replaces radio-circle styling with segmented navigation and a
  search-icon input. The tablet automatically locked again before final visible
  acceptance. Its final styled screenshot and row-to-record-list/back and
  all-record-page navigation acceptance remain pending a fresh unlock. Do not
  describe the earlier candidate screenshot as the final styled APK.
- Repository checks, Desktop structure checks and `git diff --check` pass.

All synthetic measurements/originals use isolated test databases/private roots;
native UI tests do not submit fictitious measurements. Hardware capture is not
authorized and was not started. On stop, catalog search/cursor state is cleared
along with result views; retaining navigation/search context without retaining
decrypted records needs further return-path acceptance rather than an untested
privacy exception.

These results are not full-repository CI success. Parent PR #3689's Android run
41718672992 reports 7,851 tests, five existing Agent failures and six skips
(native-tool catalog, process-state, two task-intent cases and the untrusted-
evidence boundary). Repository, Windows package, Desktop smoke and core-regression
checks pass there. This increment leaves those unrelated Agent policies intact.
