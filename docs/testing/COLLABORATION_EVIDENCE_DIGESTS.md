# Collaboration evidence content digests

Evidence recall has three distinct identities. Do not compare them as if they
were the same file checksum:

| Field | Meaning |
| --- | --- |
| `source_reference.evidence_id` and `sha256` | Exact original observation citation; copy these unchanged into publications. |
| `host_read_coverage.content_sha256` | Existing ledger digest of the complete content encoded as a JSON string with `AgentNativeJsonCodec`, then UTF-8. Its encoding is explicitly `galaxyssi_json_string_utf8_v1`. It is not a raw file digest. |
| `host_read_coverage.content_utf8_sha256` | SHA-256 of the complete content's UTF-8 bytes, before JSON-string encoding. Use this to verify an exported evidence file. |

To export an original, follow `next_offset`, concatenate the returned `content`
strings exactly, and encode the result as UTF-8. Do not parse and reformat the
JSON, append a newline, or add a BOM. Every page carries the same complete-content
digest, not that individual page's digest. Pagination offsets and character
counts use UTF-16 code units; `offset_unit` makes this explicit.

The remote delivery challenge's `delivery.content_sha256` remains the raw UTF-8
digest of the individual page. Its transport contract is unchanged.

The extra description and raw digest are derived response metadata. Existing
observations, citation hashes, persisted read intervals and frozen review
snapshots are not migrated or rewritten. A correct digest is not proof that all
pages were received, understood, or scientifically verified. Read confirmation,
complete-page requirements, dispatch ownership and revocation checks remain in
force.

## Verification

- `CollaborationEvidenceContentDigestTest`: escaped and non-ASCII text, UTF-16
  offsets, full versus page hashes, unchanged legacy rows and incomplete reads.
- `CollaborationEvidenceReadCoverageTest`: missing pages, exact dispatch identity,
  corrupt storage, revocation and idempotent recovery.
- `CollaborationRecallDeliveryTest`: per-page transport hashes and confirmations.
- `CollaborationScopedRecallDeviceTest`: cloud and native tool responses expose
  the same exact-byte digest without allowing independent or revoked readers.

These checks verify the API contract, not scientific capability growth or an
end-to-end real-model acceptance result.
