# Warehouse spreadsheet live acceptance

## Scope

Case A006 remains part of the frozen 100-case / 1,100-turn artifact campaign.
Run `active3-warehouse-xlsx-20260929-v1324` uses catalog SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`,
Active3 SM-T575, Android 1.3.24 (1067), the running Desktop 1.3.23, and real
remote Codex `gpt-5.6-sol`. The prompts and latency targets were not changed.
This checkpoint runs the first three turns; eight remaining turns are still
required. It is not a replacement three-turn suite.

## Observed results

| Turn | Request | Reply-terminal ms | Additional attachment-presence wait ms |
| --- | --- | ---: | ---: |
| 0 | Create inventory workbook | 239507 | 45092 |
| 1 | Increase item B quantity by 7 | 180484 | 2135 |
| 2 | Larger mobile layout, background delivery | 584111 | 7070 |

All three observed turns delivered a native XLSX and three real PNG previews, with
container, filename version, saving and downloaded-byte hash checks passing.
Their reply captures were focused and stable, and timers stopped. These are
delivery checks, not semantic acceptance. The first turn's audit-inclusive
duration was 288283 ms; the next two were 185572 and 594656 ms. Turn 2 fails the
unchanged 300000 ms reply target. The real test completed in 1071.940 seconds.
Turn 2's registered final event has `foreground=false` and `background=true`,
so background receipt was observed, not merely requested. Three samples cannot
establish a stable p95 or energy
usage; USB-powered temperature/battery samples are not energy measurements.

Read-only inspection of the phone-delivered XLSX confirmed the three required
sheets, native editable formulas and a native chart. Initial quantities
16/26/21 and prices 12/8/10 produce 192/208/210, total 610. Version 2 changes
only B to 33 and 264, total 666; version 3 retains these values and formulas while
moving the calculations down one row and making all three sheets portrait.
Formula caches and chart values match these
values. Cached agreement is not proof of recalculation after arbitrary edits
in every spreadsheet engine.

## Confirmed quality defects

The input does not specify currency. All three replies and workbooks nevertheless
use yuan currency labels and the `¥#,##0.00` number format. This is an unsupported
assumption, even though the arithmetic is correct. The initial column chart
auto-scales from 180 to 215, exaggerating differences in bar length. Its native
axis has no explicit minimum. The revised chart starts at zero, but this does
not retroactively accept the initial chart. The final three previews have
larger readable text, but the calculation preview visibly clips the chart's
right frame edge. Data labels remain visible; this does not justify the reply's
blanket no-clipping claim. Original evidence remains unchanged.

First native workbook SHA-256:
`fe8fbff1c35c62eb61001e5af7b2fefb4650d5a33737fafa40063eb9a2b8952d`.
Screenshots and original files remain local, outside the repository.

Read-only UI audit `capture-audit-1790688238459` clicked version 3's first
preview, opened full screen, and saved a new download. Its SHA-256 matches
`ea82137ad10a385de5d068975879641bb97a24fe63905114aad5809f2ee7be30`.
This covers one preview's UI controls, not every attachment or native Excel UI.

## Bounded quality improvement

Desktop 1.3.26's artifact contract now explicitly preserves source units and
currency, including cell formats and chart labels. Unknown units remain unknown
rather than being inferred from language or locale. Magnitude-encoding bar and
column charts require a zero baseline unless an explicit user/template request
requires otherwise, in which case the scale must be disclosed. Line, scatter
and logarithmic charts are not blindly forced to zero. Saved originals and
actual rendered previews must agree, and full chart/drawing extents must fit
the printable area without making text illegible. The rules apply even when optional Office
authoring libraries are absent; plan-only and screen-analysis paths remain
read-only.

This is a generation-contract improvement, not deterministic enforcement or a
claim that model quality is repaired. The current live run uses the old running
Desktop and must retain the discovered defects. No returned workbook is edited
by the evaluator to make it pass. A deployment and fresh unchanged-prompt run
are needed to establish improvement.

## Performance evidence and remaining work

For turn 0, Desktop's monotonic journal records five outbound packets queued
within 3.5 seconds after task completion. Initial dispatches extend to 20.6
seconds; a later wire attempt occurs at 51.5 seconds and the last peer receipt
at 63.6 seconds. This shows post-generation transport delay/retry, not a
45-second file hash operation: phone file auditing took 370 ms. It does not
identify which broker or network segment caused a missing initial delivery.

Continue the remaining case turns and full campaign, investigate delivery
tail latency, verify native recalculation and rendered source fidelity, and
deploy/retest the new contract. No full semantic or whole-campaign pass is
claimed. Automated checks: 48 isolated backend tests, 61 Desktop JavaScript
tests and 21 host catalog/report/timing tests pass. Both the real three-turn
instrumentation run and separate read-only open/save test finished successfully;
their runner success does not override the recorded quality or latency failures.
