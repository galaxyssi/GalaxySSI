# Android Health Privacy Controls

The native Health Center function page opens Privacy and Data. Derived
measurement views and selected self-reported profile context have separate
switches. They are enabled initially to preserve existing local behavior.
Disabling derived views does not disable direct record viewing or editing.
The screen also links to record export, the original library, and profile
management.

Online analysis and original-image eligibility are off initially. Original
images require online analysis to be enabled, and turning online analysis
off clears the image option. These preferences do not connect a provider,
send any data, or replace per-request consent. No health cloud integration
is introduced here.

## Enforcement And History

- Trend computation, source selection, drilldown, and explicit profile-context
  capture acquire purpose-scoped authorization before accessing data. The
  policy version is checked again with the completion record. A policy change
  invalidates an in-flight derived result, including an off/on transition.
  Visible trend screens observe policy changes and clear/reload their views.
- Explicit record export, original ZIP and single-original save operations
  record an attempt before writing the destination. A completed copy means
  the output stream closed successfully. A failed pre-copy audit does not
  remove an untouched destination.
- Scoped profile deletion records the selected counts and outcome. This
  does not constitute erasure of all health data or any external copy.
- Each access entry contains purpose, scope, time, and outcome. Scope may
  include date range, metric/field categories, requested counts, format and
  notes eligibility. It excludes measurement values, profile values, source
  names, paths, and record IDs. Interrupted attempts without a recorded
  result are not counted as successes. History does not cover ordinary
  record edits, all local reads, or export preview generation.

Policy and access entries are stored as independently authenticated
AES-256-GCM payloads in a dedicated SQLite database, with a separate Android
Keystore key. Row identity is authenticated; event IDs and timestamps remain
indexable metadata. History uses 30-entry keyset pages. This is not a
tamper-proof remote audit service or a change to existing archive keys.

Per-request cloud consent, provider enforcement, retention controls, and
broad archive/key/backup erasure remain future work.

## Validation

The 0.1.7.26 / Android 1439 build passes 264 focused JVM tests and 229
non-visual tests on Galaxy Tab Active3, with no skips. Device coverage
includes permission denial before access, changes during an in-flight
read, cancellation, ciphertext row binding, and a 65-event history.
No production health records were added and no camera hardware was used.
