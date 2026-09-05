# Paged final reply recovery verification - 2026-09-06

Scope: Android and Desktop. Default test device: Samsung S20 Ultra SM-G9880,
serial R5CN319CESA. S26U and SM-T575 were not operated.

## Local gates

- Backend Run kernel/recovery regressions: 132 passed, including 14 new archive
  and normal-delivery integration cases.
- Existing MQTT task/turn routing regressions: 23 passed.
- Android JVM regressions: 37 passed (result paging 10, recovery observations 7,
  recovery coordinator 15, identity policy 5); no failures or skips.
- Repository checks passed. Android debug and instrumentation builds passed in
  6m48s. Desktop Windows portable packaging passed.
- An intermediate backend run hit the existing watchdog test's one-second wait
  and teardown subsequently removed its temporary database while the watchdog
  was still exiting. No production watchdog or timeout was changed in this PR.
  The entire 132-test suite passed on rerun; the intermediate failure log was
  preserved as `build/result-recovery-backend-load-flake.log`. This is not proof
  that the timing-sensitive test cannot recur under load.
- That existing watchdog case also passed five isolated rechecks (1.744s total),
  recorded in `build/result-recovery-watchdog-recheck.log`.

## S20U verification

- Android 1.0.13 (versionCode 859), installed with `adb install --no-streaming -r`.
- Original first-install timestamp remains 2026-09-05 23:09:22. No production
  package uninstall, data clear, identity reset or re-pairing occurred.
- Available memory before test: 5,880,828 KiB. Available data storage: 175 GiB.
- Instrumentation: **10 passed, 1 skipped, 0 failed**. Three new tests cover
  a multi-page Unicode reply persisted in an isolated encrypted inbox, reopen,
  duplicate redelivery/acknowledgement, and corruption rejection. The previous
  three recovery-ledger and four cloud-cancellation tests also passed.
- The opt-in live paired-Desktop recovery query was skipped. `OK (11 tests)`
  includes that skip; it must not be reported as eleven passes.
- One cold Activity launch: 1,453 ms (ADB wait 1,458 ms). This is not P95, TTFT,
  a full recovery latency measurement, or a new model-response benchmark.
- Existing conversation and answer remain visible in the final screenshot.
  The visible 22-second answer belongs to the previous test, not this run.
- Crash buffer was empty. All 88 APK native-library entries are byte-identical
  to the preceding 1.0.12 APK, including existing ASR/QNN libraries.
- The instrumentation package was removed after testing; the production App
  remains installed and open. The temporary device screenshot was removed after
  pulling the local verification copy.

## Artifacts and deployment boundary

- APK: `build/galaxyssi-result-recovery-1.0.13.apk`, 410,406,047 bytes.
- APK SHA-256: `A8B30C350836B9CCB3E373CCA42ABDFBADD00346212FE8E3D4D34788FE04A547`.
- Desktop package version: 1.0.9. Packaged archive module matches source SHA-256
  `CD561E0F4F622543EB0B14CA56A757C40DD0FB4AB1741C51BA3C22F5156BA0BA`.
- The portable package uses the installed local Python runtime. The existing
  optional rcedit warning leaves Electron executable file resources unchanged.
- The currently running Desktop was not restarted or replaced. Earlier automatic
  deployment was explicitly blocked by execution policy; no alternate shell,
  helper, tool or delegated task was used to bypass it. Real paired result-loss
  recovery remains pending until the new Desktop is running.

Logs: `build/result-recovery-backend-tests.log`, `build/result-recovery-routing-tests.log`,
`build/result-recovery-android-build.log`, `build/result-recovery-s20-device-tests.log`,
`build/result-recovery-repository-check.log`, `build/result-recovery-desktop-package.log`.
Screenshot: `build/result-recovery-s20.png`.
