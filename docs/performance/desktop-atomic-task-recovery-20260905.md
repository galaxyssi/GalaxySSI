# Desktop atomic task recovery

## Scope

- Base: `5ab36d5d7`, after Android/Desktop Run Kernel PR #2804.
- Desktop version: `1.0.4`; Android remains `1.0.3` and iOS is unchanged.
- Task inputs, state, event identity, and chunked outputs commit together in the
  canonical Run database. Runtime recovery checkpoints use the same database.
- Legacy sources are attached read-only. The import and its one-time marker are
  atomic, preserve the original databases, and reject identity or integrity conflicts.
- This change does not resubmit completed tasks or replay external side effects.

## Verification

`python tools/dev/test-run-kernel.py`: **106 tests passed**, including 22 new
atomic persistence and migration tests. These cover:

- Live task rollback when a save fails before or after writing its task row.
- Event identity rejection without a phantom task or partial output chunks.
- Caller transaction ownership and cross-database transaction rejection.
- Process exit after event insertion, after task/chunk insertion, and after commit.
- Process exit during migration, followed by complete retry from intact sources.
- Complete prompts, attachment references, large outputs, events, and checkpoints.
- Corrupt, missing, reordered, and inconsistent output chunks.
- Read-only imports and migration idempotency after task deletion.
- Interleaved task-manager and Runtime writes with distinct execution identities.

`npm.cmd run check`: 16 Desktop UI regression tests and structure checks passed.
Full Desktop backend regression: **1,201 tests passed in 234.45 seconds**, using
Python 3.11.15 and pytest 8.4.2 in the isolated test environment. The first attempt
stopped because that environment lacked `tzdata`; after installing the declared
Windows timezone dependency, the entire suite was rerun successfully.
`node tools/dev/check-repo.js`: passed. The repository-wide read-only structure
check still examines iOS; this PR contains no iOS implementation changes.

All local backend tests use temporary HOME, USERPROFILE, APPDATA, state, and data
directories. Sidecar tests use a separate local port. Existing phone identities,
pairings, and the running Desktop databases are not reset or migrated by tests.

## Local persistence microbenchmark

Run `python tools/dev/benchmark-task-persistence.py --backend <backend-directory>`.
The before and after runs were sequential on the same Windows host and Python
3.11.15 runtime. Each run creates 100 tasks and performs 300 saves, including
approximately 4 KiB prompts and 37,500-character chunked final outputs.

| Measurement | Before (PR #2804) | After |
| --- | ---: | ---: |
| Save P50 | 17.560 ms | 10.597 ms |
| Save P95 | 20.955 ms | 13.402 ms |
| Save P99 | 37.061 ms | 15.900 ms |
| Reopen completed task store | 6.848 ms | 7.078 ms |
| SQLite files | 6,156,288 B | 6,160,384 B |

These are single-run local microbenchmarks, not a mobile, provider, MQTT, or UI
latency guarantee. They show no observed write-performance regression in this
sample. Reopen timing is not a P95 recovery SLO and uses completed tasks only.

## Remaining boundaries

SQLite retains `synchronous=NORMAL`; process-crash atomicity is tested, while
durability of the latest commit after power loss is not promised by this policy.
Migration assumes the old Desktop writer has stopped. Downgrade synchronization,
provider resubmission, exactly-once external effects, full-chain tracing, and
S26U end-to-end performance acceptance remain separate roadmap work.
