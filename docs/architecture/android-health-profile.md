# Native Self-Reported Health Profile

## Design Scope

The Android V2 h21 page is a single, explicitly self-owned profile, reached from
the health function page's profile/preferences section. It keeps the existing
native header/back/grid navigation, quiet page background and no bottom tabs.
The header identifies self-reported information, not verified laboratory data.
No example name, birthday, sex, height, diagnosis, medicine or allergy is
installed into the user's archive.

Optional basic fields are name, ISO date of birth, sex for medical reference,
height with cm/in units, and physiological context. Sex is explicit; not provided
and prefer-not-to-say are distinct. Missing information does not mean a normal
finding or absence of a condition. Heights use exact decimal arithmetic; these
self-reported values do not become measured height records or silently replace
measurements. No age, sex, stage, dose, health score or clinical conclusion is
inferred.

History, medication/supplements and allergy information are separate paged native
lists with individual edit/save/delete flows. Medication dose and timing are
user-supplied text, never automatically calculated or adjusted. Long notes are
bounded per entry, but there is no fixed total entry-count truncation. Each list
uses an indexed 30-row keyset page and a category version; concurrent category
changes require reload instead of mixing page versions.

## Storage And Conflict Rules

`health_profiles_v1.db` is independent of observations, original files, exports
and generic Agent memory. Basic facts, each background entry, each draft and
opaque version clocks have independently authenticated encrypted payloads using
the existing Keystore-backed application cipher. AAD binds the database, self
ownership, row kind, identity and version. Indexed field/category IDs, timestamps,
opaque tokens and counts are not a claim of completely hidden database metadata.
There is no whole-background JSON document or retained table of superseded facts.

Basic fields use per-field optimistic versions. A change to a different field
does not reject an independent edit; a stale edit to the same field cannot
overwrite a newer value. Normalized no-op basic saves preserve dependency tokens.
Background edits/deletes require the original entry token and immutable category.
Invalid multi-field saves roll back atomically.

Incomplete input may be saved as an encrypted draft without becoming confirmed
context. Basic edits require the page's explicit save action; background entries
have their own save actions. Cancelling a basic-field editor restores the previous
draft. Opening an untouched editor does not create a draft. Unsaved drafts survive
Activity/background recreation via encrypted storage, not plaintext Bundle or
widget state. Edit fields request no personalized IME learning and disable
autofill/view-state serialization. Backgrounding dismisses dialogs and drops
decrypted views/models.

Whole-profile deletion previews basic-field, background-entry and draft counts,
checks the exact preview versions and deletes those facts/drafts transactionally.
Measurements, originals and export files are explicitly outside that operation.
A new generation token prevents an old Activity, queued callback or draft from
resurrecting cleared information. Active editors observe this generation change
and drop old views. Current-row deletion is not advertised as forensic flash,
WAL, backup or Keystore-key erasure; the broader h22 privacy/erasure goal remains.

## Analysis Dependencies, Not Automatic Model Access

`HealthProfileStore.capture(fields, entryIds)` requires explicit selections and
returns only those self-reported facts, their provenance and opaque dependency
tokens. Empty selection returns no facts. Category pages also carry a dependency
stamp. `isCurrent` checks generation and the used field/entry/category versions;
unrelated facts and unsaved drafts do not invalidate an explicitly selected
context. Missing-then-added-then-cleared facts cannot match an old absence token.

These internal APIs are **not** cloud authorization or automatic Agent context.
There is still no health AI/report consumer that stores and renders these stamps.
The later h13/h14/h16 increments must consent-scope the data, persist the actual
used stamp and check it before publishing or reusing an analysis. A working
profile store alone does not prove stale-analysis presentation in those pages.
Family members are not inferred from contacts or silently mixed with `self`.

## Validation And Remaining Work

Policy, isolated device-store and native UI tests cover this increment. Debug
instrumentation can choose only a UUID-named `health-profile-test-*.db`, through
non-exported Activities; release ignores this override. No path or alternate
owner is accepted. UI fixtures use isolated databases and wait for Activity
workers to stop before deletion, not fictitious information in the real profile.
Final validation on 2026-11-04 for Android 1438 / 0.1.7.25:

| Evidence | Result |
| --- | --- |
| Offline app/test-APK build | Passed |
| Focused JVM regression | 255 tests in 32 suites, zero failures/errors/skips |
| Tab Active3 non-visual regression | 218 tests passed in 113.431 seconds, no skips; 26 new profile cases and one CSV byte-fidelity case |
| Unlocked native UI/lifecycle regression | 28 tests passed in 26.692 seconds, no skips; seven new isolated profile/editor cases |
| Visible screenshots | Actual profile basics and scrolled health-background sections inspected; no overlapping text/controls |
| Repository, Desktop structure and staged whitespace | Passed |
| Cover installation | Version 0.1.7.25 / 1438, no reset/uninstall |

The installed debug APK SHA-256 is
`5161d527c87167be558149124f2bdcdef0f3a1587f62aae775b7580565458870`.
Ignored build evidence: `health-profile-final-validation-2.log`,
`health-profile-device-tests.log`, `health-profile-ui-tests.log`,
`health-profile-final.png` and `health-profile-background-final.png`.
The earlier mixed-source candidate failures are retained separately; they are
not substitutes for the frozen-source build and final Android regression.

Still open: actual consent-scoped AI/report integration and stale-result UI,
profile inclusion in verified portable backup/restore, health-specific global
permissions/auditing/key erasure, explicit family-profile authorization, and
large-history/high-write-rate resource benchmarks. This is not completion of the
complete 32-screen design.

## Related Cross-Platform Regression

Reviewing parent #3693's CI found an additional CSV newline regression beyond
the five existing Agent failures. Measurement CSV now disables quoted-cell newline
normalization in the writer; its test reader also explicitly uses CRLF record
separators without modifying quoted-cell text. JVM and Android cases inspect the
actual quoted bytes for CRLF, LF and lone CR. The record separator remains CRLF.
This preserves user annotations rather than hiding the Linux-only failure by
loosening the assertion.

Main includes #3693 at `2af884225`; its preceding full Android CI ran 7,940 tests
with six failures and six skips. This change addresses the identified CSV case,
not the five pre-existing Agent catalog/state/intent/evidence cases. The new
focused/device passes do not assert full repository CI success.
