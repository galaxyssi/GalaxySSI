# Android #4298: selected health files and batch sampling context

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4298
Android merge: `b084370a801bb71bb8087ab5a2bf8b3e8bd67277`.

## Entry And Processing

- Health, Record Center and Data/Files import entries open the native multiple-file picker directly. Images, PDF, CSV, JSON, XLSX and text tables share selection; camera and other existing entry points remain available.
- Before opening the picker, a ready private Desktop route and current health consent allow a choice between recognizing selected report images and local-only processing. The disclosure identifies the destination. Selection approvals bind owner, consent epochs, destination and expiry; they are never persisted or restored.
- Report images selected for model processing skip redundant local OCR, are compressed under the existing exact 100,000-byte ceiling and sent once through the existing private paired transport. All selected-image results are held before any image measurements are committed.
- PDF extraction/OCR and table parsing remain local. Tables become encrypted resumable mapping reviews, not unconfirmed measurements. PDF jobs process their pages locally; locked/restricted PDFs open the existing local unlock/review flow. Existing original-retention choices still apply, including temporary review-only PDF originals.
- Selection is bounded by the existing 16-job capacity and per-file 16 MiB / table 1 MiB limits. Each failed file is shown independently. Failed or interrupted work is resumable; unrecognized model images require fresh authorization after leaving the active view. Reopening recognized results never resends them.

## Shared Local Confirmation

- A single form after the batch requests only missing sampling date/time and glucose context. It preserves each report's printed date, complete timestamp and explicit collection condition.
- One clock selection may fill multiple date-only reports while keeping their separate dates. Missing dates use the selected day. Ambiguous/nonexistent local times and future samples fail validation rather than choosing a DST offset silently.
- Pending results and their group IDs survive reopening. Job Center links back to the batch. The persistence host itself rejects confirmation while another batch member is still processing; terminal failures/cancellations do not prevent review of successful results.
- Confirmation performs no network operation and does not require enabling online requests again for already received results. Local-summary permission remains required. All jobs, sources/crops, consent epochs, record versions, time zones and the review lease are checked before applying the entire local archive update. A stale last member or invalid time cannot leave a half-saved batch.
- Confirmation receipts are durable and replay-resistant. Completed/deleted measurements are not recreated. Skipped rows retain source-specific reasons, and pending/partial/skipped originals cannot be cleaned up as successful complete imports.

## Measurement Boundaries

- Preserve `after_meal_1h` and `after_meal_2h` separately in recognition, forms, manual entries and care clarification. Neither is treated as fasting-screening context.
- For selected report results, choose the nearest compatible report-derived measurement within an inclusive one-hour window. Match metric, unit and collection condition; never update manual, HealthKit, table or Bluetooth-sourced records.
- Updates preserve identity, append a revision, preserve user notes, retain the previous primary report as a secondary source and carry forward secondary links from the replaced revision. Exact duplicates link sources without overwriting records.

## Validation Boundary

Added 23 XCTest source methods covering whole-batch hold, mixed printed dates/timestamps, local/offline confirmation, DST rollback, pending retention, consent/record/job/lease invalidation, replay/deletion, nearby updates and exclusions, post-meal context, encrypted table staging, group restoration, selection bounds, approval scope, deferred reasons, explicitly skipping unrecognized images and cancellation before asynchronous file preparation. Updated the previous automatic-import tests for the new pending-confirmation contract.

Windows checks cover project registration, added-text localization placement, Swift grammar and Git diff/merge structure only. Xcode compilation, XCTest execution, native picker rendering, actual device lifecycle, live paired recognition and notification delivery have not been verified here. No Android/Desktop edits, version bump, IPA or auto-merge are included.
