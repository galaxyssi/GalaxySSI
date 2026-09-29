# Native Chart Preview Follow-Up

This continues the frozen 100-case / 1,100-turn artifact campaign. It does not
change prompts, expected data, latency targets or historical failures. Desktop
version is 1.3.21; the Android test device remains Active3 (SM-T575) only.

## Defect and Boundary

The Office preview worker previously rejected every embedded object, including
the passive XLSX data that python-pptx creates for an editable native chart.
That prevented using the existing renderer for otherwise ordinary charts.

The exception is deliberately limited to PPTX chart-owned XLSX packages:

- The internal package relationship must belong to a chart and match that
  chart's external-data reference. Other embeddings, OLE references, ambiguous
  relationship IDs and unreferenced embedded files are rejected.
- The nested workbook permits only known data, style, theme and document
  property parts with matching content types. Macro-enabled types, formulas,
  defined names, external relationships, connections and nested objects remain
  rejected. Formula-bearing or other unsupported embedded workbooks are not
  silently flattened or treated as safe.
- XML/entity, duplicate-name, package-target, entry-count and expanded-size
  checks run before the converter sees the file. Chart packages have an 8 MiB
  compressed limit, 32 MiB expanded limit each and 64 MiB total expanded limit.
- Existing task-path validation, read-only Office worker, source hashing,
  copied-source validation and atomic publication remain in force. Originals
  are not rewritten to remove their editable chart data.

This is not a general sandbox for arbitrary Office documents. Other embedded
objects and unsupported workbook features still return an explicit unavailable
preview result.

## Real Converter Evidence

A python-pptx fixture with an editable three-category column chart (156, 184,
180; total 520) was rendered by the real Microsoft Office worker to a one-page
PDF and PNG. Both labels and values were visually inspected. The original
PPTX hash stayed unchanged and the output included the native file. This is a
local converter probe, not a phone/model business-case completion.

Thirty warm validations of that fixture measured 3.082 ms median, 3.898 ms p95
and 7.947 ms maximum. These numbers measure only local container validation,
not model inference, Office export, network transport or mobile UI latency.

## Remaining Campaign Work

The full PPTX rerun with native charts, remaining Excel follow-ups, image
annotation workflows, remaining scenarios and complete visual/content reviews
must still be tracked separately. PNG-to-JPEG transport/name inconsistency
remains open and is not fixed by allowing passive chart workbooks.

## Active3 Excel Three-Turn Evidence

Run `active3-native-office-20260929-desktop1321` used the unchanged A002 prompts
and catalog SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
The device was SM-T575, Android 1.3.22, Desktop 1.3.21, with the real remote
Codex model `gpt-5.6-sol`. Instrumentation completed in 930.623 seconds.

| Turn | Desktop task ms | Phone reply-terminal ms | Artifact audit ms | Reply target |
| --- | ---: | ---: | ---: | --- |
| Create v01 | 305852 | 332171 | 4927 | Fail |
| Revise quantity v02 | 230622 | 251303 | 955 | Pass |
| Portrait layout v03, background | 292900 | 314225 | 14166 | Fail |

All three replies settled and their timers stopped. Each delivered a native
XLSX and three sheet previews; the save API succeeded and downloaded bytes
matched received bytes. The third reply was received while the app was in the
background. This proves delivery for these samples, not a broad reliability
rate or complete visual open/save-button acceptance.

Read-only inspection of all three received XLSX containers confirmed the three
required sheets, editable formula cells and a native chart with cached data.
The initial quantities 12/22/17 yielded amounts 144/176/170 and total 490.
The next two versions preserved 12/29/17, amounts 144/232/170 and total 546.
Formula references and chart caches agreed with those values. The original
version remained separate; all v03 sheets were portrait. These checks do not
prove recalculation after arbitrary future edits in every spreadsheet engine.

Visual review found the initial and revised landscape calculation previews
clipped the bottom of the chart and category labels. The v03 portrait previews
showed the complete chart, labels, table and notes; all three v03 pages were
reviewed. The model nevertheless introduced a yuan currency unit absent from
the input. That unsupported assumption remains a content defect, not a pass.

The nine preview payloads decode successfully but use JPEG bytes despite PNG
names. The existing device verifier checks decodability rather than matching
the image signature to the requested extension, so its `correct=true` is only
a delivery/container result and must not count as PNG-format acceptance.

Timing scope also needs refinement: current `elapsed_ms` ends at reply/task
terminal state, before artifact collection. `artifact_wait_ms` includes both
waiting and file/hash/save audit work, not only network waiting. Neither is a
complete user-visible artifact-ready latency measurement. Historical results
are retained; separate phase timing and strict image-format checks are follow-up
work, not retroactively applied to make these samples pass.

## Automated Regression

127 isolated backend tests passed across chart safety, Office preview/worker,
authoring runtime, execution harness, artifact request/delivery/ownership,
blob sources and conversation-artifact recovery. The nine new chart tests
include valid passive charts, macros, nested objects, external relationships,
formulas, content-type changes, DTD/UTF-16 XML, ambiguous relationship IDs,
encoded targets and expanded-size limits. Full repository CI is not asserted.
