# Android Health Center

The user-supplied GalaxySSI Health Android V2 design contains 32 screens. It is an
interaction specification, not a dataset. Fictional names, measurements, scores,
device connections and generated analysis must never be installed as user data.

## Increment 1: Manual Measurements

- Native entry in My Agent > Common, with an isolated Activity back stack and no
  bottom navigation tabs.
- Empty state and a real overview backed by confirmed observations only.
- Blood pressure components in one observation; optional pulse; glucose, weight
  and heart-rate entry with explicit units, time and measurement conditions.
- Encrypted drafts, validated save, duplicate detection, optimistic revision
  checks, record details, revision history and deletion from current records.
- Indexed keyset pagination, 30 observations per page. Only the displayed page
  is decoded; the UI does not build the complete history in memory.

`HealthRecordStore` uses a separate private SQLite database with WAL, transactions
and per-row Android Keystore AES-256-GCM payload encryption. Health measurements,
notes and drafts are encrypted; record IDs, metric type, measurement timestamps,
revision numbers, deletion flags and a keyed HMAC deduplication digest remain indexing
metadata. This is field encryption, not whole-database SQLCipher encryption.
Associated data binds a payload to its database, identity and revision. Binary
plaintext buffers are wiped after encoding/decoding. Platform TextViews and JSON
Strings necessarily contain transient plaintext while displaying records.

Backgrounding drops health views and editor references. Foregrounding reloads
the current screen from storage. Draft fields are not placed in saved-instance
state. No health record is copied to the generic Agent transcript, memory,
Desktop, contacts or cloud providers by this increment.

Deleting a measurement hides it from current records while retaining encrypted
audit revisions. It is not a permanent erasure of health history. A separate
explicit privacy/erase flow remains to be implemented.

## Following Increments

Each independent feature is delivered as a separate pull request, with a new
version and focused validation before claiming completion:

1. Photo/file capture, durable originals, recognition and mandatory verification.
2. Structured CSV/JSON/XLSX import with mapping, conflict review and batch undo.
3. Metric catalog, time-window/source filters and true, gap-aware trend charts.
4. Original-file library, export configuration, save/share and verified backup
   restore with transactional merge and attachment integrity checks.
5. Personal profile, scoped health permissions, explicit erase and reminder
   preferences, deduplication/cooldown and notification delivery.
6. Health platform/BLE adapters with actual capability and synchronization
   status, not simulated connected devices.
7. Consent-scoped AI interpretation and versioned reports citing actual records.
8. Educational body exploration, clearly separate from personal measurements.

Screens from later increments are not exposed as fake working actions in the
first increment. Medical interpretation and default clinical thresholds are not
implemented in the manual-entry foundation.

## Verification

Domain tests cover missing data, numeric formats, units, time, conditions,
revision identity and duplicate normalization. Device tests use isolated database
names and verify persistence, encryption, authenticated identity binding,
pagination, drafts, conflicts, deletion and corruption behavior. No private
health data or remote providers are needed for these tests.

The first increment was built and installed on Galaxy Tab Active3 (SM-T575),
version 0.1.7.16 / 1429. Focused JVM validation passed 27 tests (12 health-domain,
10 control-center grouping/routing/render-cache and 5 backup-field regressions).
All 12 device tests passed (9 isolated-store tests and 3 native UI/lifecycle
tests), including a 125-observation pagination fixture. Native entry, manual
field units and system-back destinations were also checked on the device.
No fictional measurements were saved in the user's health profile. These results
do not claim completion of the remaining design screens or a full Android suite.
