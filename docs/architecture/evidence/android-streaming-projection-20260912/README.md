# Android streaming projection evidence

- Date: 2026-09-12
- Device: SM-T575; no S20U or S26U installation or interaction in this phase.
- App: 1.1.98 (984), confirmed by Android package manager after `adb install -r`.
- App APK SHA-256: `398f24dbf3de0d1ed86df3138065c4b8a148a0ce704474760f407453aed8c45e`
- Test APK SHA-256: `56c1022ca7be5267fe674ded9acda1b557e8d5264dcd47765f487fb67b6ba7a4`
- Upstream base: `22b632a09`; fetched again before submission.

## Results

- Final `assembleDebug`, `assembleDebugAndroidTest`, `testDebugUnitTest`: passed.
  Full JVM report: 3,779 tests / 541 suites / 0 failures / 0 errors / 5 existing skips.
- `ObsidianKnowledgeProjectionDeviceTest`: 14/14 passed, 216.331 seconds.
- `ObsidianStreamingScaleDeviceTest`: 1/1 passed, 281.736 seconds including setup
  and independent result verification; measured export itself was 277.768 seconds.
- `check-repo.js`: passed, including the English source-text guard.
- `check-android-16kb.js`: all 74 AArch64 libraries passed.

The scale test reuses
`test-knowledge-backup-source-revision-7d7ae32a605d0a6bf9487023.db` without seeding,
deleting, or rewriting its 10,001 canonical rows. The database was 52,641,792
bytes before this run. Before installation the device reported 1,653,080 KiB
available memory; that is a baseline system reading, not an export peak.

The test compares every expected rendered chunk through the complete output
digest, validates the written file again, verifies 20,002 authenticated body
reads, checks the original ciphertext fingerprint, and reopens the database.
The generated synthetic note is removed afterward; the encrypted fixture remains.

## Boundaries

The source is synthetic and retained from the preceding phase. These results
prove this 10,001-row export, not 100M capacity or an under-200ms full export.
Buffer/fan-in limits are algorithmic, not measured total process RSS. Destination
SAF failure is not claimed to be atomic. Process/phone reboot, vault UI rendering,
real-model latency, cross-device coordination, and other projections' scaling
remain outside this acceptance. ASR, QNN, models, and transport were not changed.
