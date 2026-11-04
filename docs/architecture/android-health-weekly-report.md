# Android Weekly Health Report

The Health Center function page opens a report for the last seven completed
calendar days. Previous/next navigation shifts by a week in the report's
time zone. Day boundaries are calendar-based, including daylight-saving
changes. The page reports valid days, days with records, and record counts
separately. Missing values never become zero.

## Measurement And Provenance Contract

- Confirmed, non-deleted self observations are read through the existing
  indexed 30-record export cursor. Drafts, other owners and other metrics
  do not contribute. Aggregation holds at most seven daily cells per metric
  and fourteen additional cells for the optional sleep baseline.
- Exact sleep observations are normalized to minutes, temperature to
  Celsius, and the report averages available daily means. Steps use the
  last cumulative count of each local day. Blood pressure counts valid
  systolic/diastolic pairs, not individual components or pulse readings.
- Sleep comparison uses the immediately preceding 14 days. At least five
  usable days in the week and ten in the baseline are required. This is a
  descriptive comparison, not a diagnosis, alert, or advice from a model.
- The report records a method version, range, zone, and version fingerprint.
  A single indexed read captures the selected metric revisions. The reads,
  linked source cohorts and export are checked against those revisions.
  A selected-metric change conservatively invalidates the preview even if
  the changed record was outside its date range.
- The native report and export are subject to local confirmed-metric
  authorization. The encrypted access history records the selected
  metric/date scope, baseline range, and whether measurement rows were
  included, not the measurement values or record IDs.

## PDF Review And Save

The user selects metrics and may separately include the sleep comparison and
underlying measurements from the seven-day window. The preview shows the
same statistics, comparison, and optional paged measurement rows. These
rows include stored values and units, time, source type, and record/revision
identity, not notes, profile fields, unconfirmed inputs, source images, or
baseline measurement rows.

Saving requires an explicit unencrypted-PDF acknowledgment and Android's
create-document result. The reviewed version is checked again; consent
cannot silently switch to a newer snapshot. The PDF is rendered without a
plaintext staging file and written only to the chosen URI. On a failed write
or invalidation detected during saving, deletion of a destination that was
actually opened is attempted; an external provider may not support deletion.
No upload, automatic send, or share intent is involved. The optional PDF
appendix is capped at 500 measurements with an explicit pre-save warning
and no silent truncation; the dedicated record export supports larger sets.

## Verification

Version 0.1.7.28 (Android 1441) was built and cover-installed on Galaxy
Tab Active3 (SM-T575). The focused suite passed 280 JVM tests, 242
non-visual device tests, and 39 native UI/lifecycle tests with no skips.
The report, export options, and default disabled save action were inspected
on the tablet. Tests verified multi-page Android PDF rendering, revision
changes, consent, and a real write through an isolated content URI after an
intercepted create-document result. External document-provider compatibility
and interruption during the real system picker remain separate acceptance
items. No test measurement was written into the production archive.
