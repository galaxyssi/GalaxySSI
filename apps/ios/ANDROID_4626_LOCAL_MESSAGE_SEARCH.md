# Android #4626: local message and attachment-name search

Android reference: 1f6ca4534e462ec52e9f6cb35f2dca4feffe363d.
iOS implementation base: eb970a6ac3ac5883f011991957bb776d40b0ab48 (main).

## Search

Add a message/attachment result section to the conversation hub's existing search.
The existing title/metadata results remain separate. Trim queries and bound them
to 256 UTF-16 units; matching is literal and case-insensitive, not SQL LIKE, regex,
semantic retrieval or a provider call. Match full stored bodies and attachment
titles only, never local paths, attachment URIs or hidden rich-block metadata.
Normalize legacy peer envelopes through the existing pure presentation helper.

Scan encrypted conversation and message pages of 32 rows on demand. Do not create
an FTS table, plaintext side index, stored query history, report or export. Search
message decoding bypasses the ordinary row cache. Strict added reads check SQL
completion, decryption, row IDs and routing metadata, and preserve existing Agent
turn admission. Existing cipher, writes, schema and normal read behavior remain
unchanged. iOS stores each authenticated message payload as one encrypted row,
so body matching is not limited to a preview or an artificial text chunk boundary.

An actor retains only current metadata/message pages, cursors and the open scan.
After a short debounce, publish the first hit and then small batches, up to 24 per
explicit request for more. Cancellation is checked between sources, pages and
rows. The UI checks request generation, owner, protected-data availability and
live source eligibility again before publishing. Query/owner/contact-scope changes
cancel old work; failures show an incomplete-search state and explicit retry.
Results can grow when the user requests more; they are not written to disk.

Active and archived scopes stay separate. Ordinary Agent sources must be neither
private nor tracking-paused, have no global topic binding, and not be merged away.
Exclude health/topic discussions, system/process/control/waiting/stream-preview
rows and merged-source copies. Direct persons/Desktop devices and historical
Desktop contacts use their contact identity, not an active Agent's transcript.
Recheck Agent metadata while scanning and prune newly ineligible results on local
workspace changes. This is a live paginated scan, not a frozen global database
transaction; concurrent history edits may require an explicit retry for coverage.

## Read-only context

Selecting a hit presents its exact stored UUID/cursor and neighboring rows without
switching the active Agent, restoring an archive, marking a conversation read,
executing tools or opening/downloading files. Recheck current source consent and
the original hit's routing identity and match before each read. Start with twelve
neighbors on each side, then append/prepend explicit older/newer pages while
preserving the visible row offset. No new chat/composer surface is launched.

Show original selectable text and attachment names, bold the first literal match,
and use native text layout to position a deep match rather than only the top of a
long message. A user drag invalidates delayed positioning. Back dismisses the
reader, retaining the hub's in-memory query/results and scroll position. No query
or reader location is persisted. Lock/background/privacy clearing cancels work,
clears mounted rows/results and closes the reader; hub search text is scrubbed on
the existing privacy/background paths. SwiftUI privacy marking is not a promise
to prevent screenshots on iOS.

## Verification boundaries

Twelve synthetic Swift methods are authored for UTF-16 bounds, literal Unicode
snippets, filename-only matching, privacy/role exclusions, deep text across many
conversation/message pages, archived separation, exact neighbor context, consent
rechecks, deterministic cancellation, encrypted storage and direct-peer scope.
They have not been compiled or executed. No private data or test output is stored
in the repository. Source guards check actual call sites and retain existing
database writes, crypto, session authority, transport and composer behavior.

No native build/typecheck, XCTest, device/provider testing, full repository check,
CI monitoring or IPA. Native text sizing/deep positioning, sheet return behavior,
storage concurrency and runtime encryption remain unvalidated. Android/Desktop
and versions are unchanged. Remaining iOS parity work is not complete.
