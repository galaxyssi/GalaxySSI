# Office Runtime and Ten-Follow-Up Acceptance

This is incremental evidence for the frozen 100-case, 1,100-turn artifact
campaign, not a replacement benchmark or a claim of full completion. Only
Active3 (SM-T575) was operated. Private logs, screenshots and delivered files
remain local.

## Completed A003 Conversation

Run `active3-artifacts-v3-20260929-desktop1319` used Android v1.3.22 (1066)
and Desktop v1.3.19. The late-result receipt allowed continuation without
resending the first request or rewriting its timeout. The continuation driver
finished its last seven turns in 1,337.371 seconds.

| Turn | Operation | Phone elapsed, ms | Delivery/container/save checks |
| --- | --- | ---: | --- |
| 0 | Initial PPTX | 600356 observation timeout | Original failure retained; separate late receipt |
| 1 | Revise B | 151263 | Pass |
| 2 | Mobile layout | 268847 | Pass |
| 3 | Add D | 169989 | Pass; visual baseline defect recorded separately |
| 4 | Check unknown facts | 155301 | Pass |
| 5 | Remove C | 147824 | Pass |
| 6 | Restore original data | 203688 | Pass |
| 7 | Bilingual content | 224302 | Pass |
| 8 | Verify consistency | 118884 | Pass |
| 9 | Add PDF and previews | 200195 | Fail: requested native PPTX not attached |
| 10 | Final delivery | 123464 | Pass: PPTX, PDF, four previews |

All ten follow-ups returned and stopped their visible timers within the
unchanged 300-second per-turn target. Nine passed the limited delivery check.
This is not a 90% content-quality score. The initial Desktop generation took
668,524 ms and remains a latency failure. There are insufficient samples for p95.

Native slide tables confirm the intended sequence: 520, 576, 676, 496, then
restored 520. The final file has four editable slides, its PDF has four pages,
and both contain original quantities 13/23/18, prices 12/8/10 and amounts
156/184/180. The inspected bilingual pages preserve Chinese content and mark
unknown owner/date/realized revenue as unconfirmed. Final data-page rendering
agrees with the native table and PDF text.

The D-bar offset observed after adding a record was visibly realigned during
the later deletion turn. That does not retroactively pass the earlier output.
Background final delivery was directly observed in turn 5, not inferred from
the test requesting background mode. Turn 6 resumed the conversation after the
driver's window-restore step; this is not process-death recovery evidence.

## Changes Under Test

Desktop v1.3.20 adds python-docx, python-pptx, openpyxl and XlsxWriter to the
backend requirements and the bundled-runtime dependency check. Office creation
requests receive the exact interpreter and discovered modules. Discovery does
not claim successful import, rendering or content verification. Other requests,
plan-only mode and read-only screen analysis do not receive this extra context.

The preview tool now includes the unchanged native original in its output file
list by default. A task-local input/temp original is copied into the same
atomically published preview directory after conversion and hash verification.
An original already in outputs is referenced without another copy. Explicit
preview/PDF-only callers can set `include_original=false`. Failed conversion or
changed source/copy publishes no partial result. Existing container and active
content restrictions remain unchanged.

Tests exercise real native document/table creation, editable PowerPoint chart
data and embedded workbook presence, and XLSX formulas plus independently
computed cached values. These round trips are not renderer or visual tests.

118 isolated backend tests and 13 catalog/report tests pass. Packaging-script
syntax and whitespace checks also pass. A full packaged Windows release was
not built in this iteration.

## Post-Change Word Sample

Run `active3-office-runtime-20260929-desktop1320`, case A001 turn 0, used the
same frozen catalog on Active3. Desktop completed in 142,953 ms and the phone
in 154,936 ms. The driver completed in 190.179 seconds, including setup and
evidence collection. The actual public tool calls used python-docx and
`galaxyssi_office_preview`. One 39,401-byte DOCX and two page previews arrived,
with correct saved hashes, a visibly rendered reply and stopped timer.

Native inspection and both page images confirm three numbered chapters,
editable paragraphs/tables, quantities 11/21/16, prices 12/8/10 and amounts
132/168/160 totaling 460. Owner, actual date and realized revenue remain marked
unconfirmed. The document assumes yuan as the currency although the synthetic
input did not specify a currency; do not treat this as fully verified business
content. Mobile readability and open/save UI still need follow-up review.

A separate real Microsoft Office conversion of this downloaded DOCX from an
isolated task's temp directory passed: unchanged native hash, two-page PDF,
two PNG pages and `original_included=true` (four published files). This proves
the native-copy path with a real converter, not just a mocked subprocess.

## Remaining Findings

- A repeat live initial-generation sample is needed before claiming a latency
  improvement from the added authoring runtime.
- The cross-format native-file omission has a real post-fix tool conversion
  check, but still needs a repeat model-driven cross-format phone turn. An
  updated tool contract alone cannot prove every model uses it correctly.
- Some PNG previews are JPEG-encoded by the existing bounded image transport,
  while their display labels still say PNG. Final native/PDF files are intact,
  but this does not meet strict original-PNG delivery expectations.
- The existing preview guard rejects embedded Office objects, including chart
  workbooks. Installing python-pptx does not establish native-chart preview
  support. Any future exception needs bounded validation and security tests.
- Full visual/content review of every version, all native formats, image-edit
  cases and the other business scenarios remains incomplete.

Source references for the authoring constraints:
[python-pptx charts](https://python-pptx.readthedocs.io/en/latest/user/charts.html),
[XlsxWriter formulas and cached values](https://xlsxwriter.readthedocs.io/working_with_formulas.html).
