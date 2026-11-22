# Android #4295: report quick import

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4295
Android merge: `3ef61a098cb35ed6c23dd12e9db3cf92d3e13a2f`.

## iOS implementation

- Remove the separate image-permission setting and gate. Keep the existing online
  health and measurement-processing permissions, route/source revalidation and one
  explicit per-image disclosure. The disclosure now states that supported results
  will be saved, rather than claiming all output remains unconfirmed.
- Preserve the paired Codex-only ephemeral/no-tools/no-history route from #4294.
  Plain numeric laboratory values are accepted as well as printed qualifiers.
- The schema adds optional explicit glucose fasting status for old-result compatibility.
  It permits a labeled collection date without time, not a report or birth date.
  Instructions prohibit guessing fasting from time/values and mixing people/samples.
- Single-image file imports queue local recognition and open the report workflow;
  single report-mode photo batches do likewise. Device mode, multipage batches and
  PDFs retain their existing local recognition/review flow. No image is sent merely
  because it was selected: the per-image preview still requires confirmation.
  Explicitly selecting a completed/cancelled image again creates a fresh report job
  and consent flow; merely reopening an existing result never retransmits it. An old
  device-mode task cannot silently replace an explicitly selected report import.
- After transcription, save all supported results without another per-row checkbox.
  Ask for missing sample date/time and glucose fasting status in one form. A printed
  date is preserved while the user supplies its time. Reject future/invalid/ambiguous
  local times. Explicitly unknown fasting stays unknown, never inferred hours.
- Recompute the exact encrypted job/draft/source plan before saving. Build all new
  measurements, duplicate source links, pending drafts and imported-source receipts
  in memory, then perform one encrypted archive write. An inactive/cancelled caller
  or changed source/plan commits nothing. No request, treatment plan or reminder is
  created by the importer itself.
- Duplicate values at the same sample time and collection condition link their source
  to the existing record revision without changing its note, value or revision. Multiple
  different results for one metric and rows with uncertain units/invalid values stay
  editable drafts. Existing user-edited drafts are respected after re-preparing.
- Durable per-job source receipts prevent repeated import, including after a user
  deletes a measurement. Saved rows open the current record editor, not a fresh model
  draft. Report/model provenance and original OCR pages remain separate.
- Non-fasting/after-meal labels do not trigger fasting screening context by themselves.
  A fasting label does not establish verified fasting hours or clinical applicability.
  Unknown collection conditions remain unknown for comparison/baseline calculations.

## Original retention

Image imports honoring a review-only choice temporarily encrypt the source until
review is complete. Only a newly created source becomes review-only; choosing review
for an already retained file cannot downgrade it. An explicit keep operation promotes
a temporary source. Fully handled, non-partial reports and explicitly cancelled jobs
release temporary originals through the existing logical-removal/cleanup ledger.
Incomplete, partial and pending-draft reports keep their originals for review. Existing
instruction-source-in-use checks still apply. Completed cleanup retains measurements
and source metadata, not image bytes. Interrupted physical cleanup is retryable on
the next recognition/review entry; no guaranteed background erasure is claimed.

## Verification limits

Added XCTest source covers combined supplements, recorded dates/DST ambiguity,
numeric laboratory values, uncertain units, same-metric conflicts, duplicates and
user edits, cancellation atomicity, stale/replayed plans, deletion, source removal,
temporary retention/release/promotion, partial results, legacy schema and collection
semantics. Updated prior image-permission regressions for the removed setting.

Windows cannot run Xcode compilation, XCTest, camera/document-picker UI or a live
paired Codex import. Static checks are not those runtime verifications. Android's
device results are reference evidence only. No Android/Desktop edits or IPA.
