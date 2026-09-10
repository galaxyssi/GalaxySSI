# Recover native effect facts before probing availability

## Scope

Android 1.1.45 (931). This updates the ordinary native registry's Run Kernel
effect recovery path. It does not implement the still-missing persisted outer
model-tool-loop transcript or claim full external-effect reconciliation.

Previously `AgentNativeToolRegistry.invoke` checked current tool availability
before looking up an existing scoped effect. After a network or dependency
failure, a committed success, recorded failure, or unfinished effect could be
reported as `tool_unavailable`. Recovery thereby lost the relevant execution
fact even though the encrypted journal still contained it.

The replay-store interface now provides `observe`: read the existing owner and
outcome without acquiring or completing an effect. The registry uses it before
availability/setup work. A matching completed result is replayed; matching
unfinished execution reports `effect_outcome_unknown` with its original owner
and no automatic retry. Only a new operation enters current availability,
schema validation, and atomic effect claiming. A concurrent claim winner is
handled through the same observation path.

Bindings still include tool/version/effect key and route/session/conversation/
goal/task/turn. Input digests must match. Cancellation and deadlines remain
honored. Unkeyed idempotent reads do not acquire an effect or consult this store.
No tool execution, model call, polling loop, queue reset, or approval bypass is
added by observing historical facts.

## Reproduction

Before the production change, `AgentNativeEffectObservationTest` ran eight JVM
tests, with five failures: completed result, recorded failure, unknown outcome,
and both completed/unfinished input-conflict cases were masked by availability.
The isolation and fresh-unavailable negative cases passed.

Evidence: `build/native-effect-observation-before.log`.

## Verification contract

- Full Android JVM suite, APK and instrumentation APK build.
- Repository, QNN packaging, and 16 KiB native-library guards.
- Encrypted ledger reopen and non-mutating observation on SM-T575.
- An opt-in, uniquely named test case performs two fsynced local fixture writes.
  The first has a committed result; the second terminates the test process before
  committing its result. A new process must replay only the committed result,
  report the second as unknown, preserve both journal sequences, and leave both
  file contents unchanged while live availability and executor calls fail.
- Only the test's own database and marker files are used. Existing app data,
  pairings, providers, and queues are not cleared or replaced.

Test graph/executors are fixtures. These checks do not establish live-provider
transcript recovery, arbitrary external-system reconciliation, network chaos,
or long-duration task completion. Actual run results are recorded below after
verification; process death alone is not described as a physical device reboot.

## Verified results (2026-09-10)

- Full build succeeded in 10 minutes 6 seconds. All 3,446 JVM tests across
  498 suites had zero failures/errors; five were skipped.
- Repository guard, QNN packaging, and all 73 AArch64 libraries' 16 KiB alignment
  passed. ASR/QNN implementation and packaged model configuration are unchanged.
- Android 1.1.45 (931) was installed in place on SM-T575. The original install
  date remained 2026-09-07; no app reset, re-pairing, or production queue cleanup.
- Combined ordinary device tests: 16 passed, zero failed, six opt-in crash cases
  skipped, in 112.211 seconds. This includes the 2,005-effect retention case,
  encrypted large-result storage, claim races, and the previous DAG-wait tests.
- The separate opt-in case `20260910-native-effect-v1145` completed one actual
  fsynced fixture write and its journal commit, then performed a second fsynced
  write and deliberately killed process 23074 before its outcome commit.
  The harness then physically rebooted the tablet. Boot identity changed from
  `c38f3427-55e9-4695-9077-e89d44c9a6e3` to
  `46b93825-83e1-4190-a46c-71cff088943c`; verification ran in process 4565.
  The completed effect replayed, the interrupted effect returned
  `effect_outcome_unknown`, and both files still contained exactly `one-write`.
  Both original journal snapshots remained unchanged. Live tool availability
  and executor callbacks were deliberately unusable during recovery.

Logs: `build/native-effect-observation-verified-build.log`,
`build/native-effect-observation-device.log`,
`build/native-effect-observation-reboot.log`, and
`build/offline-effect-20260910-native-effect-v1145/`.

The reboot result proves this isolated native-effect recovery case, not automatic
resumption of every production execution path or the complete network-chaos
matrix. Availability was fault-injected at the tool boundary; the public network
itself was not disabled. The outer model-loop transcript, coordinator recovery,
and application-specific reconciliation of uncertain external writes remain
separate requirements.

Reproduce with the matching APK/test APK already installed and a fresh case id:

```powershell
./tools/dev/test-android-offline-effect-recovery.ps1 -Serial DEVICE_SERIAL -ExpectedModel SM-T575 -RebootDevice
```

The script retains the isolated fixture and logs. Never rerun preparation for a
failed case: inspect its evidence and invoke only the verification test with the
same `effect_observation_case` after fixing the problem.
