# Exact connector session lookup

## Scope

Android 1.1.42 (928), stacked on the Desktop queue fix in PR #2967. Desktop
remains 1.1.41. No ASR, QNN, model, attachment, or encrypted storage format changes.

## Evidence and change

The preceding real SM-T575 case `live-final-1788978937857` recovered the final
body in 6,119 ms but needed 12,030 ms to display it. Its inbox had two entries;
pre-consume runtime lookup took 2,411 and 1,346 ms, followed by consume calls of
1,867 and 2,300 ms. Code inspection found repeated whole-task scans on missing
native runtime snapshots, including ordinary direct replies with no native task.

An explicit canonical turn now restricts persistent lookup to `task:<turn>`.
The snapshot still has to match the source/contact and be recoverable; subsequent
runtime and transcript identity checks are unchanged. Missing explicit snapshots
do not trigger a search through other tasks or reuse another indexed turn.

Identity-less legacy replies retain index validation, stale-index removal and
fallback scanning. A stale indexed snapshot is not loaded twice in that lookup.
There is no negative cache that could conceal a later saved snapshot. The inbox
worker no longer restores once before invoking a consumer that already restores
on the same background worker.

## Verification design

- Pure lookup tests cover explicit hit/miss, 10,000 unrelated candidate keys,
  mismatched index, whitespace, invalid source, legacy hit/stale/miss/recovery,
  and a snapshot arriving after a previous miss.
- The device regression creates only its own encrypted sentinel task root and
  an isolated test window. It holds the sentinel persistence lock while calling
  the actual Activity runtime lookup for a different explicit turn. Cleanup
  releases the lock and removes only the generated test root/conversation.
- The same real final-drop/process-death/inbox/UI-recreation/cold-start harness
  must pass without resubmitting a completed task or manufacturing its reply.

The 10,000-key unit test verifies that no enumeration occurs; it is not a claim
that 10,000 persisted production tasks were stress-tested on the device. Full
reboot coordination, side-effect deduplication, global performance percentiles,
and the broader goal remain unaccepted until their own evidence is available.

## Results on SM-T575

Full build succeeded in 8m 16s. All 3,427 unit tests in 496 suites passed, with
zero errors and five existing skips. Repository, 73-library 16 KB, and QNN package
checks passed. New production/test files are each under 10 KB.

The actual Activity lookup test failed on installed 1.1.41 at its ten-second
Future deadline while an unrelated task was locked. With 1.1.42 it passed with
the lock still held; the whole test, including its test window setup, took
2.967 seconds. The first-install timestamp remained 2026-09-07 07:17:23 after
the in-place update. Only SM-T575 (`R52R90282TY`) was operated.

Real case `live-final-1788980024707` passed all four phases with one Codex attempt
and execution generation 1. Its original conversation is
`78525f4c-94b4-4791-a84f-5b0029bf115d`. The original final hash was preserved,
Activity recreation retained the correct conversation, and both UI/cold checks
found exactly one assistant entry. A subsequent normal launch screenshot was
visually checked and showed that single reply.

| Measurement | Previous 1.1.41 sample | New 1.1.42 sample |
| --- | ---: | ---: |
| First visible recovered reply | 12,030 ms | 4,855 ms |
| Subsequent plain cold visibility | 2,541 ms | 2,506 ms |
| Inbox first entry lookup + consume | 2,411 + 1,867 ms | 519 ms combined |
| Inbox second entry lookup + consume | 1,346 + 2,300 ms | 130 ms combined |
| Network body recovery | 6,119 ms | 58,408 ms |

These are consecutive real cases with the same Chinese test request, not a
representative benchmark or percentile guarantee. The network regression is
retained, not excluded: connection readiness took 2,529 ms and the body took
55,879 ms after readiness. Four eight-second query waits expired; responses to
those queries subsequently appeared as `late_or_unknown`. The final body was
eventually delivered within the unchanged 60-second phase deadline. The lookup
change does not alter headless transport handling; the next investigation must
trace late-response ownership/queue delay rather than attribute all waiting to
UI or claim the end-to-end five-second objective is met.

Evidence: `build/exact-session-lookup-{build,before,after,repo,16kb,qnn}.log`,
`build/exact-session-lookup-unit-summary.json`,
`build/exact-session-live-1788980024707.log`,
`build/live-final-1788980024707/`, and
`build/exact-session-recovery-screen.png`.
