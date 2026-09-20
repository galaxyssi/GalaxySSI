# Receive quota and control-message churn

## Incident evidence

The September 20, 2026 local diagnostic snapshot showed a paired S26U route at
16,776,939 bytes of its 16 MiB receive-body allowance (277 bytes free). Its 11,501
retained bodies contained 11 peer messages and 22 task inputs, but also 6,214
delivery acknowledgements, 1,968 blob-capability declarations, 1,571 recovery
queries, 998 connector queries and 676 result-page queries. One previously
compacted message accounted for the remaining usage record.

All 1,968 capability declarations carried the same revision. Of the page queries,
675 targeted page zero of the same generation-two result. The corresponding
Desktop archive was already acknowledged by the phone; its pages had correctly
been released. Being connected does not prevent application-level retry churn.

## Changes

- Completed receive bodies of every size become authenticated, non-executable
  replay proofs once dispatch, native handoff release and wire binding are proven.
- Only outstanding full bodies consume the pending-receive quota. Historical
  proofs, content hashes and ciphertext bindings are retained, not discarded.
  This fixes active queue capacity; it is not a bounded archival-retention policy.
- An atomic usage migration and indexed maintenance queue reclaim old completed
  bodies in bounded transactions. Unfinished/uncertain work is not evicted.
- Storage saturation has its own diagnostic category and API counters, separate
  from cryptographic failures and broker socket readiness.
- Android distinguishes route-lease renewal from a genuinely restored connection.
  Renewals with a surviving verified path do not reset all application recovery.
- Unchanged blob capability state is not re-announced on every subscription/route
  wake. New pairing, process startup or changed capability still announces it.
- Automatic recovery queries back off on repeated failures or an unchanged
  terminal result. Real running-task responses retain normal liveness probes.
- Generation-bound handled inbox receipts stop rediscovery of already received
  results, without deleting pending task state across a concurrent new execution.
- Recent repeated delivery acknowledgements reuse the same encrypted wire bytes.
  The replay cache has 256 entries, a 24-hour preparation-age limit, and preserves
  attempt fencing. It does not wait for acknowledgements of acknowledgements.

## Verification

- Desktop receive/dispatch regression tests cover rollback, unfinished native
  handoffs, content conflicts, duplicate ciphertext, pair isolation, small-message
  history under a two-record quota, and migration from saturated accounting.
- Android JVM tests cover 100 routine lease renewals without duplicate recovery
  notifications, actual lease expiry, per-task pacing and capability publication.
- Android device tests cover replay-cache capacity, exact ciphertext reuse,
  preparation-age expiry, handled-result tombstones and execution-generation
  changes. Building these tests does not constitute running them on a device.
- A copy of the real Desktop ledger reclaimed 15,539 bodies in about 50 seconds;
  all message/content/ciphertext/handoff records and unfinished bodies remained.
- The production Desktop was backed up before deployment. Its pending body usage
  fell to one 1,376-byte legacy acknowledgement lacking a wire receipt proof. This
  row is intentionally retained. No pairing, keys or chat history were reset.

## Device acceptance still required

On S26U, install the APK without clearing data. Send a new contact message in each
direction, confirm display and receipt, then leave both endpoints idle for at least
30 minutes. Check that unchanged capabilities are not repeatedly announced, old
handled results do not request pages, and pending body usage remains low. Repeat
with one broker reconnecting and then all paths disconnected/reconnected. Verify
that a new execution generation and genuinely unfinished results still recover.

The original snapshot and post-deployment control receipts are not a substitute
for this user-visible chat test. After S26U reconnected, v1.2.12 (1017) was installed
without clearing data. LinkTransportReceiptDeviceTest and
AgentConnectorInboxDeviceTest passed all 28 device tests, including the new replay
and handled-generation regressions. The 30-minute idle/reconnect and user-visible
bidirectional chat acceptance remain separate follow-up checks.
