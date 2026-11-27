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
- The outer `locked` operation closes and drops the memo on every exit, including
  throws. Nested operations under the same recursive lock share that operation's
  memo. A failed calculation is not cached; closing during calculation cannot
  resurrect entries. No process-wide persistent-index-key cache is introduced.
- `keyedHash` uses a nonblocking recursive try-lock before inspecting operation
  state. Independent snapshots cannot inspect/borrow another thread's memo and
  fall back to the original calculation without waiting for the writer lock.
  This is hash admission only, not complete nonblocking read admission.
- Persistent HMAC inputs/key accounts are unchanged. Byte-to-hex formatting
  produces the same lowercase, zero-padded output without per-byte formatting
  calls. Hashing and authenticated body decode remain distinct checks.

## Boundaries

- This does not port Android's metadata-only source-ownership read: current main
  still authenticates/decodes full records. The open iOS primary-storage/source
  replacement work is separate; this independent branch does not include its
  ancestry or claim to have optimized those not-yet-main paths.
- Final candidate validation and several vector APIs still acquire the writer
  monitor. Android #3033 and #3034 address those separate read-admission changes;
  this PR does not claim held-writer ranked-query or source-replacement latency.
- The key and cache references are discarded, but Swift/CryptoKit do not provide
  a verified hard-zeroization guarantee here. One operation can still be long;
  an entry/lookup input can be large even though retained cache entries are
  bounded. Keychain and cipher internals may still serialize work independently.
- No Android device measurements, fresh/retained corpus timings, schema migration
  acceptance or universal performance target are asserted for iOS.

## Verification

Twelve deliberately synthetic XCTest methods are authored for cache lifetime,
LRU, exact UTF-8 identities, calculation failure, close/reentrancy, capacity,
hex compatibility, database error cleanup, persistent/reopen compatibility and
cross-thread hash admission. They have not been compiled or executed. Source
guards and the iOS project structure check are static checks only. No native
build, typecheck, XCTest/Rust execution, CI monitoring, IPA or private evidence
is part of this change.
