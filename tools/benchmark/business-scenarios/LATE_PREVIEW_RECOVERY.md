# Late warehouse preview recovery

## Preserved original failure

In frozen case A005, run `active3-warehouse-docx-20260929-v1324`, turn 7
failed its 90,441 ms attachment observation window. Two declared PNG pages were
missing; the third PNG and DOCX arrived. This remains a failed initial delivery,
not a newly passing turn. No original report, checkpoint or artifact was replaced.

## Separate recovery observation

At 20:40 on 2026-09-29, read-only recapture still showed two missing previews.
Their complete files and incoming chunk directories were absent on Active3.
Desktop retained their source files and marked them pending in its delivery
ledger. The original outbound records had exhausted six attempts. Two replay
records were queued with zero attempts for about 550 seconds at inspection.

After a normal MainActivity launch at approximately 20:45:39, both files appeared
on Active3, and the Desktop ledger recorded their stored acknowledgements:

| Page | Bytes on phone | Desktop stored timestamp (Unix seconds) |
| --- | ---: | ---: |
| 1 | 169795 | 1790685976 |
| 2 | 156356 | 1790685948 |

The two replay records then left the outbound queue. This proves eventual
recovery, not that foregrounding was the root cause or that routine background
delivery is reliable. Broker causality and the original retry failures remain
unresolved. Historical diagnostic counters are not current traffic rates.

Read-only capture `capture-audit-1790686278836` resolved the original task/reply
identity. Its first-preview UI audit clicked the thumbnail, opened full screen,
and saved a new download with SHA-256
`b345077b3918cc61166492f42ba69902166e1bf06ad30e0f1e01e68acc206e20`.
The screenshot shows readable Chinese v08 content and pending unknown claims.
This audit covers page 1 only, not all attachments. It is not a timer assertion:
the recapture's process row was absent and its `timer_stopped` field was false.
Original live timer observations are unchanged. Raw files remain local.

## Diagnostic improvement, not a delivery fix claim

Desktop 1.3.25 adds constant receive-phase labels and numeric OS error codes to
the existing failure log. This distinguishes route lookup, peer controls,
receipts, chunk recovery, Signal/replay handling and application storage.
Exception text, filenames, message bodies, topics and credentials are not added
to the log. Normal delivery, authentication, retry bounds and failure return
values are unchanged. The running Desktop has not been replaced, so these new
diagnostics have not yet observed the live failure.

Five targeted failure/privacy regressions plus 49 existing durable-delivery,
artifact-lane and artifact-delivery tests pass in an isolated runtime. The 61
Desktop JavaScript regressions pass. The on-device recapture passes one test.
The full 100-case / 1,100-turn campaign remains incomplete; this follow-up must
not increase the original semantic or on-time delivery pass counts.
