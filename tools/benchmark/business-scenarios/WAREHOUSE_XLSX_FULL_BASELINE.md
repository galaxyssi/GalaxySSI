# Warehouse XLSX: complete eleven-turn baseline

## Scope and identity

Frozen A006 in `artifact-business-100-v2`, catalog SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`,
run `active3-warehouse-xlsx-20260929-v1324`, Active3 SM-T575 Android 1.3.24
(1067), configured Codex gpt-5.6-sol, running Desktop 1.3.23. Backend port 8765
was owned by PID 39336, started at 18:27:11 on 2026-09-29; Electron PID 12060
had not been replaced. This is not acceptance of subsequent merged fixes.

The last continuation completed instrumentation in 1303.275 seconds and skipped
the six existing completed turns. All eleven turns now reached a terminal phone
observation. Instrumentation success means the driver finished, not that business
results passed. The original observations and received files remain unchanged.

| Index | Request | Reply terminal ms | Attachment wait ms | Delivery checks |
| --- | --- | ---: | ---: | --- |
| 0 | Create workbook | 239507 | 45092 | Pass |
| 1 | Correct quantity | 180484 | 2135 | Pass |
| 2 | Mobile layout | 584111 | 7070 | Pass |
| 3 | Add item | 215716 | 2820 | Pass |
| 4 | Source/unknown checks | 227972 | 6940 | Pass |
| 5 | Remove item | 192255 | 90394 | Fail: missing notes preview |
| 6 | Restore initial data | 245831 | 3315 | Pass |
| 7 | Add English summary | 337484 | 90459 | Fail: missing calculation preview |
| 8 | Consistency check | 219221 | 12262 | Pass |
| 9 | PDF export, retain native | 126669 | 3904 | Fail: XLSX omitted |
| 10 | Final native/PDF delivery | 152720 | 90501 | Fail: attachment recovery timeout |

There are seven delivery passes, four delivery failures, ten explicit failed
content reviews and one content-unverified error response. No semantic pass is
claimed. Reply median is 219221 ms, maximum 584111 ms; turns 2 and 7 exceed the
300000 ms target. Eleven observations are insufficient for a stable p95.
The full denominator remains 100 cases / 1100 turns, not this one completed case.

## Content inspection

- Restore correctly returned quantities 16/26/21, amounts 192/208/210 and total
  610 in formulas and cached chart data. The chart again used an axis minimum
  of 180, and both unsupported yuan currency and right-edge clipping remained.
- Bilingual notes preserved Chinese and added English, but propagated the
  unsupported currency as CNY. The calculation preview missing on the phone
  is not certified by looking at a Desktop copy.
- The consistency-check calculation preview was byte-identical to the restore
  preview. Correct arithmetic did not remove its presentation defects.
- Exported PDF is a real three-page document. Re-rendering page 2 with pdftoppm
  at scale 1600 produced SHA-256
  `7cdb15e38505fc4eb2379f084dfa7816f8392096b6c7e2ea5a47158e566854c1`,
  identical to the received page image, including the defects. Native XLSX was
  absent from this turn's delivery, despite the explicit retain-original request.
- Last Desktop task `3bd3cf09-537b-3fa3-9f02-fd7b49d815d6` ended `failed`
  with `Phone attachment recovery timed out`. It was not still generating.
  This failure originated in the history attachment request broker's 120-second
  wait. It establishes the failure location, not why the phone request failed.

## Recovery and process-lifetime caveat

The missing turn-5 notes preview was eventually acknowledged as stored at Unix
second 1790690728, after the resumed test started. Earlier post-completion
transport observations included failed broker acknowledgements at approximately
4.8, 32.8 and 63.6 seconds. These facts do not identify a particular public broker
as the cause and do not retroactively pass the original 90-second observation.

Immediately after this instrumentation completed, `adb shell pidof
com.galaxyssi.chat` returned no process (exit 1). The driver also closes its test
window in `finally`. Thus time between completed instrumentation sessions must
not be presented as continuous background-app uptime. Background task coverage
comes only from explicitly recorded in-run background turns. The final recovery
timeout happened while instrumentation was live, so this caveat does not excuse it.

CPU samples include instrumentation and transcript polling. USB-connected 100%
battery readings do not measure energy usage; no battery-life claim is made.

## Follow-up

PRs 3282/3284/3286 address original-format delivery contracts, authoring quality,
layout diagnostics and a separately reproduced localized converter failure.
They still require an updated-running-Desktop model/phone validation. Prioritize
history attachment recovery and delivery retries before expanding the expensive
full campaign. Do not increase deadlines, rewrite failing observations, or label
the whole 100-case objective complete based on this baseline.
