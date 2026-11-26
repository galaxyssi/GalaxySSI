# Search Response Size Follow-up

Actual incremental base: main c7fe57aedc90de24c31b6e86f4b7c04db6e8e49f after #4571 merged during development. Android reference: #3007 merge 65655f0c79c6ab04121150229a65b089180f82f2. iOS-only increment; no duplicate context/provenance code.

## Reference And Changes

- Android AgentEncryptedWebIntelligenceStore.putSearch serializes the complete response and calls AgentEncryptedDatabase.writeString. Neither that method nor writeString imposes a separate response byte cap; the encrypted SQLite backend can still fail writes. This does NOT mean physically unlimited storage or identical platform maximum row sizes.
- Remove iOS's extra 2,000,000-byte SearchResponse validation ceiling and its repeated validation-time JSON encoding. Preserve successful/nonempty response checks, 100-result limit, exact key/timestamp/TTL validation, permissions, credentials, response identity, source receipts and explicit-clear generation behavior.
- Search index rows no longer inherit the document/other-kind 3,000,000-byte payload and approximately 4.1 MB encoded/blob limits. Query the current connection's SQLITE_LIMIT_LENGTH, bound raw payload before serialization, bound encoded bytes allowing for the 12-byte nonce/16-byte tag, and recheck sealed bytes. Read search ciphertext under that same native bound. SQLite may still reject the complete record due to its own overhead/limits.
- Non-search document/watch/learned row limits and marker read bounds remain in place. Do not relax network/body/URL/parser limits or increase result count. SQLite length configuration is an optional internal constructor argument, not request JSON or a permission grant; default connections retain their normal backend setting.
- Bind BLOB length using checked Int32 conversion rather than a trapping conversion. Unsupported lengths, encoder/seal/SQLite/disk failures remain errors through the existing transaction/rollback path. Do not silently truncate response fields or overwrite prior data with partial results.
- No cache row/schema/crypto/namespace/key change or migration. Existing smaller rows remain readable. Preserve the old archive import limits independently of runtime search row size; no automatic search-key pruning is introduced.

## Verification

- Four new XCTest fixture methods authored SOURCE ONLY: multibyte response above the old byte cap; failed replacement of a large response; search ciphertext beyond the former blob bound while other row kinds remain bounded; configured SQLite length rejection retaining old row/generation.
- Three existing fixture methods updated to retain large valid responses and continue rejecting empty/failed/101-result records. Examples use 4.2 MB payloads and 2.4 MB UTF-8 text, not giant near-platform-limit allocations.
- Fixtures are NOT executed. They do not establish real SQLite/CryptoKit behavior, memory/latency, filesystem failure/reopen, protected-data/keychain, process races or byte-exact platform-limit equivalence.
- Dedicated response-size source guard passed, pinning the Android writer and comparing full changed production files outside declared size hooks. Prior response-cache, result-capacity, retention and indexed-cache guards also passed with only this increment normalized before historical comparisons. `npm run check:ios`, all five checker JS syntax checks and `git diff --check` passed. These are not native acceptance.

## Remaining

- iOS's base64 Entry JSON, authenticated ciphertext and SQLite record overhead differ from Android's row codec. No claim that both devices accept exactly the same largest encoded response, or that allocation near backend limits is safe. Native memory/storage/performance acceptance and backend-error/device testing remain required.
- Existing network limits, privacy/source authorization, expiry/cleanup, watch scheduling, key lifetime and protected-data behavior are separate concerns. This change removes artificial response caps, not all Android #3007 gaps or all cache differences.
- No native build/typecheck, XCTest execution, CI watching, live network/device tests or IPA. The full Android PR backlog remains incomplete.
