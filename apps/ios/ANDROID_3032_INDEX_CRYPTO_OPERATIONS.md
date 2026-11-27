# Android #3032: Index Crypto Operations

Reference: Android PR #3032, pinned merge
`25f1af00ad6eb1e2b7f724f4002b76921f9b4d63`.

## iOS Mapping

Android moved canonical records from its former storage cipher into a reusable
Keystore-wrapped AES-GCM row cipher and changed its envelope schema. iOS already
uses reusable `GalaxySSIAttachmentAtRestCipher` instances for canonical bodies,
headers, vectors and previews. That cipher caches its Keychain-backed key,
authenticates the envelope/purpose, and checks the decrypted size and digest.
This PR does not invent another envelope or copy Android schema number 13 into
the unrelated iOS schema. Existing ciphertext, key accounts, associated purposes
and legacy reads remain unchanged.

## Implemented Change

- `AgentKnowledgeIndexKeyMemo` is owned by one serialized database operation,
  defaults to 64 entries and rejects capacities outside 1...256. LRU eviction
  maintains that bound. It retains only ephemeral HMAC lookup tokens and existing
  persistent index digests, not plaintext source/ID/query strings.
- Input lookup tokens use a fresh per-operation 256-bit key and exact UTF-8 bytes.
  Canonically equivalent Unicode strings, embedded NUL and empty input do not
  accidentally share a token through Swift string-key normalization.
- A private per-database operation scope uses an opaque thread-dictionary slot.
  The outer synchronous operation closes/drops its memo on every exit, including
  throws. Nested operations for that owner on the same thread share only that
  outer lifetime. Different threads and database owners never borrow an entry.
  Calculation failures are not cached; close cannot resurrect entries. No
  process-wide persistent-index-key cache is introduced.
- Both the outer `locked` writer operation and each database-owned committed
  view `read` enter the same scope mechanism. The hash path no longer inspects
  the writer lock. Unscoped hashing calculates directly without retaining values.
  A read memo lasts for one synchronous `read` activation, not the entire snapshot
  or query lifetime. There is no cache carried across async suspension. This is
  hash admission/lifetime control, not a measured end-to-end nonblocking result.
- Persistent HMAC inputs/key accounts are unchanged. Byte-to-hex formatting
  produces the same lowercase, zero-padded output without per-byte formatting
  calls. Hashing and authenticated body decode remain distinct checks.

## Boundaries

- Main `e6bd822b0` now contains prepared source replacement, committed read/vector
  admission, primary storage/durability/allocations, statement reuse and reusable
  read connections. This PR retains that ancestry; none of those are newly
  delivered #3032 features. Android metadata-only ownership optimization and
  further primary-header work remain separate. Full bodies still decode where
  required by current main.
- Original memo wiring cached only writer-locked operations. Integration now
  covers the shared committed-read adapter as well, without changing WAL pinning,
  lifecycle checks, statement disposal or physical retention lease order.
  Registered-model cold writer enrollment and other existing writer boundaries
  are unchanged. No held-writer ranked-query/source-replacement latency claim.
- The key and cache references are discarded, but Swift/CryptoKit do not provide
  a verified hard-zeroization guarantee here. One operation can still be long;
  an entry/lookup input can be large even though retained entries per operation
  are bounded. Independent threads each own their bound; this is not a global
  memory cap. Keychain and cipher internals may still serialize independently.
- No Android device measurements, fresh/retained corpus timings, schema migration
  acceptance or universal performance target are asserted for iOS.

## Verification

Eighteen deliberately synthetic XCTest methods are authored for cache lifetime,
LRU, exact UTF-8 identities, calculation failure, close/reentrancy, capacity,
hex compatibility, database error cleanup, persistent/reopen compatibility and
cross-thread hash admission, nested/throwing/unscoped lifetimes, owner separation,
concurrent scopes and committed-read error/reentrant-close cleanup. The corruption
fixture now also removes primary references before testing an invalid legacy
payload; changing the old placeholder alone no longer corrupts main's primary
body. They have not been compiled or executed. Source
guards and the iOS project structure check are static checks only. No native
build, typecheck, XCTest/Rust execution, CI monitoring, IPA or private evidence
is part of this change.

The main merge preserves both sides of concurrent Xcode source registrations.
The focused scope check compares complete database/read-view/project content to
that main outside declared memo hooks, and retains the original LRU/hex kernel.
Read-connection guards normalize only those hooks for older contracts; no SQL,
ownership, encryption, WAL or durable primary implementation is replaced by a
cached digest.

Current verification passes the memo scope, all eight native-knowledge source
guards and check:ios. Six older whole-file guards (read-connections, statements,
primary allocations/durability/partitions and primary-source integration) fail
on project or coordinator baseline drift. A read-only loader of main's original
scripts and sources reproduced the same failures. They are not counted as passes
and their assertions are not disabled. There is no full-repository-green claim.
