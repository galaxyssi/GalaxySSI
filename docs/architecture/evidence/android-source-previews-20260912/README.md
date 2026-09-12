# Authenticated source preview evidence

## Scope

- Device: SM-T575 only; no S26U operation, model download, model replacement,
  user-data export, uninstall, reset or re-pair.
- App: Android 1.1.95, version code 981. Desktop and iOS are unchanged.
- Initial verification base: `b323f0b3e`, including merged PRs #3013 and #3014.
  Main subsequently advanced to `4ea021860` (PR #3015); that change is also
  integrated in this branch, with rebuilt-artifact validation recorded below.
- Corpus: the retained synthetic `test-knowledge-backup-cf7de680-e44d-499f-87e6-39e03f35389b.db`,
  containing 10,001 real encrypted source rows and bodies.
- Content: numbered Chinese fixture titles, summaries and bodies; default cloud
  access DENY and agent access LOCAL_ONLY. No semantic model is configured by
  this scale test.
- Only derived previews are reset to simulate schema 8. Original items/chunks
  remain intact. All three passes verify the original ciphertext SHA-256:
  `95b4ea281213622780074760c1fa15afccce5ded8c1594ea55c76b7c7718eb1e`.

## Files

`summary.json` and the three CSVs were pulled directly from the device.
Each CSV contains 201 page observations, including preview hits/misses and body
decode counts. The total is 30,003 verified source visits, not 30,003 distinct
sources. No plaintext application data or full database is included.
`main-integration/` contains a second complete set for the final rebuilt artifact.

`legacy_build.csv` includes one-time authentication and preview construction;
the two `ready_*.csv` files use persisted encrypted previews after reopening.
The first page and every later page are retained, including outliers. The two
ready passes contain 402 pages, all below 200 ms in this measurement. The legacy
pass is slower and is not presented as meeting that latency target.

## Reproduction

Build and install App/test APKs on an explicitly selected test device. Use the
retained corpus created by `KnowledgeBackupScaleDeviceTest`, or retain an
equivalent isolated corpus from that test first. Do not substitute a production
database or reset the application.

```text
adb -s <test-device> shell am instrument -w -r \
  -e retainedKnowledgeFixture <retained-test-knowledge-backup-name.db> \
  -e resetDerivedSourcePreviews true \
  -e class com.galaxyssi.chat.KnowledgeSourcePreviewScaleDeviceTest \
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The test drops only derived preview tables in its explicitly named synthetic
fixture. It checks all rows, exact descending order, unique membership, access
policy, stable ciphertext, no body decoding, and cleared operation keys. It
reopens before each pass and after page 100. Both ready P95 values must be below
200 ms; evidence is written before evaluating that gate.

## Real process death

Use a new name matching `test-knowledge-backup-preview-recovery-[a-f0-9]{24}.db`
with instrumentation argument `knowledgePreviewRecoveryFixture`. Run these
methods separately, in order:

1. `KnowledgeSourcePreviewRecoveryDeviceTest#prepareUncommittedWriteAndTerminate`
2. `KnowledgeSourcePreviewRecoveryDeviceTest#verifyNextProcessRollsBackAndUsesPersistedPreviews`
3. `KnowledgeSourcePreviewRecoveryDeviceTest#cleanup`

The first command intentionally reports `Process crashed.` after committing 65
source/preview pairs and writing a 66th pair inside an uncommitted transaction.
A marker records the old PID and ciphertext hash before termination. Verification
requires a different PID, exactly 65 surviving sources/previews, the unchanged
original hash, 65 preview hits, zero misses/body reads and no retained key.
The marker and synthetic database are removed by the final explicit cleanup.

This run used old PID 25728, passed verification in 0.206 seconds and cleanup in
0.101 seconds. These are instrumentation method times, excluding Android startup.
No whole-device or cross-device recovery claim follows from this test.

## Initial verification

- Paired scale test: PASS, 123.541 seconds, 3 x 201 pages.
- Actual process death: expected preparation termination; verification/cleanup PASS.
- Full App/test build: PASS, 15m14s, Gradle default heap 8 GiB.
- JVM: 3,755 tests across 538 suites; zero failures/errors, five existing skips.
- Repository guard: PASS.
- APK 16 KB alignment: PASS for all 74 Android AArch64 libraries.
- Shared device regressions: PASS 138/138, no skips, 1,026.145 seconds. Includes
  backup/restore, schema recovery, keyed FTS, native vector replay, concurrent
  mutations, source pagination, model lifecycle and ten preview security cases.
- Additional permission-snapshot test: PASS 1/1, 0.372 seconds. A changing
  caller-owned list is read once; body, header and rebuilt preview agree.

App APK SHA-256:
`ebd25d856bdfc90380b037b99a489a1fd3ae2621725f1aabe8ce7c39a320beaa`

Scale/recovery/shared test APK SHA-256:
`ba0ffbd0c92b1ba7dc0b932b7d74e1def44053a02b9b8664ceb0bdd8ce7d8655`

Additional snapshot-test APK SHA-256 (only the new test was added):
`ed924956d27e5068961506aa960dc6b9b2a88910ff90f6505cab51adbfa5c7cd`

## Latest main integration

Main `4ea021860` adds image-delivery code, not changes to the knowledge storage
or preview implementation. The initial shared-regression results above belong
to the preceding artifact, not a claim that those 138 cases were rerun against
the later build. Final rebuilt-artifact verification:

- Full App/test build: PASS, 11m41s.
- JVM: 3,765 tests across 539 suites; zero failures/errors, five existing skips.
- Focused preview security and permission snapshot: PASS 11/11, 6.735 seconds.
- Full paired scale: PASS, 127.219 seconds; all 10,001 original sources verified
  in each of three 201-page passes, with the same unchanged ciphertext hash.
- Ready page P95: 35.268077 ms and 31.646769 ms. All 402 ready pages below 200 ms.
- Missing-preview construction P95: 816.803269 ms, still outside that target.
- Real process death repeated with a new isolated fixture: old PID 28377,
  65 committed sources retained, the uncommitted 66th rolled back; verification
  PASS in 0.259 seconds, cleanup PASS in 0.110 seconds. The new-PID assertion,
  ciphertext hash and all preview hit/miss/body/key invariants passed again.
- Final APK 16 KB alignment: PASS 74/74; repository guard PASS.

Final App APK SHA-256:
`ccc5a15f3b6e4c405753b49e4fc78c83ca870af4f4045c97e9a13e62eccdc1b1`

Final test APK SHA-256:
`b0a6b72fb6261cd628254629070159f765ec9f16b4818ebf431282f492cf3987`

## Limits

These results do not prove 100M+ capacity, cold legacy pages below 200 ms,
end-to-end UI latency, provider latency or complete Run Kernel/DAG acceptance.
Source sharding, bounded single-source bulk operations, background preparation,
explicit corrupt-preview repair and full-scale NDK retrieval remain open.
