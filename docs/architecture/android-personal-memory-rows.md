# Encrypted personal-memory rows

Android 1.1.59 replaces the personal-memory store's single encrypted `items`
JSON array with independent encrypted rows in the same database. This changes
the storage representation, not the provider, global-agent setting, history
retention policy, ASR or QNN runtime.

## Storage and migration

- Keys use the `personal-memory:v3:row:` prefix and a SHA-256 of the opaque item
  ID. Values, provenance, scope, status and ordering remain AES-GCM encrypted
  with the existing database/key associated data. Keys do not contain memory
  text or embedding vectors.
- Encrypted metadata records the schema, revision, total row count and active
  count. The normal count operation reads this small record instead of decoding
  every personal memory. This cached count is not a full integrity audit.
- Migration validates the original encrypted array, normalizes legacy conflict
  groups and writes rows plus metadata in a single SQLite transaction. Only
  after the new representation commits is the old array removed. Failed writes,
  malformed source data and duplicate IDs cannot silently become an empty store.
- Older application binaries do not understand the new representation. Do not
  downgrade the application after migration; preserve the database and repair
  forward. This is distinct from transaction rollback on a failed migration.
- The shared encrypted database's streaming mutation API encrypts one row at a
  time inside the transaction. It does not construct a second map containing
  every encrypted payload. Unchanged payloads keep their original ciphertext.
- Ordering positions are encrypted and stable for surviving rows. Deleting an
  earlier item does not renumber and rewrite all surviving items. Actual
  reordering can require new positions for the affected suffix.
- Personal-memory mutations, deletion records and pending retraction references
  use the same database transaction. Backup restore also uses the row writer and
  applies the existing deletion suppression before committing.
- Readback validates identity, count and ordering. An unreadable or inconsistent
  row raises an error rather than silently dropping memories. Independent store
  wrappers do not retain the old unbounded plaintext snapshot cache.

## Current scaling boundary

This is not a million-item acceptance claim. Existing mutation and recall
algorithms still materialize complete decoded lists; row reads are keyset-paged
but their results are combined for those APIs. Conflict normalization, backup
export/import, the legacy-array migration and UI snapshots also still require
full collections. Replacement scans candidate and existing rows even though
only changed payloads are rewritten. This removes the giant persisted value
and unnecessary ciphertext writes, not all O(N) work.

Indexed identity/conflict queries, bounded recall candidates, personal-memory
UI paging and streaming backup formats remain required. Neither 1,201-row
migration tests nor fast metadata counts prove million-item or hundred-million
item performance. Large-dataset full reads may be slower than the former warm
in-memory snapshot; benchmarks must distinguish this from count/write savings.
Migration holds the shared memory lock and a SQLite write transaction; its
foreground contention has not passed a production latency gate.

## Verification

Final build and device evidence will be recorded after verification.
