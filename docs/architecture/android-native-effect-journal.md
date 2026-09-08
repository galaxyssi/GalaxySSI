# Android Native Effect Journal

Android source version: 1.1.5 (891). Desktop is unchanged.

## Runtime Integration

The ordinary mobile plan executor and model-tool loop share the native tool
registry. Tools declaring `IDEMPOTENCY_KEY_REQUIRED` now acquire a durable effect
claim before entering their executor. The process cannot publish a finished
result to the Agent/UI before committing that outcome. This is execution state,
not optional diagnostic telemetry.

The key binds tool ID/version, the caller's effect key, client route, session,
conversation, goal, task and turn. Invocation IDs identify attempts, not new
effects. Reusing the same scoped key with different input remains an error.
The mobile plan adapter now supplies its task and goal identity explicitly.

Concurrent registry instances share the same SQLite claim transaction. Only one
can acquire a new effect. A second invocation returns either the durable result
or `effect_outcome_unknown`, including the original invocation and input digest.
It does not invoke the executor again. A timeout is not proof that a write did
not happen. There is no timed lease that silently allows another writer.

All observed outcomes, including failures and verification failures, are retained
for claimed effects. Repeating their key observes the same outcome; it is not a
new retry. The model receives the actual failure. After inspecting external state,
an intentional new attempt needs a new effect key. The framework does not infer
whether an external write happened from the wording of an error.

## Storage and Recovery

The shared encrypted Run Kernel stores these child Runs. Claims use a conditional
initial append. Outcome chunks and the terminal observation commit atomically.
Root identities and event payloads use the existing authenticated encryption.
Each event contains at most 24 Ki UTF-16 units of result text, without splitting
a surrogate pair; readers validate order, count, digest and receipt identity.
Large tool results therefore do not create one oversized Android CursorWindow
row. Complete output is retained, not truncated into a success summary.

Lookups address one effect by its digest. Results are read in event pages of 64;
the journal no longer reloads an array of every cached effect on each invocation.
There is no 2,000-entry eviction or 30-day expiry for execution receipts. Explicit
clearing removes only this journal's indexed namespace, never unrelated Runs.

A surviving claim without an outcome remains uncertain across process death or
database reopen. Model replanning can inspect the original operation and its
external state using available observation tools. No generic exactly-once claim
is made for arbitrary external systems that lack idempotency or reconciliation.

Legacy encrypted successful receipts are imported once without expiry and are
not deleted during migration. Old records lack execution scope. They can be read
under their original unscoped identity, but cannot serve as proof for a newly
scoped conversation. A matching unscoped key produces
`legacy_effect_scope_unverified` rather than exposing another conversation's
output or silently rerunning an old effect. Malformed legacy records stop
migration; they are not silently treated as an empty history.

## Boundaries

- Pure idempotent reads retain successful-result caching; they do not acquire
  persistent write claims.
- Tools declared `NON_IDEMPOTENT`, direct platform actions outside the native
  registry, connector sends and other executors still need their own adapters.
- A model can propose a new key. This change alone does not prove that a new
  proposal cannot repeat the semantic effect of an older uncertain operation.
- Whole Android task-DAG migration, automatic external reconciliation, durable
  pending-node scheduling and month-scale acceptance are not completed here.
- This does not enable self-evolution, change model routing, change ASR/QNN,
  send private execution state to another device, or reset user data.

## Verification

Focused JVM tests exercise scope isolation, two concurrent registries, uncertain
claims, input conflicts, failure replay, storage-failure behavior, completion-hook
ordering and retention beyond 2,000 later operations. Instrumentation tests use
isolated encrypted databases for reopen, competing claims, large multilingual
results, transaction rollback, stale writers, namespace clearing and migration.

The two explicitly enabled restart phases support an ADB force-stop between
setup and recovery. The pending effect in that case is a controlled fixture.
A separate process-death case invokes the real registry executor, writes a local
counter, then kills its own process before returning an outcome. Recovery invokes
the same scoped key through a new registry process and asserts the counter is
still `1`. This tests the interruption gap, not a remote service's exactly-once
contract. Both cases use isolated test databases and files, not user Run data.

### Verified on 2026-09-08

- 160 targeted JVM tests in 25 suites passed with no failures or skipped cases.
- Main and instrumentation APK builds passed. The 16 KB alignment gate passed
  for 72 Android AArch64 libraries; the QNN packaging gate passed for 24 libraries.
- SM-T575 was upgraded in place from 1.1.4 (890) to 1.1.5 (891), without clearing
  application data or pairings. No other attached device was modified.
- Nine ordinary instrumentation tests passed in a 90.001-second class run.
  Four opt-in restart/crash phase methods were skipped in that normal run;
  the runner's `OK (13 tests)` must not be reported as 13 ordinary passes.
- The separately enabled restart seed and post-force-stop recovery phases each
  passed (0.293 s and 0.268 s). Completed output replayed; pending output stayed
  uncertain without calling the executor.
- The actual executor process-death phase intentionally returned `Process
  crashed.`. Its separate recovery test passed (0.176 s), with the write counter
  unchanged at `1` and `effect_outcome_unknown` returned to the caller.
- A subsequent cold Activity launch succeeded (`am start -W`, 2,669 ms). This is
  one startup smoke measurement, not a P95/P99 performance acceptance result.
- `npm run check` passed after staging all new source and test files.

Raw build and device outputs are retained locally under `build/native-effect-*`.
These results do not complete whole-device reboot coordination, automatic
external reconciliation, ordinary Agent DAG migration, or long-period acceptance.
