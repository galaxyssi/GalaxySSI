# MQTT retry pressure recovery

## Observed failure

The Desktop per-peer admission lane reached its unchanged 128-packet limit.
Packets were still being processed, but Signal invalid-message failures and
replays dominated diagnostics. One ten-second sample processed 15 packets while
admitting 12, decreasing backlog from 121 to 118. Repeated Android outbox batches
were visible about every 650 ms. These are wire attempts, not distinct user chats.

Android reconnect callbacks could reset all outbox schedules to immediately due,
defeating the existing receipt wait/backoff. Desktop caught handler errors inside
the worker callback, so the pool incorrectly reported zero failures.

## Changes

- Preserve the existing receipt window for previously attempted Android messages
  when paths resume. Unsent messages can still wake immediately. Repeated wakeups
  cannot repeatedly shorten the same retry window to zero.
- Apply a bounded, per-pair/per-ciphertext negative cache only after outer AEAD
  authentication and sender/receiver binding. Repeat invalid ciphertext waits
  2-30 seconds before another Signal attempt. Changed keys, ciphertext or peers
  are independent; the cache contains no plaintext and is capped at 1024 entries.
- Never emit an application storage receipt for deferred or invalid ciphertext.
  Existing durable received-message proofs still take precedence and can resend
  valid receipts. Transient infrastructure errors are not negatively cached.
- Count handler-reported failures and expose backoff counters and allowlisted
  error reasons without logging private exception bodies.

No queue limits, pairing keys, Signal authentication rules or chat records were
removed or relaxed. This is load containment, not automatic Signal session reset.

## Device evidence

- The live tests below used the modified v1.2.4 development build. This PR bumps
  Android to v1.2.5 (1010) and Desktop to v1.2.5; the version-only update has not
  been rebuilt or reinstalled as part of PR submission.
- Debug APK built and installed over the existing S26U installation (SM-S9480).
  Desktop was restarted from the modified source.
- Eleven isolated outbox database tests passed on S26U, including repeated path
  wakeups, encryption/reopen and exact authenticated receipt binding. The opt-in
  metadata audit also passed.
- S26U sent `Link-recovery-check-20260918-A`. Desktop recorded it as `received`;
  the sender's durable outbox entry was removed after authenticated storage proof.
- Desktop sent `Link-recovery-check-20260918-B`; Desktop reconciled its state to
  `delivered` after the phone's application receipt, not merely MQTT PUBACK.
- Subsequent health snapshots showed zero pending packets, an authenticated peer
  ready, and no admission rejections in the new process. Startup high-water was
  31 packets. This is a limited live sample, not a long-duration SLO result.

## Remaining investigation

The phone metadata audit found 1470 older internal outbox records, oldest about
4.8 days, with attempt counters zero. Those records are not automatically the
packets that saturated Desktop: many have not been sent. They were preserved.
Historical Signal invalid-message errors still occur occasionally; their exact
cryptographic cause is not established. No blanket session reset or deletion was
performed. Multi-day offline/online cycling and archival of stale internal
requests require separate acceptance.

The focused Desktop regression suite covers failure backoff, bounded capacity,
isolation, no false receipts, worker failure accounting and receipt replay.
An expanded pre-existing timing test suite has stale mocks for the receipt-hash
API; its failures must not be counted as passing validation of this change.
