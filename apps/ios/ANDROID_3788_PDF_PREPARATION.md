# Android #3788: foreground PDF preparation without UI-thread unlock

Reference: `dc510ad52`. Merged iOS #3858 and later protected-recognition work already
implement password prompts, extraction restrictions, secret-free durable jobs,
resume/checkpoints and hidden partial protected results. This follow-up removes
remaining synchronous PDFKit password/page-count and preview work from UI actions.

## Implementation

- Queue enqueue/resume prepares PDF page count and password/extraction validation
  in a detached worker, with cancellation checks before/after PDFKit. Keep a
  separate preparation task/token and exact target job/version. Busy UI and batch
  scheduling account for preparation, and users can cancel before a run exists.
- After suspension require the current token, active scene, matching owner/dataset,
  exact indexed original, current target job/version and current crop revision.
  Only then enqueue or begin the existing native run. Initial protected enqueue
  reuses its prepared bytes/count rather than decrypting twice before starting.
- Invalidated workers cannot enqueue, begin a run or publish a password error.
  Explicit cancellation cancels only the exact preparing job/version. Navigation
  stop does not immediately restart an automatic job while the page is disappearing.
- Original preview now passes immutable authenticated PDF data into a separate
  asynchronous preview view. Unlock/count/render stay inside the worker; no
  mutable unlocked PDFDocument crosses actors. Reuse the existing bounded renderer
  for current-page CGImage output, preserve paging and show cancel/retry/error UI.
- Display-only preview does not require copying permission. Text extraction and
  recognition still require it; no OCR fallback bypasses a restriction. Existing
  page processing/commit/source/crop/failure-settlement loop remains verbatim.
- Inactive/disappearing or runtime plaintext clearing invalidates work and drops
  password/image references. Passwords remain transient Swift strings, never new
  durable fields. No claim of secure heap zeroization or preempting an in-progress
  native PDFKit call; cancellation fences its returned result. Existing original
  encrypted reads and archive/index I/O remain synchronous on MainActor, so this
  is not a blanket asynchronous-storage or measured UI-latency claim.

## Validation

Four dedicated Swift cases authored, NOT executed: password/extraction gates;
display-only restricted preview and bounded image size; wrong secret/page bounds;
deterministically cancelled preparation/preview workers. Existing protected job and
large Health fixture sources are unchanged. Eight Xcode entries and six localized
resources. No new record schema, original bytes, model/network, permission or
Android/Desktop/version changes.

The source guard pins owned queue/view hooks, compares existing job/page schema,
OCR/extraction/render kernels and native per-page loop, composes the independent
export-save view inverse and rejects 22 negative source mutations. These checks
are not Swift compilation, native execution or rendered UI acceptance.

No Xcode/Swift build, XCTest execution, PDFKit/permissions/password/native UI,
cancellation race/storage-fault/restart/performance acceptance, CI inspection, IPA
or automatic approval/merge. Full Android platform equivalence remains unproven.
