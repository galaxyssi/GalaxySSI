# Stable reply identity acceptance

## Scope

The artifact campaign remains 100 cases and 1,100 planned turns. This change
repairs evidence capture, not production rendering or the definition of success.
Only the authorized SM-T575 (Active3) was used.

## Observed failure and verification

In `active3-handwriting-20260929-desktop1323`, turn 9 delivered a correct final
image and stopped its timer, but immediate capture retained an obsolete row ID.
The original failed observation remains unchanged.

A separate read-only audit (`capture-audit-1790679453209`) matched the frozen
report's conversation, turn, task, reply text and rich artifact identity to the
current final row. Original row `1798f785-aeaf-4eab-9d03-31ec96e4f5f5` became
`dacde4c3-a0fa-4e4d-9c5b-7f808728a17b`. The target was visible and focused, three
frames were stable, and the timer was stopped. Clicking the delivered thumbnail,
opening fullscreen and saving produced a new download (1000003336) with SHA-256
`51b345c8fdd183c84006cfbcab2f9fff41ae357e297d48a26a7035620ea61ef0`.
No model request was resent during this audit.

## Matching invariants

- Require the same nonblank conversation and turn and exact reply text. Task IDs
  must match unless the completed-workspace exception below is proven.
- Reject non-assistant, streaming and approval rows.
- Accept unchanged rich JSON, or equal ordered rich blocks with identical
  non-file content and verified 64-hex artifact hashes, IDs, types, MIME types,
  titles and text. Only hydration-specific file locations/state may differ.
- Reset stable-frame sampling when the current matching row changes.
- Read the already-loaded UI window on the main thread, not the database.
- A missing target still fails; preserve a diagnostic screenshot when possible.
- Record initial and observed row IDs. Never rewrite historical failed captures.

Five identity device tests and three phase-timing device tests passed. The
18 Python catalog/timing regression tests also passed. This establishes the
specific identity repair, not a universal UI-restoration or grading pass rate.

Private transcripts, artifacts and screenshots remain outside Git.

## Canonical parent final on Active3, 2026-09-30

The original A008 turn 0 report in `active3-warehouse-image-20260930-v1326`
recorded no artifacts during its audit despite later showing the image on screen.
A read-only identity audit located the actual difference: the initial final row
used the remote Codex task ID, while the current canonical final used the local
execution task ID. Conversation, turn, exact text, block IDs, artifact ownership
metadata and SHA-256 remained unchanged. The local original PNG was present.

This is evidence of a reply-identity limitation in the evaluator, not permission
to classify all missing previews as evaluator errors. In particular, the prior
A007 missing-file observations have not been reclassified.

The evaluator now permits this replacement only with an explicit durable
workspace snapshot: status COMPLETED, workspace ID and task ID equal to the
reference turn, the same conversation, a nonblank candidate task ID and its exact
canonical final dedupe key. The production `hasDeliveredReply` policy must accept
the candidate, or a completed connector snapshot must prove both executor IDs,
conversation, turn, exact result text and completed parent loop. Cancellation and
pre-workspace timestamps are rejected in both paths. A resumption after the
checkpoint's loop completion is rejected. Content and artifact comparisons still apply; artifact ID, originating
task, Desktop and client-route metadata must remain equal. Without that workspace
proof, an unrelated task with identical text is still rejected.

Workspace reads happen on the instrumentation worker; UI-thread capture reads
only the loaded window and the already captured workspace snapshot. New live
turns record their actual app version/code/update timestamp independently of the
run's initial version, so an in-place upgrade is not silently attributed to old
turns.

`BusinessReplyAuditDeviceTest` is opt-in, takes one named synthetic run/case/turn,
and writes a separate timestamped diagnostic. It does not resend model requests,
change the catalog or rewrite historical assessments. The A008 report hash before
this audit was `f47700016d731e2c86a0f67d0d40b842fffe99a03ba28ff9c1c14de30c5bca54`.
Subsequent appended turns are new evidence, not a replacement for the original.

The first strict-policy recapture failed. A follow-up diagnostic showed why:
the connector reply timestamp was 1790699034255, parent automatic resumption was
1790699034399, and loop completion was 1790699036500. The same connector is
resumed to consume and finalize the result, not to execute a new user request.
The durable result explicitly binds remote task
`7374685c-082c-3bab-acbf-56028ff51ab1` to local executor task
`a9355a6f-a413-43be-9429-60ab5438d083`, the original conversation and parent turn.
This alternate proof is test-only; production liveness/resumption policies are
unchanged. A malformed, incomplete, mismatched or later-resumed snapshot cannot
authorize replacement. The diagnostic does not export all conversations.

Verification: eight identity tests passed on Active3 (0.134 s), and 32 host
catalog/report tests passed (0.559 s). The subsequent read-only UI audit
`capture-audit-1790701184762` passed in 8.383 s: the original PNG thumbnail opened
fullscreen and saving created download 1000003441 with SHA-256
`8c56200b97e18fe51610f9f18c71b78c2e4fc275dbf382cf5936535edabc0707`.
The target reply was focused, visible and stable. Its historical process row was
not captured (`process_visible_text` empty, `timer_stopped` false), so this audit
does not prove the timer state. The raw A008 report hash remained exactly the
value above; neither the initial missing-artifact result nor the content-grounding
failure in turn 1 has been upgraded to a pass.

## Continued real-model turns

The same frozen run then appended A008 turns 2-4 on Active3 1.3.26 (1069),
using the existing Desktop 1.3.23 process. No earlier turn was resent or rewritten.
Instrumentation completed in 362.965 s; this is runner completion, not a business
quality pass.

| Turn | Reply terminal | Additional artifact presence wait | Observed total |
| --- | ---: | ---: | ---: |
| 2: mobile layout, background | 123.295 s | 1.592 s | 127.150 s |
| 3: add Ding record | 79.738 s | 3.733 s | 85.878 s |
| 4: check unknown sources | 77.925 s | 65.573 s | 146.046 s |

All three delivered actual 1200x1600 PNG files with matching saved-download
hashes, stable focused reply captures and stopped timers. Turn 2 received its
reply while backgrounded. Their totals are correctly 726, 826 and 826; layout
was readable and unknown owner/date/returns remained unconfirmed. Each still
asserted the unsupported yuan unit and therefore has a source-bound content
failure in `reviews/active3-a008-20260930.json`. The 65.573 s attachment tail is
also unresolved; these samples do not establish a latency percentile or reliable
weak-network delivery. Six A008 follow-ups and the wider frozen campaign remain.
