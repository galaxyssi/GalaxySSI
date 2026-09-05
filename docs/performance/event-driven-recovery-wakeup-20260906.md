# Event-driven reply recovery wakeup verification - 2026-09-06

Scope: Android only, following the verified remote observation and paged final
reply recovery PRs. Desktop source/package stays at 1.0.9. Default test device:
Samsung S20 Ultra SM-G9880, serial R5CN319CESA. S26U and SM-T575 were not operated.

## Local gates

- Android JVM: 57 passed, zero failures/skips. Wake coordinator 11, result paging
  10, remote observations 7, Run recovery coordinator 15, identity policy 5,
  control-plane executor 9.
- The wake tests include 10,000 events coalesced during an in-flight observation
  and eight concurrent caller threads. Maximum active observation count was one.
- Android debug and instrumentation APK builds passed. An intermediate build
  found a test-only LongArray/mapNotNull type error, fixed by using a Sequence;
  no production behavior was changed for that fix. Final incremental build 1m57s.
- Repository checks and git diff whitespace checks passed.
- Fetched origin/main before submission: 6e5da5157, already an ancestor of this
  branch. This phase is stacked on the preceding paged-result recovery PR.

## S20U verification

- Android 1.0.14 (versionCode 860), installed using adb install --no-streaming -r.
- Original first-install time remains 2026-09-05 23:09:22; update time is
  2026-09-06 04:17:02. No production uninstall, data clear or identity reset.
- Instrumentation: **14 passed, 1 skipped, 0 failed**, 6.412s total. The four new
  tests use isolated encrypted pending preferences: reconnect discovery without
  a Handoff, 81 pending records read as 32/32/17 bodies, reopen/removal semantics,
  and main-thread responsiveness while an IO observation remains suspended.
- The prior three result paging, three recovery ledger and four cloud transport
  cancellation tests also passed. The opt-in live paired Desktop query is skipped;
  the runner's OK (15 tests) includes this skip and is not fifteen passes.
- Measured wake callback: 0ms at elapsedRealtime millisecond resolution. This
  means below this sample's resolution, not zero computational cost or a P95 SLO.
- One cold Activity launch: 1,419ms; ADB wait: 1,424ms. These are not message
  delivery, full recovery, model TTFT, list-load or percentile measurements.
- Existing conversation and answer are visible after cold launch. The displayed
  22-second answer is from an earlier test, not a new provider benchmark.
- Crash buffer was empty. All 88 native APK entries match the 1.0.13 APK byte
  for byte, including ASR/QNN. No inference code was changed.
- Removed only the instrumentation package and the temporary device screenshot
  after verification. The production App remains installed and open.

## Artifacts

- APK: build/galaxyssi-recovery-wakeup-1.0.14.apk, 410,413,867 bytes.
- SHA-256: D245805D9FCD0BCF663D9F50013D87B853904BFF73C38F17C3D1CFC664A01159.
- Test APK: build/galaxyssi-recovery-wakeup-tests.apk, 1,528,225 bytes.
- Test SHA-256: E6997BFD865FD719E5C3BC72DB4DCDECC9803D47A644D1161F64267A54C7D043.
- Build log: build/recovery-wakeup-android-build.log.
- Device log: build/recovery-wakeup-device-tests.log.
- Repository log: build/recovery-wakeup-repository-check.log.
- Crash log: build/recovery-wakeup-crash.log.
- Screenshot: build/recovery-wakeup-s20.png.

## Acceptance boundaries

Real paired result-loss/reconnect recovery is still pending because the new
Desktop is not running. The previously blocked automatic Desktop deployment was
not retried through another mechanism. Device tests use injected observation
callbacks and isolated persistence, not a live provider or a real broker failure.

The legacy pending-identity key snapshot remains O(N) metadata, although bodies
are decrypted in pages of at most 32. Indexed durable pending-intent storage,
failure-result replay, persistent page checkpoints and complete cross-runtime
recovery remain subsequent work. No overall reliability goal or five-second
recovery SLO is claimed complete by this phase.
