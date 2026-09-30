# Warehouse Image Source-Fidelity Review

This is additional baseline evidence, not a new passing run or a production
fix. The frozen artifact campaign remains 100 cases / 1,100 turns, catalog
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.

## Exact Evidence

Device: Active3 SM-T575, Android 1.3.26 (1069).
Run: `active3-warehouse-image-20260930-v1326`, A008, five observed turns.
Conversation: `f01fd55f-e0fd-447b-9bc7-5c710d46eba9`.
Raw A008 report SHA-256:
`70839b41e821f3b5876f43462b280a29df8057e8d3d79a2020ce1811e6bd5548`.

The separate `reviews/active3-a008-20260930.json` binds four failed content
verdicts to their exact original turn records and received artifact hashes.
Every cited PNG was opened and visually inspected at its actual 1200x1600
resolution. Hashes were independently recomputed and matched the phone report.
The raw report, images and screenshots were not modified or committed.

## Findings

| Turn | Request | Numeric check | Content verdict |
| --- | --- | --- | --- |
| 1 | Increase the second quantity by 7 | 216 + 280 + 230 = 726 | Fail: unsupported currency |
| 2 | Improve mobile layout | Same values and 726 retained | Fail: unsupported currency |
| 3 | Add a fourth record | 216 + 280 + 230 + 100 = 826 | Fail: unsupported currency |
| 4 | Check missing evidence | 826 retained; owner/date/returns unconfirmed | Fail: unsupported currency remains |

The input specifies quantities and unit prices but no currency. Each image
nevertheless labels its amounts, totals and chart with yuan. Even the source
check revision retains this invented unit while saying unknown items were not
invented. A later request to preserve data does not make an earlier generated
assumption into source evidence.

The numeric values, record ID and requested revisions are visible and correct
in the inspected exports. Chinese is readable and the larger layout does not
show obvious clipping. These limited positive checks do not turn the full
content verdict into a pass or prove every UI control works.

Turn 0 had no audited received artifact and its current-reply visibility check
failed. It remains a delivery/visibility failure; no image-content approval is
invented for it. Turns 1-4 retain their successful delivery/hash/save-API checks,
focused stable reply captures and stopped timers separately from these content
failures. No new fullscreen/open/save UI audit was performed in this review.
Turns 5-10 are unobserved in this checkpoint.

## Existing Fix and Deployment Boundary

PR #3284, already merged, added the source-unit rule for all required artifacts,
including PNG charts; the corresponding test explicitly includes downloadable
PNG output. Do not add a duplicate Office-only patch for this finding.
The baseline was produced by the still-running Desktop 1.3.23 instance, not a
fresh instance with that authoring rule. The newer policy is a model instruction,
not a deterministic accuracy guarantee. It still needs a fresh real run with
these unchanged prompts and separate content inspection after deployment.

The pending transport fix and the current Desktop-exit prerequisite also remain
open acceptance work. This review does not resolve the A007 final-delivery
failure or justify continuing its failed checkpoint as though it passed.

## Reporting

Use the original run catalog/report and pass this review JSON explicitly to
`report.py --reviews`. Expected result for this five-turn checkpoint: four
delivery checks passed, four explicit content failures, zero semantic passes,
and the full 100-case / 1,100-turn denominator retained. It remains incomplete.
No benchmark prompt, answer oracle, timeout or product setting was changed.

The real report accepted all four evidence bindings and produced those exact
counts. All 32 host catalog/report/content-review/timing regressions passed.
