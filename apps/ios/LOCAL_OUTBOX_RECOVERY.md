# Local Outbox Recovery

Android #4281 is mirrored through the existing iOS transport contracts:

- A fresh online/idle/busy heartbeat newer than the last recoverable failure
  permits one half-open runtime probe. It does not increment successes or clear
  authorization, protocol or timeout failures. All in-process ledger instances
  serialize their persisted read/modify/write operations.
- A local MQTT journal capacity exception is attributed to local transport.
  Dispatch and adapter health accounting do not count it as provider failure.
  Existing quota bounds remain unchanged. Legacy iOS publishing does not have
  Android's identical queue-capacity return enum; no new message limit is added.
- Both transport paths retain at most the newest replaceable capability snapshot
  for the exact paired binding. Only queued, never-attempted internal snapshots
  without source messages, attachments or dependencies are replaceable.
- Journal compaction and insertion share a transaction, including quota checks.
  Legacy compaction rolls back its state if persistence fails. Unknown historical
  rows and already-attempted snapshots are retained, not inferred from ciphertext.
- Capability revision acceptance is recorded only after local enqueue succeeds.

The focused XCTest source cases cover independent ledgers, freshness and failure
class gates, local failure attribution, paired-binding isolation, preservation
of user and attempted messages, encrypted reopening and quota rollback.
Static checks do not establish device delivery or an executed recovery test.
