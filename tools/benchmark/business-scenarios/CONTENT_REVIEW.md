# Evidence-bound content review

The device collector checks delivery, containers, versions and saved bytes. It
deliberately does not infer semantic correctness from those checks. Evaluator
inspection can now be recorded in a separate JSON file and supplied explicitly
with `report.py --reviews <file>`. Original reports are never rewritten. Reviews
are not discovered from generated model artifacts or interpreted from replies.

Each review contains `schema: 1`, `case_id`, zero-based `turn_index`,
`source_sha256`, `verdict` (`pass` or `fail`), `reviewer`, substantive `notes`, and
`checked_artifacts` pairs of `evidence_file` and `sha256`. Compute the source
digest with `content_review.source_digest(report, turn)` after the turn completes.
It binds the entire original turn plus catalog, case, device, window and
conversation identity. The turn includes task, reply, artifact hashes, timings
and observations. A later run or changed evidence cannot reuse the review.

This hash is evidence binding, not a digital signature or proof that a reviewer
actually inspected content. Only create a verdict after inspecting the matching
received files/reply. Reviewer attribution must accurately identify human or
model-assisted inspection. Notes should state the checked claims and limitations.

## Acceptance behavior

- Only observed, completed artifact turns with durable task/run identity can
  have reviews. Duplicate, unknown, incomplete and stale reviews are rejected.
- A passing file review must list every received artifact by its recorded name
  and SHA-256. A failure can cite one inspected artifact with a confirmed defect;
  that does not certify the remaining artifacts.
- Text-only turns bind to the exact reply and do not require invented files.
- Content approval cannot remove a delivery failure, timeout, visual failure or
  latency failure. The full planned case/turn denominator remains unchanged.
- Explicit failures override an old `content_verified` flag and appear as
  `artifact_content_review_failed` in failure reasons. Counts distinguish reviewed
  passes, reviewed failures and unreviewed content.
- Reviews do not automatically certify source/preview rendering fidelity,
  native application recalculation, every UI control or real-world correctness.
  Existing no-review report behavior remains available.

The included `reviews/active3-a006-20260929.json` records six actual failed
content reviews from the first six warehouse XLSX turns. Unsupported currency,
an initial misleading bar baseline and a later clipped chart frame were observed.
Five turns had successful attachment delivery; turn 5 also had a missing notes
preview after a 90-second observation window. None becomes a semantic pass.
The notes do not claim that all their other content was correct. Raw files and
screenshots remain local. A checksum mismatch is an error to investigate, not a
reason to regenerate a favorable review automatically.

Example from the repository root:

```powershell
python tools/benchmark/business-scenarios/report.py --plan <run>/catalog.json --reports <run> --reviews tools/benchmark/business-scenarios/reviews/active3-a006-20260929.json --output <separate-summary>.json
```

The six-turn real summary retains 100 planned cases and 1,100 planned
turns, five successful delivery checks, zero semantic passes, six explicit
content failures and the layout turn's latency failure. It remains incomplete.
The first three reviews validated unchanged against the six-turn checkpoint
before adding reviews 3 through 5; later turns do not rewrite earlier evidence.
Thirty-two host regressions pass, including eleven review-binding tests. No Android
or Desktop production code, version, stored conversation or returned artifact is
changed by this host-side reporting feature.

## Real continuation evidence

Run `active3-warehouse-xlsx-20260929-v1324` on Active3 (SM-T575), Android
1.3.24 (1067), still-running Desktop 1.3.23 and configured Codex gpt-5.6-sol.
The authoring fixes in PR 3284 were not loaded by that running Desktop, so
this is additional baseline coverage, not a repaired-runtime acceptance run.
The resumed instrumentation completed normally in 753.329 seconds, skipping
the three already completed turns rather than resending them.

| Turn | Reply terminal (ms) | Attachment wait (ms) | Observed result |
| --- | ---: | ---: | --- |
| 3: add item | 215716 | 2820 | Added 5 x 20 = 100; total 766; four chart values |
| 4: source check | 227972 | 6940 | Owner, actual date and real returns marked unconfirmed |
| 5: remove item | 192255 | 90394 | Removed item from active cells/formulas/chart; total 556; notes preview missing |

The six-turn reply median is 221844 ms; maximum is 584111 ms. There are too
few observations for a stable p95. These timings exclude subsequent file audits
and UI checks, which are reported separately. All six terminal replies had
focused/stable captures and stopped timers, but this does not certify every
pixel or every attachment-opening interaction. Native OOXML cells, formulas and
cached chart values were inspected without changing or recalculating the files.
The successful source checks and arithmetic do not excuse the unsupported
currency and clipped previews. The original missing attachment remains failed
even if it is later recovered. The remaining five A006 turns and the full
100-case, 1100-turn suite are still incomplete.
