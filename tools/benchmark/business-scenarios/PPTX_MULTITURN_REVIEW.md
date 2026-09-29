# Active3 PPTX revision content and UI evidence

## Scope and provenance

Run `active3-warehouse-pptx-20260929-v1325`, case A007, Active3 SM-T575.
The new follow-ups 5 and 6 ran on Android 1.3.26 (1069) through the configured
real Codex target and the existing Desktop runtime. Desktop repair PRs
#3293, #3295 and #3296 were not deployed by this test. This evidence-only PR
does not change production versions, route selection, prompts or thresholds.

Seven turns (0-6) have now reached a terminal reply in this run. Follow-ups
7-10 remain unexecuted. Earlier missing-delivery observations on turns 0, 2
and 3 are retained; a later UI audit is not a replacement for those results.
The full frozen denominator remains 100 cases and 1,100 turns, catalog SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.

The local report lives under
`%LOCALAPPDATA%/Temp/galaxyssi-business-eval/active3-warehouse-pptx-20260929-v1325`.
After appending the two new turns, `A007.json` SHA-256 is
`902c56ed54d386d0ea05678ee228e88f9092c77580591d0388edbee0e010cfc0`.
The same digest remained after all UI-only audits. Original model replies,
artifact hashes and timing observations were not rewritten.

## Native content review

`reviews/active3-a007-20260930.json` records four evaluator judgments bound to
the exact observed turn digests and checked file hashes. These are explicit
reviews, not model self-grading or a substitute for transport/UI checks.

| Turn | Request | Native and preview observations |
| --- | --- | --- |
| 3 | Add Ding, quantity 5, price 20 | Four editable slides; amount 100 added; total quantity 78 and amount 796. Active slide-2 chart and embedded workbook have 204/272/220/100. The received three previews are readable. The missing second preview remains a delivery failure. |
| 4 | Check owner/date/returns sources | All four previews inspected. Missing facts explicitly marked pending confirmation and sources not supplied. Numbers remain 796/78, currency remains unspecified. |
| 5 | Delete Bing, retain revised Yi and Ding | Table, active chart and workbook agree at 204/272/100, quantity 56, amount 576. Deleted label absent from PPT XML and embedded workbook XML. All four previews inspected. |
| 6 | Restore original three items | Restores quantities 17/27/22 and prices 12/8/10, total 66 and amount 640. Ding removed; mobile portrait layout retained and title/data slide explicitly identify a new restored version. All four previews inspected. |

The unchanged page 3 was checked by matching its already visually inspected
SHA-256. Turns 3-4 contain unused old chart parts, but relationship inspection
confirmed the visible slide references the updated chart. Turn 5's returned
package contains one chart and no deleted label in the inspected XML. This is
not a generalized sanitization guarantee for all Office formats or metadata.

## New real-model measurements

| Turn | Reply terminal | Additional attachment wait | Audit | UI observation | Observed total |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5 | 226,027 ms | 26,148 ms | 514 ms | 2,683 ms | 255,403 ms |
| 6 | 162,976 ms | 1,740 ms | 392 ms | 2,716 ms | 167,854 ms |

Both delivered the editable PPTX and all four PNGs, passed container/save API
and download hash checks, rendered the target reply, and stopped the process
timer. These observations include test overhead. They do not establish a
stable p95 or isolate provider time from transport time. The runner completed
in 428.750 seconds; its `OK` means the driver completed, not the whole business
campaign passed.

## Actual phone UI open and save

The separate UI audit uses the installed multipage test driver from #3294.
It sends no new model request. Each declared image must have a matching local
hash and unique thumbnail, open full screen, and create a new matching
MediaStore download through the visible Save control.

| Turn | Audit directory | Pages | New download IDs | Runner time |
| --- | --- | --- | --- | ---: |
| 4 | `capture-audit-1790725515243` | 4/4 | 1000003481-1000003484 | 17.872 s |
| 5 | `capture-audit-1790725575267` | 4/4 | 1000003485-1000003488 | 20.048 s |
| 6 | `capture-audit-1790725621708` | 4/4 | 1000003489-1000003492 | 19.811 s |

All three persisted audits have `status=completed`. Fullscreen screenshots of
the data pages visibly show 576 and 640 with their matching tables and charts.
Temporary image-title toasts appear near the lower margin; these captures do
not certify a permanently unobscured interface. Native PPTX save API/hash was
tested separately; no claim is made that Android opened the PPTX in PowerPoint.

An initial turn-4 audit (`capture-audit-1790725398116`) omitted
`business_artifact_ui_all=true` and therefore verified only one image. Its
9.166-second success is retained and is not counted as multipage acceptance.
The installed test package already supported all-image checks; no rebuild was
needed after correcting the invocation.

Example all-page invocation (replace only the explicit turn index):

```text
adb -P 5038 -s R52R90282TY shell am instrument -w -r
  -e class com.galaxyssi.chat.BusinessScenarioLiveDeviceTest#recaptureCompletedTurns
  -e business_recapture true
  -e business_run active3-warehouse-pptx-20260929-v1325
  -e business_cases A007 -e business_capture_turn 6
  -e business_artifact_ui true -e business_artifact_ui_all true
  -e business_device_model SM-T575
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Historical timer rows may no longer be visible in a recapture. Their absence
does not override the original live stopped-timer observations.
