# Unfinished tool discovery and test history

## Product behavior

Task-related capability recall previously indexed released tools but omitted
`executable_tool` candidates and `tool_test_plan` records. A later assignment
could read those originals only after discovering their IDs through the general
workspace. Keyword-based capability discovery could therefore overlook useful
unfinished code and the tests that rejected it.

Capability recall now includes both kinds. A test plan can match metadata from
its exact visible source: name, purpose, conditions, environment and dependencies.
Source code and expected test answers are not search terms or automatic excerpts.
Linked metadata remains subject to the reader's original workspace visibility.

Each match includes its exact reference and a `usage_recall` selector. The existing
`method_history` mode returns original native test observations, including failures
and replays, without executing code. `read_original` retrieves complete inputs,
outputs and diagnostics through existing evidence pagination. The new task does
not need the earlier conversation's text.

Candidate history requires a runtime receipt resolving the exact source and test
plan. A rejection before source resolution is attributed only to the requested
test plan. Missing history is unknown, not proof a candidate works or was unused.
Current paging and authorization checks remain in effect; no new background scan,
migration, scheduler, global sharing or execution permission is introduced.

## What is not changed

- A candidate remains unverified. Search does not release or install it.
- Existing source, test, independent release and runtime checks still apply.
- The Agent chooses whether to repair, extend tests, reuse a released version or
  develop an alternative. No fixed repair sequence or retry count is added.
- Prior failed tests and negative outcomes are not overwritten or reclassified.
- Native tests and remote shell executions are not interchangeable receipts.
- Reopening a store is not a measured long-term retention interval.
- A synthetic fixture is not evidence of autonomous learning or team superiority.

## Verification

Focused JVM coverage checks candidate discovery after reopening, failure details,
pre-execution rejection, replay identity, no implicit release, exact source/test
bindings, hidden metadata, exclusion of code and expected answers from search,
paging, reader isolation, revoked access and caller attempts to relabel records.

`CollaborationCandidateRecallDeviceTest` exercises real persistent stores and both
cloud/native recall adapters with a temporary synthetic failed-test record. It
creates a fresh assignment, retrieves the original expected/actual mismatch and
checks member revocation. It invokes no model or Python, makes no scientific
claim, and removes its dedicated group, workspace and evidence afterward.

The production increment is Android 1.4.147 (1232). Desktop transport and UI are
unchanged; existing scoped recall already serves the same modes remotely.

Verified on 2026-10-11: 62 focused JVM tests passed; debug and instrumentation
APKs compiled; three targeted instrumentation tests passed on SM-G9880 (S20U).
The device suite includes candidate history, existing workflow checks and typed
record persistence. The installed base APK hash matches the built APK. The
source-size policy and `git diff --check` passed. No live model efficacy claim
follows from these local synthetic checks.
