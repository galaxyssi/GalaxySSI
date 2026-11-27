# Single-File Recovery and Interpretation

Ports Android #4628 (`a2d4d8c274b74370d379aa311238cefadd3b248a`) to iOS.
Only iOS sources, resources, project registrations and source checks change.

## Independent Receipts

Each original image/file in a batch of two to ten has a caption beneath its
own rich block. Transport state and model-reported reading state are separate.
Missing receipts stay unknown; delivery and ordinary assistant prose never
prove that a model recognized a file. The attachment-reading native tool records
an explicit, scoped model self-report, not independent content verification.
Receipt metadata uses the existing encrypted per-profile/per-conversation store.

## Resume One Transfer

Legacy MQTT resumes only held packets for the selected transfer while retaining
the original task's dependency barrier. It does not resubmit the question or
sibling files. Relay retries require an advertised recoverable failure, the same
peer/route/source binding, verified original chunks, an unexpired ten-minute
window and the exact next generation (at most three). Older generation receipts
cannot release the current transfer. Expiry closes the held transfer and removes
its deferred body without submitting it. Unsupported failures retain terminal
handling rather than receiving an invented retry receipt.

## Read One Original

The user action restores the selected original by exact attachment ID, never
by filename, and creates an independent read-only child turn. It supplies one
file and fixed interpretation instructions, without the original question,
conversation history, session/global requirements or team context.

- Cloud uses the existing image-payload or transient document-text pipeline and
  restricts the request to one user input with fixed system instructions.
- Local inference uses extracted document text or existing OCR. Its instructions
  explicitly state that original layout and non-text visual content are absent.
- Paired Desktop uses a separate supervised, plan-only connector task. The
  encrypted intent pins the original rich-content hash, descriptor, invocation,
  task/turn, source, selected peer and current cryptographic route binding. Modern
  MQTT authorization and legacy queue markers reject stale scoped sends after
  cancellation, privacy lock, profile changes or conversation changes.

All paths require a bounded structured result (`recognized` or `unreadable`
plus reply). Tool calls, executable rich blocks, malformed/incomplete output and
unavailable sources leave interpretation unverified. Only the host can apply a
structured result to the parent file; a model cannot grant itself that authority.
Desktop results are committed to the scoped ledger, not the ordinary connector
execution bus. Cancellation is best-effort and cannot recall bytes already sent.

## Verification Boundary

`node apps/ios/tools/check-file-recovery-foundation.cjs` checks source contracts;
`npm run check:ios` checks project structure. Neither executes Swift. Twenty
synthetic XCTest methods cover receipt transitions, isolated output parsing,
Desktop request substitution and legacy serialization; they are unexecuted.
No native compilation, device/provider/relay execution, CI monitoring or IPA
generation is claimed by this change. These remain necessary before release.
