# Desktop Atomic Receive Checkpoint - 2026-09-12

This is isolated local verification of the actual Desktop Signal sidecar and
Python receive handoff. It does not activate the three-broker application path,
install a shipping APK, replace the running Desktop, or submit a PR.

## Implemented Boundary

1. `PersistentSignalProtocolStore` uses encrypted per-record SQLite storage,
   WAL and `synchronous=FULL`, with fail-closed identity/session loading.
2. `SignalReceiveJournal` commits the libsignal ratchet and validated complete
   plaintext in one transaction. Identical ciphertext replays return this body.
3. Python saves the complete envelope and immutable content/cipher bindings in
   the existing delivery database before releasing the JVM handoff journal.
4. Lost release responses retry from the durable Python body; supervised bounded
   cleanup does not depend on another incoming MQTT duplicate.

No old Signal JSON migration is supported. Existing installation data is not
silently deleted. SQLite JDBC 3.53.4.0 is packaged with the sidecar; its per-record
AEAD protects Signal state and message handoff records, not attachment files.

## Executed Evidence

- 157 Python tests passed in 37.963 seconds: the prior 127 transport/delivery
  regressions, 17 receive-handoff tests, 11 sidecar-supervisor tests, and two live
  JVM/HTTP recovery tests. Counts include deliberate failure fixtures, not 157
  successful end-to-end MQTT exchanges.
- The live handoff test sends real libsignal ciphertext through the actual
  `/decrypt` endpoint. It injects Python persistence failure after JVM commit,
  terminates the owned JVM, restarts it, and retrieves the original message.
  After Python commit and JVM-journal release, another JVM termination/restart
  replays from Python without a second `/decrypt` call. Identity remains stable.
- The atomic Java probe passed 33 checks covering concurrent duplicate reception, ciphertext/content
  binding, storage and quota failures, nested rollback, invalid UTF-8, wrong
  endpoints, corrupted state, explicit revocation and encrypted disk content.
  Its child processes use `Runtime.halt(37)` inside a transaction and immediately
  after commit; fresh processes verify rollback and committed recovery respectively.
  These are abrupt process exits, not power-loss or physical-device reboot tests.
- The unchanged 10-worker/1,000-round-trip in-memory probe exposed a pre-existing
  scheduling failure: 5 of 10 repeated runs failed with libsignal decryption errors.
  Fair striped locks then passed the same 10 runs (10,000 round trips), with
  per-run workload times 780-1,328 ms. These exclude JVM startup and use in-memory
  identities, not MQTT, disk-backed sessions, phone traffic, or model execution.
  This improvement does not establish immunity to arbitrary network reordering.
- Sidecar recovery in the 157-test suite run took 4,562 ms; maximum sampled cached
  health-query latency was 0.254 ms. One observation is not a p95.
- After the final Java changes, both live tests passed again in 12.831 seconds;
  that recovery sample was 3,860 ms with a 0.258 ms maximum cached-health query.

Generated logs are in the worktree's ignored `build` directory:
`mqtt-desktop-receive-python.log`, `mqtt-desktop-atomic-java-final.log`, and
`mqtt-desktop-fair-lock-repeat.log`.

## Reproduction

From the repository root:

```powershell
./apps/android/gradlew.bat -p ./apps/desktop/core/galaxyssi-link/backend/signal_sidecar verifySignalAtomicReceive verifySignalConcurrency installDist --max-workers=2 --console=plain
```

From the Desktop backend, with `GALAXYSSI_DATA_DIR` and `GALAXYSSI_STATE_DIR`
pointing to isolated test directories and Java configured:

```powershell
python -m unittest test_signal_receive_handoff test_inbound_content_binding test_mqtt_broker_pool test_mqtt_multipath_policy test_mqtt_route_state tests.test_link_delivery test_mqtt_inbound_pool tests.test_mqtt_link_diagnostics tests.test_mqtt_phone_tool_routing tests.test_link_transport_diagnostics test_signal_sidecar_supervisor test_signal_receive_handoff_live test_signal_sidecar_recovery_live -q
```

## Still Required

- Durable pending-body dispatch must replace ID-only/accepted-state skip paths
  without blindly repeating an uncertain external action. Completed retention
  and cleanup must bound long-running storage growth.
- Generation-scoped pooled MQTT publishing, authenticated resume and receipts,
  ordered wire acceptance/bounded skew, persistent chunk assembly, and full
  Android/Desktop/app-to-app integration remain unfinished.
- Private-broker chaos/load, handset interaction, ten-window execution, p50/p95,
  background and power validation remain required before claiming delivery.
- The user most recently connected S20U (SM-G9880, `R5CN319CESA`). This round is now
  scoped to S20U; no S20U app installation/UI operation has occurred. The earlier
  S26U storage report is retained as evidence for that device only.
