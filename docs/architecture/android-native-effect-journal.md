# Android Native Effect Journal

Android source version: 1.1.50 (936). Desktop is unchanged.

## Runtime Integration

The ordinary mobile plan executor and model-tool loop share the native tool
registry. Mutations (including idempotent overwrites), and tools declaring
`IDEMPOTENCY_KEY_REQUIRED` or `NON_IDEMPOTENT`, acquire a durable effect
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

Since 1.1.12, non-idempotent effects also retain receipts and acquire claims. The
earlier registry explicitly bypassed their provided keys, leaving tool types such
as generic MCP and Linux software operations outside this mechanism. The mobile
plan adapter now passes the action ID for these tools. Model tool calls derive a
stable key when absent, in both serial and parallel dispatch, and Skill children
inherit a parent-key/step identity. Parallel model calls also retain explicitly
provided keys. Automatic retry of non-idempotent tools remains disabled.

For a direct registry caller without a logical effect key, a mutation without an explicit-key requirement
uses its invocation ID as a fallback; the executor and receipt receive that key.
Repeating that invocation is not a new effect, while a new invocation without a
stable caller key is a new request. Idempotent reads without keys still perform
fresh reads without accessing the effect journal. Claims do not equate two new
model-generated calls merely because their arguments are similar.

### Idempotency Is Not Read-Only Semantics

An idempotent overwrite can still destroy a newer user edit when redispatched
after a lost receipt. Since 1.1.50, descriptor `effect` distinguishes explicit
serial reads from mutations. Existing `PARALLEL_READ_ONLY` tools imply a read;
unclassified serial tools conservatively require a claim. Explicit mutations
cannot advertise parallel-read-only concurrency. Existing non-idempotent and
explicit-key-required contracts continue requiring claims regardless of effect
metadata. Missing required keys are still rejected before execution.

This internal recovery metadata does not change the public model tool catalog
hash, so pending planner journals do not become invalid merely because execution
is more durable. The ordinary plan adapter supplies the stable action ID for
idempotent mutations too. The model tool loop automatically retries only pure
reads; mutation outcomes are observations for the next model decision, not
permission for a blind retry. Resource-scoped parallel mutation scheduling is
unchanged.

Known serial hardware, notification, Home Assistant, web/media and remote
Desktop reads are annotated explicitly. Flashlight setting, browser closing,
workspace creation and file overwrites remain mutations. This classification
uses tool contracts, never keywords in a user's request or error message.

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
- Mobile direct actions and rollback now use the [action-effect adapter](android-action-effect-journal.md).
  Platform actions outside both entry points and other executors still need their
  own integration; connector acceptance is not a final response.
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

### Non-idempotent Extension Verified on 2026-09-09

- Android 1.1.12 (898) installed in place on SM-T575. User data and pairings were
  retained; the attached S20U was not operated on. Desktop was unchanged.
- 83 focused JVM tests in seven suites passed. Coverage includes same-call
  receipt replay, concurrent registries, uncertain claims, changed inputs,
  separate conversations, fallback invocation identity, failed outcome commits,
  fresh idempotent reads and a model tool call resumed with the same logical key.
- The audit test previously reused one invocation ID for different operations.
  Its fixture now gives independent calls distinct IDs; success/failure and
  sensitive-log assertions remain unchanged. The initial new test setup also
  used an invalid tool version and was corrected to semantic version `1.0.0`;
  that failed setup is not evidence of the production defect.
- A real non-idempotent test executor fsynced a file append and killed its
  process before returning an outcome. A new process invoked the same scoped
  effect key with a new invocation ID and received `effect_outcome_unknown`.
  The original owner was retained and the file contained exactly one append.
  Verification passed in 0.156 s; explicit verified-fixture cleanup passed.
- The combined effect-journal and ready-DAG device regression passed 12 actual
  tests, with seven opt-in phases skipped (19 total reported by the runner).
  This includes retention after 2,005 effects and the ordinary resume regression.
- Repository checks, 72-library 16 KiB alignment and 24-library QNN packaging
  passed. A final cold Activity launch took 2,534 ms and the crash buffer was
  empty. This is smoke evidence, not a performance percentile gate.

APK SHA-256:
`DEDC56B7017BFCAE9D273FC6D3F76FBD948A1181A402087846084D925D1B0FB0`.
Logs remain local under `build/nonidempotent-*`. The test executor performs a
real local file write using the production registry and encrypted journal; it
does not test remote service reconciliation or a model inventing a new effect
key for the same semantic operation. Those acceptance gaps remain open.

### Idempotent Mutation Extension Verified on 2026-09-10

- Before the fix, both new JVM reproductions failed: an interrupted overwrite
  ran again over a newer user edit, and an invocation without an explicit key
  executed twice. These were behavioral failures, not compilation failures.
- Final full JVM run: 3,486 tests in 503 suites, zero failures/errors, five skips.
  The first full run found one old read-only fixture missing its explicit read
  declaration. Its freshness assertions were retained and a no-observation
  assertion was added. The final run also checks browser state mutations,
  concurrent duplicates, isolation, input conflicts and deliberate new actions.
- Debug and instrumentation APK builds passed. Repository checks, 73-library
  16 KiB alignment and the 24-library QNN packaging audit passed.
- SM-T575 was upgraded in place to 1.1.50 (936). First install remained
  2026-09-07 07:17:23; last update became 2026-09-10 13:47:55. No user data,
  pairing or downloaded models were cleared. No other device was operated on.
- The combined mutation, observation-first and ordinary multi-node recovery
  run passed five actual tests in 1.990 seconds, with four opt-in methods skipped.
  Two new tests use the production workspace catalog, actual file overwrites
  and encrypted SQLite: a failed receipt commit survives database reopen, and
  a completed receipt replays without overwriting newer text.
- Crash case `20260910-v1150` killed process 16965 after the actual workspace
  overwrite and before receipt commit. Recovery in a new process passed in
  0.176 seconds, returned `effect_outcome_unknown` and retained newer text.
- The same evidence was verified again after a physical T575 reboot, without
  reseeding or submitting another task. Boot ID changed from
  `3f19ddc6-092e-45e9-9fbe-a97b41d3ab81` to
  `748770b9-f8f2-413a-90db-54980d1636f6`; recovery passed in 0.270 seconds.
  The original claim, test file and verification marker remain on the device.
- Existing encrypted journal regression: nine actual passes, four explicit
  restart/crash phases skipped, 172.536 seconds. This covers 2,005 later effects,
  large results, competing owners, rollback and legacy scope isolation.

Local logs are `build/idempotent-mutation-*.log`. APK SHA-256:
`DD84F2239F812CACF5EC59EFF47579B37F01B5AD7C9C6F14F3EDA470DC26A15E`.
This is not a real cloud-provider test or a performance percentile gate. It
does not retroactively create receipts for old unjournaled operations, prove
exactly-once external services, or complete all-path Run Kernel acceptance.
