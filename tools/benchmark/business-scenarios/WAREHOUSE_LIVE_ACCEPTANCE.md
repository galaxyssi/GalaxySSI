# Warehouse document live acceptance

## Scope and preserved failure

This is A005 of the frozen 100-case / 1,100-turn campaign, not a smaller replacement
suite. Only SM-T575 / Active3 was operated. Android 1.3.24 (1067) was installed;
Desktop remains 1.3.23. PR #3279's routing repair is merged.

The original `active3-warehouse-docx-20260929` run remains a 900,174 ms observation
timeout. A later observer confirmed that its phone parent had still not settled.
Explicit cleanup matched catalog, run/case, conversation, exact goal and workspace
identity before using normal supervisor cancellation. Receipt
`A005-0-cleanup-1790681780047.json` records RUNNING -> CANCELLED and stopped
execution. No original report, conversation or artifact was deleted or rewritten.

## Fresh real model run

Run `active3-warehouse-docx-20260929-v1324`, configured Codex gpt-5.6-sol:

| Turn | Request | Phone terminal ms | Audit-inclusive ms | Result |
| --- | --- | ---: | ---: | --- |
| 0 | Create editable stocktaking DOCX | 190759 | 215872 | DOCX + 2 PNG pages; total 580 |
| 1 | Increase item B quantity by 7 | 187171 | 189293 | DOCX + 2 PNG pages; B=32, amount=256, total=636 |
| 2 | Larger mobile-readable layout | 134794 | 138753 | DOCX + 3 PNG pages; data still 636; received in background |

All three original/preview versions passed container, versioned filename,
receipt and downloaded-byte hash checks. All three current reply rows were
visibly captured with stable frames and focus, and all timers stopped. Turn 2's
registered final event has `foreground=false`, not merely a planned background flag.
This three-turn test completed in 547.323 seconds without resending the old run.

## Independent content and visual review

The returned DOCX containers contain real paragraphs and three native tables, no
embedded page images. Three explicit section headings are present. Native rows
and all seven delivered preview pages were inspected. Original data (15x12,
25x8,20x10) totals 580; B's revision is 32x8=256 and total 636; A and C remain
unchanged. Owner, actual date and actual benefit remain pending. Currency is also
explicitly unspecified. The document uses the generic quantity unit 'items', which
was not provided as a specific inventory unit; do not treat that as established
business master data.

Turn 2 increases direct font sizes (half-points 18/19/20/21/30/44 become
22/23/24/26/36/50), retains the revised native table and separates sections across
three pages. Inspected previews have readable Chinese and no clipped/overlapping
text. This proves observed content/layout agreement, not an independent pixel-
identical rerender of every original. The Desktop trace records Office preview
completion, but no source-hash renderer receipt was captured by this phone driver.

Native DOCX hashes for versions 1, 2, 3:

- `e58a638b8c110a05855b6917821e70a1c8c0742c6adb20e70f23f4369511e3fa`
- `d644a2cefcdface2d28a88b2940ba573dcad174e2a5e21279c10411a905f5b5a`
- `fef66fe6ce904538b364172d844450b77c44fde4fb7a83589ffdd602a097a4a5`

Read-only UI audit `capture-audit-1790682450642` passed thumbnail click,
fullscreen opening and Save for version 3's first preview. New download 1000003348
matches SHA-256 `1922c16ec0f44b8f7ac46f0a753f21d32eac95bbc4cf77d2c8289d2757652125`.
This does not claim that a native Office editor is installed on the phone.

## Performance findings and remaining work

All three turns meet the unchanged 300-second reply target, but this does not
establish stable p95. Boundary PSS spans 304857..408941 KiB, not a continuous peak;
USB-powered battery readings cannot establish energy use.

Turn 0 required another 21,993 ms for all artifacts to become locally available
after the terminal reply. Turn 1's Desktop duration is 109,228 ms, versus phone
terminal 187,171 ms. Desktop queued the reply at 1790682135955; the phone observed
the final envelope at 1790682206920. Cross-device wall-clock skew prevents an
exact network-only duration, but the evidence exposes a material post-completion
delivery delay. Its cause remains unproven; do not blame a specific public broker.

Continue turns 3..10 on this same checkpoint, preserving all previous versions.
Investigate delayed delivery, collect source/preview provenance, and broaden to
the remaining cases. No full A005 or whole-campaign completion claim is made.

Screenshots, native files and raw logs remain local and are not committed.

## Harness verification

The rebuilt instrumentation APK passed 8 Active3 tests: 3 cleanup-scope guards
and 5 reply-identity guards. Cleanup rejects mismatched run/case/catalog,
conversation, task, goal and non-timeout records. The opt-in cleanup test is not
part of ordinary runs. The 18 host catalog/timing tests also pass. These checks
validate test isolation, not model quality or the remaining business turns.
