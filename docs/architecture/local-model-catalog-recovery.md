# Local model catalog recovery

## Failure and boundary

The local loop previously bound recovery to the available-only catalog, including
readiness reasons and timestamps. Installing a dependency, losing connectivity,
or simply receiving a fresh availability timestamp could change that hash and
reject an otherwise unchanged durable task. Such observations are not changes
to the tool contract or the user's goal.

New identity-bound local dispatches use a registered-contract catalog. It binds
the entire authorized registry view, including unavailable tools, but excludes
availability. IDs, versions, schemas, execution locations, permissions, consents,
risk, timeouts, concurrency, idempotency and effect semantics remain bound.
Building this catalog neither probes readiness nor executes or installs a tool.

The model adapter still receives the current available-tool snapshot for each
execution slice. Discovery/inspection and invocation return current availability;
the native execution gate is unchanged. Stable contract membership is not an
assertion that a tool is ready. Newly repaired capabilities can be discovered and
selected by the model without changing the original loop/checkpoint binding.

The encrypted continuation pins its binding kind along with its original goal,
selected profile and scope. Old available-snapshot records retain their exact
bindings; they are not silently promoted or rerun as new tasks. An old record
whose snapshot no longer matches still requires reconciliation. Calls without
a durable dispatch identity retain the previous available-snapshot behavior.

## Validation scope

Regressions cover readiness/reason/timestamp changes, contract changes, restricted
views, input/identity preservation and old-record behavior. A durable loop fixture
installs a missing capability, interrupts after committing its receipt, recreates
the registry, resumes, and verifies the original operation without repeating the
installation. A device fixture repeats this using the encrypted database, a real
database close/reopen and the local JSON model adapter with a Chinese goal.

Model decisions and dependency actions in these fixtures are injected. They do
not establish autonomous real-provider dependency installation or website login.
The broader goal remains open.

For comparison, [LangGraph's persistence documentation](https://docs.langchain.com/oss/python/langgraph/persistence)
distinguishes thread-scoped checkpoints from cross-thread stores. This change
keeps using GalaxySSI's existing encrypted per-loop journal; it does not add a
second global request cache or replace the execution framework.

## Verified build

Android 1.4.186 (1271) built successfully in 8 minutes 44 seconds. The expanded
JVM selection passed 708 tests across 92 suites with no failures, errors or skips.
Repository Guard passed on the clean staged-source snapshot.

S20U / SM-G9880 was updated in place without clearing data. The new encrypted
catalog-recovery fixture passed, followed by all 61 existing local/browser/runtime
device checks. Cold Activity launch reported TotalTime=672 ms and WaitTime=680 ms;
MainActivity resumed and the crash buffer was empty. These timings do not measure
full first-content latency or real-model task performance.

Evidence under .local-artifacts/autonomous-problem-solving/ includes:

- build-1.4.186.txt and jvm-1.4.186-summary.json
- pr-1.4.186-clean-repo-guard.txt
- s20u-1.4.186-catalog-recovery.txt
- s20u-1.4.186-framework-regression.txt
- s20u-1.4.186-installed-package.txt
- s20u-1.4.186-cold-start.txt and s20u-1.4.186-resumed-activity.txt
- s20u-1.4.186-crash-buffer.txt

The full Android CI baseline has three separate collaboration test failures.
They are also present in main at 69ccd9f01, verified against its GitHub Actions
log. They are not hidden by this scoped JVM selection and are not fixed by this
catalog-recovery increment.
