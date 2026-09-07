# Android Inline Recovery Consumer

Android 1.0.38 can request and consume the optional first archived reply page
provided by Desktop 1.0.34 (PR #2852). This removes a separate first-page request
when the authenticated status observation includes a valid page. It does not
change task execution, transport encryption, page size, or durable receipts.

## Execution Path

- Automatic recovery and explicit recovery set `include_result_page: true`.
- Metadata-only inspection does not opt in and discards unsolicited page data.
- The query client binds a nested page to the authenticated Desktop, query
  nonce, all seven execution identity fields, and observed generation.
- The shared page codec validates integer metadata, the 16 KiB page bound,
  manifest shape, and page checksum. Single-page bodies also verify the complete
  checksum before entering the checkpoint store.
- The existing result client uses the first page and requests only missing
  subsequent pages with the pinned full-body digest. Existing encrypted
  checkpoints take precedence over an incompatible optional manifest.
- Full-body checksum, inner identity, terminal outcome, generation, and current
  execution eligibility remain necessary before publishing a recovered reply.
- The existing durable inbox and result-receipt paths remain unchanged.

## Failure and Privacy Behavior

Malformed optional data falls back to normal page retrieval. A seed that passes
page checks but later fails complete-manifest or inner-envelope validation can
trigger one seed-free attempt. Only that invalid digest's checkpoint is cleared.
Timeouts, rejected sends, cancellation, and checkpoint write failures do not
discard valid downloaded pages or cause an immediate seed-free retry.

Decoded page arrays and assembled byte buffers are wiped after use. No plaintext
temporary file is introduced. Private local-only contexts are still rejected by
the existing transport policy. Optional page bytes are not put into status
inspection results or diagnostic timing records.

## Timing and Verification

Body and checkpoint spans still measure their actual work. A reply recovered
entirely from an inline page has no page-network span, not an invented zero-RTT
sample. Larger replies still emit spans for pages actually requested.

The focused JVM suite covers authenticated query-to-consumer delivery, nested
nonce and full identity binding, malformed generations, metadata-only queries,
multi-page Unicode bodies, invalid optional manifests, existing checkpoints,
timeout resume, forged inner identities, cancellation eligibility, private
contexts, buffer wiping, and timing semantics.

This PR does not install a new APK or restart Desktop. S20U paired-broker tests,
process-death recovery, and before/after timing remain separate integration
acceptance work. Passing JVM tests does not prove the five-second recovery
target or complete Run Kernel acceptance.
