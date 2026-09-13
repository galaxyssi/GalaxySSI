# Native Multi-Broker Business Checkpoint

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.
This extends the owned TLS lab, not full P0-P3 or phone acceptance.

## Executed Path

Two independent Python endpoints run the real built JVM Signal sidecar, each
with its own identity and SQLite databases. They assemble the production broker
pool, authenticated route manager, bounded ingress, Signal receive handoff,
durable outbox/inbox, dispatch guard and direct-contact business handler.

The controller supplies an isolated trusted bundle exchange instead of a camera
scan. Three independent aMQTT TLS listeners bind only loopback with ephemeral
certificates. The physical adapter refuses non-loopback destinations and maps
only the three catalog entries. No production pairing store, App database,
model or real user's messages are used. Public brokers receive no test traffic.

## Business Invariants

Each completed run contains nine distinct synthetic business messages:

| Scenario | Assertion |
| --- | --- |
| Native pre-key and ratchet reply | Real decrypted content is stored on the intended endpoint |
| Three-path replay | All three actual MQTT copies observed; one dispatch and one chat row |
| Fragmented native envelope | Reassembled authenticated content and hash match |
| One broker stopped | Both directions continue on surviving paths |
| Receiver stored, sender receipt lost | PUBACK alone does not retire the durable outbox |
| Both endpoint process trees killed | Same identities and message ID recover; completed dispatch is not repeated |
| All three brokers stopped | Lower publisher persists the message without false delivery |
| Only one broker restored | Same queued message resumes and receives durable confirmation |
| All paths restored | Fresh bidirectional state supports another business message |

Assertions read actual database rows, hashes and dispatch attempts. Waiting for
the bounded ingress queue to drain prevents a UI uniqueness constraint alone
from masking repeated business execution. Error logs are retained across child
process restarts, and any captured ingress error fails the run.

The 450,000-byte padding case stays inside the unchanged 512 KiB application
envelope limit. Native encoding causes wire fragmentation. This is explicitly
not image, file or video artifact delivery, preview or save verification.

## Delayed Resume ACK Fix

An early successful-delivery run (`mqtt-owned-native-v5`) still logged three
`ValueError` entries. It did not capture exception stacks and is not a clean
acceptance result. Later baseline runs v7-v9 passed with empty endpoint logs.

A deterministic network-ordering test then reproduced a concrete source of
the same error class: it holds real MQTT receive callbacks, stops and restarts
one listener, waits for a newer local route epoch, and releases old ACKs over
the two surviving connections. The pre-fix run failed twice at
`PeerRoutes.handle_verified`: `Unsolicited or stale resume acknowledgement`.
This proves this failure mode, not that every historical ValueError had that
same cause.

Android and Desktop now discard authenticated, structurally valid ACKs whose
acknowledged epoch is below the current local epoch. They do so before remote
route persistence, readiness grants, notifications or response publication.
An ACK containing a newer remote advertisement still cannot update that route
if it acknowledges an old local epoch. Current/future mismatches, malformed
fields, wrong pair identity, expired advertisements and unknown peers remain
rejected. A fresh matching ACK remains required for the new route epoch.

No cryptographic check is removed, no new wire format or legacy fallback is
introduced, and there is no extra per-peer history cache. A discarded ACK is
not evidence that the peer accepted the current route or a business message.

## Results

| Scope | Result | Local evidence |
| --- | --- | --- |
| Pre-fix focused unit reproducer | Failed at the stale-ACK branch | Reproduced before editing production code |
| Pre-fix owned delayed-ACK reproducer | Failed with two captured stacks | `build/mqtt-owned-native-delayed-v1/left.log` |
| Focused Desktop regression | 58 passed, 2.884 s | Route, route-state and pool-client suites |
| Expanded Desktop regression | 176 passed, 46.814 s | `build/mqtt-native-checkpoint-backend.log` |
| Owned native business and delayed ACK | v2-v4 all passed, nine messages per run; six endpoint logs empty | `build/mqtt-owned-native-delayed-v{2,3,4}/report.json` |
| Original TLS lab after shared adapter extraction | Ten directed messages, two TLS rejection checks and broker recovery passed | `build/mqtt-owned-lab-smoke-v4.log` |
| Android ordinary-configuration regression | 78 passed across six suites; build successful in 5m 57s | `build/mqtt-delayed-resume-android-v2.log` and `app/build/test-results/testDebugUnitTest` |

The first Android run compiled production code and ran 42 cases. One existing
test still required old ACKs to throw. Its assertion now checks the intended
invariant instead: no persisted-route change and no readiness until a fresh
matching ACK. The expanded rerun passed all 78 cases with no failures or errors.
No native/runtime build exclusion flags were used; no APK was assembled or
installed by these unit-test commands.

Run instructions and dependency isolation are in
[the lab README](../../tools/testing/mqtt_owned_lab/README.md).
Controller timings include JSON-line RPC and SQLite snapshot polling. They are
not network RTT, unbiased p50/p95, phone latency or performance release gates.
Three reruns do not prove indefinite reliability or coverage of every ordering.

## Deployment And Remaining Boundaries

The designated S20U (`SM-G9880`, `R5CN319CESA`) remains on full App 1.1.113 (999).
Desktop 1.1.50 remains running with three public broker connections and its QR
visible. The last health check had zero paired peers. This checkpoint did not
replace those binaries or change pairing grants. No SM-T575 operation occurred.
The delayed-ACK source fix is not yet in those installed/running binaries.

Pending work includes real QR/Android-native cross-platform delivery, App/App,
full image/file/video transfer and hashes, ten windows/background/Doze/reboot,
public-provider compatibility smokes, owned load and latency distributions,
resource/power measurements, diagnostics UI and production lifecycle coverage.

In particular, the Desktop `publish_peer_message` UI entry still rejects an
all-offline connection before reaching the tested durable lower publisher.
Its offline enqueue and delivery-status projection need a separate fix and
real send-entry acceptance, including attachments. Lower-level offline recovery
in this report does not close that gap. Full development goal and PR remain open.
