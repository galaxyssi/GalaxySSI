# Saved Tool Execution From Remote Collaboration

Remote Codex can request `collaboration_test_tool` without supplying executable
source, a shell command, member authority, or a test verdict. The originating App
resolves an immutable `tool_test_plan` and its exact `executable_tool`, compiles
the existing test harness, and invokes `galaxyssi.runtime.execute`. Expected
answers stay outside the generated candidate's input. The existing native evidence
recorder retains the original output; App validation compares actual case values.

## Lifecycle

1. Publish the saved source and test plan using normal collaboration publication.
2. Call `mode=start` with a stable `execution_id`, exact plan reference, and
   `timeout_ms`. The timeout is the existing native per-process range, not a
   research-step or goal limit.
3. Admission returns `queued`. Query `mode=status` with the same ID, respecting
   `retry_after_ms`; do not busy-poll or equate admission with successful tests.
4. `finished` means the native invocation ended. Inspect `native_status`, `passed`,
   and the original evidence receipt. Missing/unavailable execution has no passing
   verdict. Full reports and failure details are read through evidence recall.
5. A reviewer can use the existing release/comparison contracts after reading
   original evidence. A failed candidate remains available for diagnosis and repair.

`mode=cancel` affects this test only. A queued cancellation cannot enter the
executor. Running cancellation is forwarded to the existing native cancellation
token. Pausing/removing/replacing the member assignment cancels active execution;
the transport nonce expiring alone does not cancel accepted work.

## Recovery And Scope

The encrypted workspace journal is scoped to group, run, turn, round, node and
person. A repeated start can only read the same saved outcome; changed input under
the same ID is rejected. An App-process restart marks unresolved work interrupted,
never automatically repeats an uncertain effect. Original native evidence must be
recovered before the Agent decides whether a genuinely new attempt is appropriate.
This is not an exactly-once guarantee for arbitrary external side effects.

RPC retries keep the transport nonce and execution ID. They do not create a second
durable MQTT outbox. Results are accepted only from the bound authenticated route,
current task generation and matching phase. Read-only recall cannot start tests.
Read-only or plan-only Codex tasks cannot start code through this capability.

## Boundaries

- Uses the already available **App Linux runtime**, not Desktop terminal output.
- Does not download a runtime, install a Skill, change model selection, grant
  permissions, or silently fall back to another machine.
- The existing Linux execution environment is **not a security sandbox**. Network
  is requested disabled through the native runtime's existing policy; this is not
  a new OS-level security guarantee.
- Completed checks do not prove oracle truth, broad correctness, innovation,
  causal learning, or physical scientific experiments.
- Two execution slots bound device resource use; they are not a team-size or
  research-step limit. Waiting work and test results remain independently scoped.

## Validation

JVM tests cover identity, duplicate admission, changed inputs, cancellation,
cross-member isolation, process-loss uncertainty and receipt restoration. Desktop
tests cover the actual dynamic-tool callback, execution-policy checks,
authenticated responses and uncertain transport recovery. Device persistence tests
use synthetic results and do not invoke models.

`CollaborationSavedToolNativeDeviceTest` is a separately selected device suite. It
runs two tiny developer-authored Python candidates through the production native
wrapper, checks the failing and repaired reports, and reopens their receipts. It
requires an already installed runtime and never downloads one. It is not a real
model innovation trial or a full MQTT end-to-end acceptance test.

### S20U Verification, 2026-10-08

- Android 1.4.105 (1190) was installed by update on SM-G9880. The installed APK
  SHA-256 matched the build: `ed0ee1ab7d4de1b204993987c6a1a139eaefb8299cb4567e585f832b3d472a00`.
- Android targeted JVM suites: 78 passed, no failures or skips.
- Desktop isolated regression runner: 167 passed, one skipped (168 total).
- Device persistence, comparison, executable contract and milestone suites:
  17 passed in 14.818 seconds. These used synthetic execution observations.
- The separately selected real native suite **failed** after 393.751 seconds.
  The installed guest image still expected
  `/sys/firmware/qemu_fw_cfg/by_name/opt/com.signalasi/runtime-session/raw`;
  the current host supplies the GalaxySSI interface. The guest startup logged
  `FileNotFoundError`, so no candidate Python test verdict was produced.
  This is an environment startup failure, not a failed candidate or a successful
  repair. The test now explicitly reports missing native verdicts instead of
  attempting to parse null as a boolean; that diagnostic change was not rerun
  against the same incompatible guest.
- No runtime was downloaded or replaced, no real model was called, and the
  running Desktop instance was not restarted. Full live Codex/MQTT execution and
  failing-to-repaired native acceptance remain pending.
