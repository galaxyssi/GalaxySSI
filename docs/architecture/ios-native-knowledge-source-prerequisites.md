# iOS Native Knowledge Source Prerequisites

Partial port of Android PR #3005, pinned to
`5d1a668ee1288fc6ef013dc853d9758f9283ad94` (native crate 0.4.0).
This change does NOT activate native retrieval or complete that Android PR.

## Production Changes

- Newly embedded chunks persist actual half-open UTF-16 source offsets. Literal,
  forward-only source matching distinguishes repeated chunks without inventing
  offsets from ordinals. Failed matching aborts indexing.
- Source range validation rejects missing endpoints, invalid bounds, surrogate
  splits, wrong document identities and changed source revisions. Offset-bearing
  vector writes resolve the current encrypted source inside the write transaction.
  Existing source revisions include policy metadata, not only source text.
- Compact storage and legacy JSON continue to decode old checkpoints without
  offsets. Such records remain usable by existing search; they are NOT suitable
  for native provenance replay without reindexing/backfill.
- Vector catalog traversal uses model-scoped opaque keyset cursors and indexed
  pages of at most 256 rows. Cursor keys contain no plaintext source identifiers.
  Individual reads re-use existing encryption and purpose authentication.
- Existing semantic search hydrates only each page's sources and the at-most-256
  retrieved candidates. It no longer calls the whole-source `all()` API or uses
  OFFSET traversal. Candidate source revision/policy checks remain in place.
- New vector writes also maintain an indexed ordinal directory in the same
  transaction. Offset-free legacy writes remove any prior ordinal entry instead
  of leaving stale native eligibility. Vector deletion cleans up the directory
  through a SQLite trigger. Encrypted payloads retain the actual text ranges;
  the directory contains only opaque identities, revision hashes and ordinals.
- A published-event replay API resolves at most 64 vectors in ordinal order,
  inside one read snapshot. It validates the exact durable event and latest
  publication for that document, current source revision, complete ordinal count,
  embedding specification, contiguous ordinal sequence and actual source ranges.
  Old publications, deletion/re-addition, changed policy and missing legacy
  metadata cannot yield replay rows. Callers must still fence the feed epoch/head
  and source policy again before releasing query results after this snapshot.
- Change-feed iteration now treats SQLite step failures and non-increasing or
  out-of-head sequences as errors rather than returning a truncated success page.

Pages are individually consistent reads, not a corpus snapshot. Concurrent edits
require source revalidation; a cursor does not grant source access. The current
USearch cache STILL accumulates a whole vector catalog. Bounded page reads are
not a bounded total-memory guarantee and are not a durable graph implementation.

## Android Comparison and Remaining Work

| Android #3005 area | iOS disposition |
| --- | --- |
| KnowledgeNativeIndex source offsets and bounded vector loading | Source provenance, bounded catalog and published-event replay-page API added; no native replay engine yet |
| KnowledgeSemanticSearch source-policy re-resolution | Existing revalidation retained; whole-source hydration removed |
| AgentKnowledgeDatabase native index directory | Deferred with native index ownership |
| KnowledgeNativeBridge, JNI owner/arrays/mod | iOS C ABI sources added under memory-native with checked buffers and monotonic owners; framework and Swift caller still absent |
| KnowledgeNativeWire | C ABI preserves Rust binary records; Swift decoding still required |
| KnowledgeNativeFiles key wrapping | Not ported; requires iOS Keychain-backed index key and protected files |
| KnowledgeModelWork bounded durable successors | Not ported; requires iOS lifecycle/background scheduling |
| memory-native Cargo files, lib.rs and replay format | Android engine unchanged; separate iOS crate uses current 0.6.0 path dependency and a derived lockfile; native framework integration remains required |
| Android Gradle, setup action, three workflows, build-memory-native.mjs | Android-specific build inputs untouched; iOS linking/signing still required |
| Two Android device fixtures | Not executable on iOS; nine Swift fixture methods authored, not run |
| Three Android architecture documents / README | Reference only; no transferred Android device/performance claims |

Still required before native activation: legacy published-document bootstrap,
native model/epoch ownership, replay-page consumption, transactional progress recovery,
compiled ABI ownership/cancellation acceptance, framework packaging, key lifecycle, privacy
invalidation, query freshness fencing and lexical fallback during replay.
No native framework, build, device, latency or scale acceptance is claimed here.

## Verification Scope

`node apps/ios/tools/check-knowledge-native-source-scope.cjs` checks source wiring.
`node apps/ios/tools/check-knowledge-native-abi-scope.cjs` checks C ABI source
contracts, header exports, owner structure and dependency pins. Nine Rust unit
fixture functions are authored but not executed; Rust compilation, dependency
resolution and ABI layout acceptance remain unverified. The lockfile is derived
from the audited shared engine lock, not claimed as Cargo-validated on Windows.
Swift grammar parsing and project structure checks are not Xcode type checking.
XCTest fixture source covers repeated chunks, surrogate boundaries, old storage,
transaction rejection, restart/model cursor isolation, bounded source lookup,
130-chunk replay with reopen, legacy eligibility, exact event identity, deletion/
re-addition publication fencing and policy-change invalidation.
Native builds, XCTest execution, CI monitoring and IPA generation were not run.
