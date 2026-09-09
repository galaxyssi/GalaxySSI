# Android planner observation context

## Failure addressed

Ordinary `MobileNativeAgent` replanning supplied completed actions in an
`AgentRequest`, but the guarded-model prompt emitted only action descriptions
and statuses. Native tool results and verification evidence never reached the
reasoning model. The former history block also followed larger context blocks
and could disappear under the final prompt limit.

Replanning did not carry the active conversation or turn into its request or
new actions. A runtime session is not a conversation ID. Scope filtering based
on the runtime ID alone would therefore discard legitimate observations.

## Behavior

- The prompt starts with the current goal, sanitized replanning reason and a
  bounded observation block, before the existing contracts and broader context.
- Native actions supply both result and evidence through the common observation
  sanitizer. Completed, failed and uncertain states retain their actual status;
  an absent observation is not reported as success.
- Observation text is marked as untrusted data, not instructions. Credential
  redaction precedes compaction. Structured JSON is parsed for nested sensitive
  fields; partial command output, private keys and authorization credentials
  also receive masking. This is defense in depth, not exhaustive secret detection.
- Whole JSON entries are budgeted after escaping. Newest observations take
  precedence; retained entries are emitted chronologically. The existing overall
  prompt limits remain, with 3,000/6,000 characters reserved for compact/normal
  observation history. The full journal is not copied into each model request.
- Connector output sharing remains opt-in. This change does not newly disclose
  screen text, global memory or other conversation summaries.
- Continuation scope resolves explicit IDs from current persisted actions and
  active context. Conflicting conversation/turn IDs prevent replanning. History
  cannot decide the scope of the current task. Unscoped legacy actions retain
  their existing task-local fallback; this cannot retroactively prove their owner.
- Explicitly foreign observations are excluded before invoking the planner and
  during prompt assembly. Framework-owned conversation and turn IDs override any
  proposed IDs on new actions, including after an encrypted session reopen.

## Validation boundaries

Host tests cover prompt placement, complete-entry budgets including JSON escaping,
result/evidence tails, scope conflicts, wrong-turn histories, credential masking,
connector privacy and legacy fallback. CI explicitly includes these suites.

The device rolling case executes eight batches of actual memory/storage tools,
parses injected model JSON through the production parser, checks observation
content at the planner boundary, then reopens the encrypted session and checks
the same content and scope again. Runtime and conversation IDs intentionally
differ. This proves the native observation plumbing, not that a live Provider
authored the plans or understood their output.

Remaining larger-goal work includes real-model-authored revisions, external-effect
reconciliation, all execution paths, full dynamic-DAG integration, long-period
scheduling and the existing failure-replanning count policy. No ASR/QNN model,
Desktop production implementation or user pairing data is changed by this patch.

## Executed validation, 2026-09-09

Integrated with main `60cab38ce`, Android 1.1.26 (912):

- Application and instrumentation APKs built successfully in 5m 38s. The 66
  focused JVM tests passed. The complete updated Android core selection then
  passed 152 tests in 16 classes, without failures or skips. These selections
  overlap; their counts must not be added together.
- All six core-regression runner/manifest contracts and repository checks passed.
- SM-T575 node-journal suite: 12 passed in 27.880 seconds; two explicitly opt-in
  process-death phases were skipped, not counted as passes. The eight-batch test
  verified real hardware observations in prompts, conversation/turn propagation,
  all 16 journal results and another planner assessment after encrypted reopen.
- SM-T575 startup, ready-node and connector-fallback regression suites: 17 passed
  in 25.700 seconds. Four opt-in boot phases were skipped. No real reboot or
  process-death injection is claimed for this patch's run.
- All 73 AArch64 libraries passed 16 KB alignment; all 24 QNN libraries passed
  package validation. Both APKs were installed in place only on SM-T575. The
  original first-install timestamp and user data were retained.
- Post-test activity cold launch returned successfully in 1,091 ms. This is one
  activity-launch measurement, not a UI readiness percentile or recovery SLA.
  The device crash log buffer was empty after the tests and launch.

APK SHA-256:
`4527fd26231175233bdb09d83fa88dde8dd11cab08c385f550daf41ec2b5924c`.

Local evidence remains outside Git: `build/planner-scope-build.log`,
`build/planner-scope-core-unit.log`, `build/planner-scope-device.log` and
`build/planner-scope-recovery-device.log`.
