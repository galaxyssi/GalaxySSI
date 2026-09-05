# Durable pending reply journal

Android pending deliveries now use an indexed SQLite journal instead of two
independent SharedPreferences commits per body/turn pointer. This is a persistence
upgrade to the existing delivery/recovery semantics, not another task scheduler.
No model invocation, task resubmission or tool execution is introduced.

## Transaction and identity boundaries

- A pending body and its current turn pointer commit in one SQLite transaction.
- Completing a reply retires its source, linked successor and current turn source
  atomically. A referenced source in another conversation/turn is never retired.
- Removing a predecessor does not erase a successor's current turn pointer.
- Recovery predecessor linkage preserves the existing supersession semantics.
- Body ciphertext authenticates the database and source identity. Turn pointers
  are encrypted independently under an opaque, structured conversation/turn key;
  legacy colon-delimiter collisions cannot bind another conversation's source.
- WAL with synchronous=FULL supplies the database transaction boundary. This does
  not make the separate Run ledger, terminal store and transcript one transaction.

Source IDs and record counts remain indexed metadata. Contact, task, conversation,
turn and recovery-successor fields are encrypted using the existing Android
Keystore AES-GCM storage cipher. No plaintext message body is added to this store,
and no decrypted preferences cache is used for new records. Retired sources retain
only a source ID/encoding tombstone with a NULL body, preventing migration replay.

## Bounded recovery pages

Routine recovery reads at most 32 pending bodies, ordered newest source first,
with a strict source-ID cursor. There is no OFFSET or full pending-key snapshot on
the steady-state path. Deletions do not shift offsets; newer records are picked up
on the next event-driven wake. A corrupt ciphertext is retained, reported as an
unreadable count, and advances the cursor so it cannot hide later valid records.

## Crash-safe legacy handoff

Exact-key find/update/remove operations import only the referenced legacy record
and turn pointer. They do not trigger the full migration from a UI callback.
The recovery IO path performs the one-time preferences snapshot/import in batches
of 64 ciphertext entries. Each short batch yields the journal monitor between
transactions, allowing ordinary exact-key operations to continue.

INSERT OR IGNORE preserves any newer SQL body, turn pointer or deletion tombstone.
Legacy bodies stay authenticated with their original AAD until rewritten. Legacy
turn pointers are retained as ciphertext under hashed keys and validated against
their source body when used; they are not trusted solely because the old key matches.
Only after all batches commit is the migration marker committed. The old preferences
are removed after that marker. A crash before the marker safely reimports missing
rows; a crash after it cannot resurrect a deleted pending entry from an old file.
Unexpected legacy value types abort finalization and leave the old file intact.

## Boundaries

This removes the full-key scan from routine recovery, not from the one-time legacy
import. Exact-key APIs remain synchronous for existing callers; this phase does
not claim all Android storage work has been moved off the main thread. The migration
and paged recovery caller run on Dispatchers.IO. The journal does not yet unify
pending intent, transport send, terminal marking and transcript projection under
one event-sourced commit. Full process-death/network recovery against the new
Desktop, failure-result replay and persistent result-page checkpoints remain
separate acceptance work.
