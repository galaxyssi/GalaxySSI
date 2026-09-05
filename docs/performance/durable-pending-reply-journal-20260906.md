# Durable pending reply journal verification - 2026-09-06

Scope: Android pending-delivery persistence and recovery paging. Default physical
device: Samsung S20 Ultra SM-G9880. S26U and SM-T575 were not operated. Desktop
source/package remains 1.0.9 and the running Desktop was not replaced.

## Gates and fault tests

- Android JVM: 63 passed, no failures/skips. Six new codec cases cover exact
  source/scope validation, Unicode, legacy task fallback and delimiter collisions.
  The preceding 57 recovery/identity/control-plane tests also passed.
- Debug and instrumentation builds passed. Repository checks passed.
- Final S20U instrumentation: **32 passed, 1 skipped, 0 failed**, 266.211s total.
  All 18 new journal tests passed, alongside four wake, three paged-result, three
  recovery-ledger and four cloud-cancellation tests.
- The opt-in live paired-Desktop observation is skipped. The runner's OK (33 tests)
  includes that skip and must not be reported as thirty-three passes.
- SQL abort triggers verify rollback when the turn-head insert fails, rollback
  of linked retirements when completion fails, and restart after a migration-marker
  failure. Other cases cover stale legacy files, migration/update races, corrupt
  ciphertext retention, wrong-conversation successors, linked retry semantics,
  concurrent callers, deletes during paging and encrypted on-disk values.
- Initial instrumentation had three failures in the older wake test's isolated
  Context, which incorrectly prefixed an already absolute database path. The test
  context was fixed without weakening production checks; the full 33-test suite,
  including the entire 10,000-record case, was rerun. The original log is retained.

## 10,000 pending records

Each run created its own isolated journal with 10,000 individually committed,
Keystore-encrypted body/turn-head transactions. The database was closed/reopened,
every page was read, and all 10,000 IDs were compared to the exact descending
sequence. Production recovery never collects this complete list; the test does.

| Measurement | Initial run | Full rerun |
| --- | ---: | ---: |
| Individual durable writes, total | 190,835ms | 161,564ms |
| First 32-body page after reopen | 273ms | 283ms |
| Warm 32-body page P50, 30 samples | 267.06ms | 259.55ms |
| Warm 32-body page P95, 30 samples | 287.78ms | 290.07ms |
| Verified stored/ordered records | 10,000 | 10,000 |

Both query plans report SEARCH TABLE pending_deliveries USING INDEX pending_active
(source_id<?), not an OFFSET scan. The DB file observed during the large test was
5,263,360 bytes, plus WAL/SHM. One process sample during the initial write run was
213MiB resident; this is a sample, not a measured peak. These two runs are not a
before/after comparison with the old implementation and do not establish a
production UI, model-response or end-to-end recovery percentile SLO.

## Installation and App smoke

- Android 1.0.15, versionCode 861, installed with adb install --no-streaming -r.
- First-install time remains 2026-09-05 23:09:22; update time 2026-09-06 04:42:41.
  No production uninstall, data clear, identity reset or re-pair occurred.
- Before testing: MemAvailable 5,944,572 KiB; available /data storage 174GiB.
  Existing legacy pending preferences were 65 bytes; large datasets were isolated.
- Cold Activity launch samples: 1,408ms before the full rerun, 1,815ms afterward.
  These are Activity launch times, not time to first message or percentile claims.
- Wake callback measured 1ms in each instrumented run. The original conversation
  remains visible afterward; its displayed 22-second reply is from an older test.
- Crash buffer empty. All 88 native APK entries match 1.0.14 byte for byte;
  ASR/QNN binaries and inference paths are unchanged by this phase.
- Test databases/prefs were cleaned by their isolated teardown. Only the test APK
  was uninstalled; the production App remains installed and open. The temporary
  device screenshot was removed after pulling the local verification copy.

## Artifacts and integration

- APK: build/galaxyssi-pending-journal-1.0.15.apk, 410,422,343 bytes.
- APK SHA-256: 202848E0043C3FE37712F62E81A33BFEB3242730521AF7E45266B8124EF747D9.
- Final test APK: build/galaxyssi-pending-journal-tests.apk, 1,537,112 bytes.
- Test SHA-256: 189F26618208EE65511195BFF59E62CA83855E09382E9237D80F525CC89FED52.
- Logs: build/pending-journal-android-build.log, pending-journal-test-rebuild.log,
  pending-journal-device-tests.log, pending-journal-device-metrics.log,
  pending-journal-device-test-context-failure.log, pending-journal-crash.log,
  pending-journal-repository-check.log (all under build/).
- Screenshot: build/pending-journal-s20.png.
- Latest main 801763419 was fetched and merged before submission. Its new merge
  commit contains the already inherited PR #2816, so tested source content did not
  change during this integration. This phase is stacked on PR #2818.

Real paired recovery against the new Desktop is still pending. The blocked Desktop
deployment was not retried through a bypass. Failure/cancellation-result replay,
persistent result-page checkpoints, one commit spanning terminal/transport/Run/
transcript stores, and the full reliability goal remain incomplete.
