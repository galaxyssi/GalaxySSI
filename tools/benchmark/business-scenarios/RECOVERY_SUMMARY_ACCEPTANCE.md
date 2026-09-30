# Recovery summary display boundary

## Real observation

During Active3's A007 turn 4, the phone displayed a Planning section containing
a JSON array with `GALAXYSSI_RECOVERY_ACTION_V1`. This is internal recovery
protocol text, not a useful progress update. The observation came from the real
running Desktop 1.3.23 and Android 1.3.26 (1069); no transcript was injected.

The Codex adapter accepts provider-supplied public summary text separately from
raw reasoning. Its summary cleanup bounded length and stripped NULs but did not
exclude the internal recovery marker. Both a completed summary and a buffered
summary could therefore become a visible narration event.

## Narrow repair

Suppress a public reasoning-summary item containing the exact reserved recovery
marker. Do not fall back to raw reasoning. Continue clearing the summary buffer
and publishing generic task liveness. Normal public summaries, commentary,
actual final replies and recovery decisions retain their existing paths.

This is specifically a summary-display repair, not a general final-output
protocol sanitizer. It does not remove control data before the recovery
controller can parse it, and does not change attachment restoration or retries.
Desktop version is 1.3.30; 1.3.28 and 1.3.29 are reserved by earlier open fixes.

## Verification

The new tests failed before the fix (five failed assertions/subcases). They
cover the observed JSON-array form, full recovery block, fenced array, footer,
and split buffered deltas. They also require ordinary summaries to remain visible,
no raw-reasoning fallback, buffer cleanup, generic liveness and an unchanged
actual recovery reply that still decodes to RETRY.

After the fix, 76 isolated backend tests passed (Codex conversation events,
model recovery and task latency). All 61 Desktop JavaScript unit tests passed.
No live runtime files or user databases were modified by those tests.

The separate `scripts/check.js` gate failed at line 818: it requires the literal
`const backendDataEntries = ["web_source_sites.tsv"]`, while the packager already
includes `research_contract` as a second entry. Both files are unchanged from
origin/main. This pre-existing static-contract mismatch is not hidden or changed
in this narrowly scoped fix; the full Desktop check gate is not reported green.

The running Desktop has not been replaced, so the repaired display boundary
is not yet accepted on the physical phone. This is not a claim that the broader
attachment delay, missing previews or business quality problems are fixed.

## Same-session PPT continuation

Run `active3-warehouse-pptx-20260929-v1325` continued A007 turns 3 and 4 without
resending earlier turns. The runner finished in 506.365s. Both replies became
terminal and their phone timers stopped; focused captures were stable.

| Turn | Reply terminal | Additional attachment wait | Observed total | Delivery check |
| --- | ---: | ---: | ---: | --- |
| 3: add Ding, 5 x 20 | 192.878s | 90.084s | 286.871s | Failed: page 2 unavailable at deadline |
| 4: verify unknown sources | 181.914s | 30.153s | 215.837s | Native PPTX and four previews verified |

Turn 3's reply reports quantity 78 and amount 796. Turn 4 reports unknown owner,
actual date and real benefits as unconfirmed. These text observations do not
constitute complete native-file and preview content reviews. Do not count the
runner's success as a semantic pass or replace the missing-page failure.

The appended five-turn A007 report SHA-256 is
`d2b312d3b520c7c020fcec92bd12d83904d9ca661cbbf04ea4e35dc5592f6639`.
Private artifacts and screenshots remain local. Six A007 follow-ups and the
full frozen 100-case / 1,100-turn campaign still require completion. Later
availability must be recorded separately from the original delivery deadline.
