# Artifact Live Acceptance Follow-Up

This follow-up uses the existing frozen 100-case / 1,100-turn artifact catalog.
It does not replace failures with smaller workloads or change latency targets.
Device scope is Active3 (SM-T575) only. Runtime: Android v1.3.22 (1066), Desktop
v1.3.19, configured Codex provider. Native files, logs and screenshots remain
local; this document contains synthetic-case observations only.

## Late Results Without Duplicate Requests

The live driver preserves an `observation_timeout` checkpoint. A separate opt-in
`observeLateCompletedArtifact` test observes the original turn without sending a
new request. It requires the same catalog, conversation and turn, a terminal
phone workspace, no active supervisor task, and an actual final assistant entry.
It collects the delivered artifacts and captures the exact reply and process
rows. Successful evidence is stored separately as `Axxx-index-late.json`; the
original timeout, elapsed time and failed assessment remain unchanged.

Continuation additionally requires `business_continue_after_late=true`, a valid
late receipt, successful container/delivery/save checks and visible reply, and
rechecks the current phone task and transcript. The loop skips the original
request and sends only the next unsubmitted turn. No receipt means no resend and
no continuation. A receipt does not establish content correctness by itself.

## Observed A003 Run

Run: `active3-artifacts-v3-20260929-desktop1319`.

- Creation exceeded the 600-second phone observation window (600,356 ms).
  Desktop completed later in 668,524 ms. The original failure remains recorded.
- Tool evidence shows several recoverable PowerShell/PowerPoint errors: UTF-8
  script interpretation, variable collision, cell-border APIs and chart COM
  state. The task was not prematurely stopped by the old one-error policy, but
  generation performance remains unacceptable for the 300-second target.
- Desktop produced one 48,980-byte PPTX and four 1600x900 previews. The first
  late audit failed to load the exact final row. A subsequent read-only audit
  passed: all five native/preview names, containers and saved hashes match;
  the actual final reply is visible and its timer has stopped. This does not
  establish the precise first phone receipt time after the original timeout.
- The rebuilt late observer passed in 6.674 seconds. Running the ordinary
  driver without the explicit continuation flag rejected the retained timeout,
  as intended, before sending another prompt.
- The next real user turn restored the delivered PPTX from the phone through
  the authenticated attachment request. The restored 48,980-byte file's SHA-256
  matches the prior received/downloaded file, not just its filename.
- Revision completed on the phone in 151,263 ms, within the unchanged 300-second
  target, with a 49,093-byte PPTX and four previews. All five versioned filenames
  and saved hashes pass; the reply is visibly rendered and its timer stopped.
- Native slide text and preview review confirm the requested change only:
  quantity 23 becomes 30, amount 184 becomes 240, and total 520 becomes 576.
  Pages one and three retain identical preview hashes and text. Page two's
  table, bars and arithmetic and page four's totals agree. The original timeout
  JSON turn is structurally identical before and after continuation.

## Background Layout and Added Record

The same conversation then completed two more real turns. Layout revision took
268,847 ms on the phone (Desktop 253,900 ms), retaining total 576 while changing
the four pages to 9:16 portrait. The registered final MQTT envelope was observed
with `foreground=false`, not just a requested-background flag. All five files
passed receipt/save/name checks; the reply was visible and its timer stopped.

Adding item D (quantity 5, unit price 20) took 169,989 ms on the phone (Desktop
152,346 ms). It returned the PPTX and four previews with matching saved hashes.
Native text and inspected data/risk pages contain D=100 and total 676, while
retaining the earlier B revision. Both follow-ups meet the unchanged 300-second
latency target, but this is only two samples.

The new D bar is visually offset to the right. Native slide geometry confirms
the other three bars begin at x=88 points, whereas D and its track begin at
x=100 points. Its width (132 points on a 330-point / 250-unit scale) is correct,
but the inconsistent baseline is a content/presentation defect. Do not report
this turn as fully correct based on successful transport or arithmetic. Keep it
for the subsequent verification/repair turn; no test operator edited the model's
delivered document to make it pass.

Thirteen host catalog/report tests pass, including preservation of an original
timeout even when a late receipt exists. The real two-turn continuation test
passed in 481.592 seconds. Instrumentation completion is not a business-quality
score: creation latency, the initial late-capture failure, and D-bar alignment
remain open findings.

These observations prove a real delivered-output revision/recovery flow and one
background delivery, not ten follow-ups, all Office formats, all business cases,
weak-network resilience, or a stable p95. The 100-case campaign remains incomplete.
