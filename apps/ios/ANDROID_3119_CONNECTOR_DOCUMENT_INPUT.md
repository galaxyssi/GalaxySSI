# Android #3119: scoped connector document-input follow-up

## Actual implementation

This addresses the broader attachment-input gap tracked in the iOS #3119 port,
not a claim that Android #3119 introduced the iOS parser or these limits.
Android reference remains `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4` and its
originating-turn attachment routing. iOS source baseline: main `2e4db3d46`.

Native queued local/cloud connectors previously rejected all non-image
attachments, even though iOS already had document text parsers. They now restore
the exact original conversation/turn attachment IDs and use a read-only entry
point to the existing text/HTML/PDF/DOCX/XLSX/PPTX extractor. This entry point does
not import a source into knowledge, change long-term memory or authorize OCR.
Unsupported audio/video, unknown binary files and unreadable documents fail
before any inference or provider call. Cloud images retain their original vision
path; local raw-image support remains unavailable.

Document parsing runs on a utility task with cancellation forwarding and checks
between files. Existing synchronous parsers are not forcibly interrupted in the
middle of a PDF/Office parse. After parsing, re-read the original native wait,
profile, source text and attachment manifest, then apply the unchanged live
resource, privacy, connector and task-budget checks. An edited/replaced source
or revoked execution context cannot proceed using the earlier parsed context.

Actual document text and labels are serialized and wrapped with the existing
untrusted-evidence contract. They cannot grant tools or modify host policy. The
local system prompt now includes that contract. This is structural containment,
not proof that a model follows instructions. The cloud engine's normal disclosure,
tool policy, encrypted journals and completed-stream requirement remain in place.

Limits are explicit: at most ten unique current-turn attachment IDs; aggregate
document bytes at most the existing 20 MiB import source limit; 12,000 extracted
characters per document and 24,000 total; 128 KiB encoded evidence envelope; and
256 KiB combined host execution prompt/document input. Over-limit or unreadable
inputs fail as a whole instead of silently returning a truncated/partial document
set. These are input bounds, not proof that every selected local model's token
window can fit every accepted request. Existing local generation limits remain.

## Remaining paired attachment work

Paired numeric-source connector attachments are still rejected explicitly. The
current journal runtime, deferred-body dependency release and attachment-receipt
paths require UUID source/body identity. Supporting numeric managed owners needs
coordinated authorization, outbox/journal, blob and receipt changes; removing the
producer guard alone would not work. No MQTT schema, source ID conversion or raw
file delivery is invented or claimed by this document-input change.

## Verification limits

Ten XCTest methods were authored and registered, not compiled/executed. They
cover production text/HTML parsing, unsupported files, hostile labels/content,
duplicate/historical IDs, source/text/encoded-byte limits, image separation and
all-or-nothing failure. Existing PDF/Office parser implementations are unchanged.
Source/project checks do not prove native parser, cancellation, inference,
privacy, network, end-to-end or device acceptance. No native build/typecheck,
XCTest execution, CI watching or IPA. #3119 and the overall backlog remain open.

Checks passed: document-input, pre-shadow, reported-usage, live-health,
provider-ranking, observation-timing, research-context, autonomous/research source,
background-cognition, live-planning and special-use source contracts, plus iOS
project structure, changed JavaScript syntax/localization placement and diff
whitespace. This is not a full repository check or native execution result.
