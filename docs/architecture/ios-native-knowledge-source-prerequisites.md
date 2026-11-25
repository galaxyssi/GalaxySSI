# iOS Native Knowledge Source Prerequisites

Partial port of Android PR #3005, pinned to
`5d1a668ee1288fc6ef013dc853d9758f9283ad94` (native crate 0.4.0).
The default semantic query is now routed to the native consumer in source.
This does NOT prove a native build/activation or complete that Android PR.

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
- Default semantic search no longer builds a USearch graph, loads a vector
  catalog, or hydrates all sources. The native result resolver reads at most
  256 authenticated candidate chunks/sources and checks their current policy.
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
require source revalidation; a cursor does not grant source access. The default
whole-vector cache has been removed, but bounded reads do not establish a
whole-App memory/RSS guarantee. Native progress is stored through Rust replay
transactions, whose iOS execution has not been verified here.

## Android Comparison and Remaining Work

| Android #3005 area | iOS disposition |
| --- | --- |
| KnowledgeNativeIndex source offsets and bounded vector loading | Serial native owner advances four pages per slice, resumes pending chunk progress, skips obsolete events and fences epoch/head before queries; source-wired, not native-tested |
| KnowledgeSemanticSearch source-policy re-resolution | Default semantic consumer uses native search plus authenticated current-source resolution; lexical fallback and late controller returns are revalidated/fenced |
| AgentKnowledgeDatabase native index directory | Protected per-database/specification/epoch ownership and persistent bounded real-vector seed seek added |
| KnowledgeNativeBridge, JNI owner/arrays/mod | C ABI and synchronous Swift bridge added; Xcode framework build/link/embed configured but uncompiled |
| KnowledgeNativeWire | Swift decoder preserves Rust binary records, pending progress and match provenance with strict lengths/flags/bounds |
| KnowledgeNativeFiles key wrapping | Per-database ThisDeviceOnly Keychain root, HKDF spec/epoch keys, keyed directories, complete protection, backup exclusion and reset/invalidation sources added; native storage acceptance unverified |
| KnowledgeModelWork bounded durable successors | Embedding worker pumps source/replay slices, resumes on launch/foreground, and releases runtime/handles at 30-second idle; OS-managed background successors still required |
| memory-native Cargo files, lib.rs and replay format | Android engine unchanged; iOS crate uses exact 0.6.0 path dependency and derived lockfile; native framework configuration is connected but unbuilt |
| Android Gradle, setup action, three workflows, build-memory-native.mjs | Android inputs untouched; iOS-only locked framework build/export isolation/CodeSignOnCopy configured, not executed |
| Two Android device fixtures | Not executable on iOS; thirty-one Swift fixture methods authored, not run; replay-driver fixtures simulate the ABI boundary |
| Three Android architecture documents / README | Reference only; no transferred Android device/performance claims |

Still required for full parity/acceptance: ordinary Agent/RAG asynchronous
integration, OS-managed durable background successors, Cargo dependency resolution,
compiled ABI/lifecycle acceptance, framework packaging/signing/installation
validation and real graph/recovery/latency/scale acceptance. Default semantic UI
queries and the existing embedding worker now consume the native driver in source.
No native framework, build, device, latency or scale acceptance is claimed here.

## Verification Scope

`node apps/ios/tools/check-knowledge-native-source-scope.cjs` checks source wiring.
`node apps/ios/tools/check-knowledge-native-abi-scope.cjs` checks C ABI source
contracts, header exports, owner structure and dependency pins. Nine Rust unit
fixture functions are authored but not executed; Rust compilation, dependency
resolution and ABI layout acceptance remain unverified. The lockfile is derived
from the audited shared engine lock, not claimed as Cargo-validated on Windows.
`node apps/ios/tools/check-knowledge-native-framework-scope.cjs` checks framework
build/export/signing wiring, Swift module registration and four binary-protocol
fixtures. Node syntax and Swift grammar checks do not prove Xcode builds or
installation. No native build script has been executed on Windows.
`node apps/ios/tools/check-knowledge-native-lifecycle-scope.cjs` checks Keychain/
HKDF ownership, protected no-backup directories, generation fencing, lifecycle
notifications, reset wiring and transactional legacy enrollment. Six additional
Swift fixture methods cover resume, contract changes, legacy/current vectors,
namespace isolation, token invalidation, key deletion and missing-key/symlink
rejection. They are source only, not successful device/runtime acceptance.
`node apps/ios/tools/check-knowledge-native-publication-scope.cjs` checks the
transactional latest-publication map, schema re-enrollment barrier, source/feed
stamps and authenticated native-match resolution. Six additional fixture methods
cover publication pagination/re-addition, current source-policy enforcement,
policy-only mutations, stale result batches, schema upgrade without invented
history and non-recursive feed-registration failure. These fixtures have not run.
`node apps/ios/tools/check-knowledge-native-routing-scope.cjs` checks actual
default routing, bounded replay, committed-cursor use, source/lexical revalidation,
generation/foreground gates, resume and idle-close wiring. Six fixture methods
cover a 130-chunk simulated session recreation, obsolete/removal publications,
late append/search invalidation, persistent seed seek and stale lexical policy.
The simulated session is explicitly not a Rust or native disk acceptance result.
Swift grammar parsing and project structure checks are not Xcode type checking.
XCTest fixture source covers repeated chunks, surrogate boundaries, old storage,
transaction rejection, restart/model cursor isolation, bounded source lookup,
130-chunk replay with reopen, legacy eligibility, exact event identity, deletion/
re-addition publication fencing and policy-change invalidation.
Native builds, XCTest execution, CI monitoring and IPA generation were not run.
