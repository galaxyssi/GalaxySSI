# Durable model-tool loop checkpoints

## Scope

Android 1.1.46 (932) adds encrypted model-loop records to guarded cloud planning
and local-model web tools. Ordinary native effect recovery alone cannot restore
the outer conversation with a model: previously its responses, observations and
random planning-loop identity disappeared when the process died.

Each loop is bound to session, conversation, turn, task, workspace, caller and
planning revision. Its initial input snapshot is immutable. Each model response
is committed before executing its proposed tools; each stable invocation id is
committed before native execution; each tool result is committed before it is
returned as the next model observation. The native effect journal remains the
authority for effects whose result was not yet copied to the outer journal.

On re-entry, the loop reconstructs its original messages from these facts,
suppresses historical progress callbacks, and requests only the missing next
model response. A completed loop requires no provider or executor call. Explicit
cancellation is durable. Input/catalog drift, corrupt records, or journal write
failures surface as recovery errors instead of selecting a new executable
fallback plan. Same-scope execution is serialized by a process-releasing file
lock; different scopes remain independent.

Records use the existing encrypted Run Kernel store. Each immutable operation
has 24 Ki-character chunks and a committed count/hash, read in pages of 64 rows.
This is not a limit on the number of actions or retained observations. No growing
transcript is repeatedly rewritten as a single SQLite row. Presence checks use
indexed record keys, so an unreadable encrypted commit is not mistaken for an
absent record. The original model request transcript still grows in memory;
context compaction and multi-month bounded-memory operation are not claimed.

## Verification contract

- JVM tests cover interruption after observation, completed-loop replay, partial
  journal writes, parallel partial results, input drift, all scope dimensions,
  exclusive ownership, catalog drift, cancellation and 129 tool rounds with
  lifetime count limits disabled.
- Instrumentation tests reopen an encrypted large response, check bounded row
  size and absence of a plaintext marker, reject corrupt chunks/commits, and
  exercise file locking across separate journal instances.
- A unique opt-in case saves a model response, executes a real fsynced fixture
  file write, commits its tool observation, then terminates the test process
  before the second model response. Verification in a different process must
  start at model round two with that observation and no repeated executor call.
  A second reconstruction must use the saved final response without model calls.

With matching APKs installed, use a fresh case id:

```powershell
./tools/dev/test-android-durable-model-loop.ps1 -Serial DEVICE_SERIAL -ExpectedModel SM-T575 -CaseId UNIQUE_CASE -RebootDevice
```

If verification fails, inspect the retained database, marker files and logs.
Resume only verification with the same case id and `-Phase verify`; never rerun
preparation to replace the failed fixture. The script does not clear production
chat data, pairings, providers, models or queues. Test prompts are Chinese.

## Limits

The device model adapter and native executor are controlled fixtures, not a
real cloud-provider recovery test. A provider request interrupted before its
response is journaled may have to be requested again; this does not claim
exactly-once provider billing. An external effect with no committed native
outcome still requires reconciliation and is not silently executed again.

This supplies durable re-entry at the two integrated model-loop entry points.
It is not automatic startup coordination for every production execution path.
Restoring a pending initial planner with no published plan, long-duration DAG
scheduling, all-provider chaos, and UI performance acceptance remain separate
work. ASR/QNN models and the Desktop implementation are unchanged by this PR.

## Verified results (2026-09-10)

- The latest main (`50085c111`, including final Markdown table rendering) was
  merged before final verification. The full build passed in 9 minutes 38
  seconds: 3,463 JVM tests across 500 suites, zero failures/errors, five skips.
- Repository checks, QNN packaging and all 73 AArch64 libraries' 16 KiB
  alignment passed.
- Android 1.1.46 (932) and its matching test APK were installed in place on
  SM-T575. The original first-install date remained 2026-09-07; the update time
  was 2026-09-10 10:45:32. No production data reset or re-pairing occurred.
- Combined device regression: 21 passed, zero failed, eight opt-in cases
  skipped, in 112.298 seconds. Coverage also includes previous effect/DAG
  recovery, 2,005 retained effects and the newly merged Markdown table renderer.
- Opt-in case `20260910-model-loop-v1146` deliberately terminated process 18917
  after committing its native observation. A physical reboot changed boot id
  from `46b93825-83e1-4190-a46c-71cff088943c` to
  `b6103e57-64f7-4b51-8e96-3e0857b4d001`. Process 4518 restored the existing
  observation and requested only round two. The executor was never called
  again; a further completed-loop reconstruction required no provider call.
  The verification test passed in 0.836 seconds. This is test execution time,
  not boot time, live-provider latency or an all-path recovery SLA.

Evidence: `build/durable-model-loop-verified-build.log`,
`build/durable-model-loop-device.log`, `build/durable-model-loop-reboot.log`,
and `build/durable-model-loop-20260910-model-loop-v1146/`.
