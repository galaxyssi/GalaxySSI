# Multi-Broker Implementation Progress

Branch: `feat/automatic-multi-broker-20260912`

Base: `2c4a76415` (latest origin/main when this worktree was created).

The goal remains the complete Android + Desktop specification, including real
pairing, task delivery, attachments, recovery, diagnostics, performance evidence,
version updates, and a PR. This record is not a reduced P0 scope or completion claim.

## Latest Checkpoint

The previously failing isolated window/history suite now passes on S26U, twice
with different class order (20 cases). Production transcript projection was then
made callable with application Context, preserving the existing UI entry point
and output rules. Its four new no-Activity cases plus those 20 cases passed as
one 24-case run. The subsequent normal full-runtime build and 67 JVM tests passed;
its 1.2.0 (1005) APK is built but not installed. This is shared persistence infrastructure, not yet a complete
process-owned reply consumer. See
[window-independent projection](../testing/MQTT_WINDOW_PROJECTION_20260913.md).

PR preparation has synchronized `origin/main` at `f66030ecb`. That main revision
already uses Android versionCode 1004, so the merged PR source retains versionName
1.2.0 and advances versionCode to 1005. Desktop stays 1.2.0. The deployed Android
artifact described below is still the pre-main-sync 1.2.0 (1002) build; do not
confuse its device evidence with a new 1005 installation. Draft
[PR #3045](https://github.com/galaxyssi/GalaxySSI/pull/3045) is now open against main,
without auto-merge. Post-sync verification passed 67 JVM tests, Android-test
Kotlin compilation, full-runtime APK packaging and 37 Desktop checks. Full
acceptance remains unfinished; the new 1005 APK has not been installed.

The next coordinated PR must use Android/Desktop **v1.2.0**, as explicitly
requested by the user. The earlier version checkpoint set Android 1.2.0 (1002)
and Desktop 1.2.0 in `90bb10c5a`. The user subsequently requested installation and
Desktop startup. Desktop 1.2.0 is now packaged with Python/Signal JVM and running;
its visible window shows v1.2.0 and all three TLS/subscription paths are ready.
Android 1.2.0 (1002) passed the final full-runtime build and 54 focused JVM cases,
then installed successfully with `adb install -r` on S26U (`R5GL546G3LZ`). Its
package metadata and nonblank MainActivity were inspected; pairing/data were
preserved. No other phone was installed or operated in this continuation.
The latest code adds ordered connector reply commits, transactionally idempotent
usage and safe resumption of an already-written orphan reply. The prior checkpoint
passed 51 focused JVM and 12 isolated S26U storage cases. The broader window
regression hit a missing WorkManager initializer; a test-only runner fix is
written but that full suite still needs rerunning. See
[reply commit checkpoint](../testing/MQTT_REPLY_COMMIT_20260913.md).
This is still not a complete headless consumer or the full multi-broker release.

Installed App 1.1.115 (1001) and previously running Desktop 1.1.51 retained the real S20U
QR pairing. The App update passed 43 focused unit tests and a full-runtime build.
It keeps weak final-response consumers available for paused windows and selects
one live consumer per dispatch. Stream UI and plaintext clearing are unchanged.
Device retesting is waiting for screen availability; all-hosts-destroyed headless
consumption remains unfinished.

The user's subsequent request changed installation to S26U (SM-S9480,
`R5GL546G3LZ`). The same full App 1.1.115 (1001) installed successfully without
data clearing or UI interaction. Do not continue the pending S20U screen test
after this target change; no post-fix real model timing has yet been measured.

The prior App 1.1.114 real Codex request/reply completed with the phone on its
launcher. Both endpoints recorded authenticated peer receipts, but Android final
consumption waited 21.9s for recovery after the verified reply arrived. This is
the pre-fix baseline, not a multi-broker delivery failure or a post-fix result.
See [S20U background evidence](../testing/MQTT_S20U_BACKGROUND_20260913.md).

Source Desktop 1.1.52 additionally queues Agent push/mobile diagnostics while
offline and reports acceptance truthfully. Tests and native process-recovery
evidence are in [notification acceptance](../testing/MQTT_NOTIFICATION_QUEUE_20260913.md).
These notification changes are now in the running Desktop 1.2.0 package, but
their new real-phone notification acceptance remains to be tested. Earlier checkpoint sections
below are historical; their pre-install/pre-scan statements do not override this
update. The entire remaining artifact, lifecycle, performance, diagnostics,
power and PR scope is still required.

## Implemented Foundations

- Shared generated broker catalog, no default or manual selection configuration.
- Android and Python scheduling policies: authenticated common-path selection,
  adaptive hedges, critical races, chunk load balancing, global/per-peer budgets,
  metric expiry, network change invalidation, and physical-versus-peer receipts.
- Android and Python independent Paho connection pools: per-path TLS, generations,
  reconnect backoff, exact subscription replay, partial/missing SUBACK handling,
  bounded publish registration, stale-callback rejection, and orderly close.
- Capability schema and canonical digest on both endpoints, rejecting legacy or
  partial single-broker capability announcements.
- Desktop durable per-pair local/remote route epochs in Link delivery metadata.
- Android route-state implementation sharing the Link inbox database; application
  and instrumentation Kotlin compilation passed, followed by six S26U persistence
  tests in the isolated verification package.

## Important Activation Boundary

Desktop `mqtt_bridge.start` now owns the three-path pool in this development
branch, with authenticated per-pair resume exchange and shared physical publish
tokens. Android `GalaxySSIMqttClient.connect` now owns `MqttPoolTransport` and
`MqttPeerRoutes` as well. Shipping applications are unchanged. Do not launch this worktree
against the existing installed Android application as a completed upgrade.

Deployment update, 2026-09-13: the matching full-runtime Android 1.1.114 (1000)
has now been installed on the designated S20U and packaged Desktop 1.1.51 is
running. The three Desktop paths completed TLS, connection and subscriptions;
the pairing QR is displayed. This supersedes the historical no-install status
below, not the outstanding native pairing and business acceptance gates. See
[coordinated deployment](../testing/MQTT_DEPLOYMENT_S20U_20260913.md).

Do not claim automatic fallback, hedging, or striping in the shipping application
on the basis of these isolated modules passing their tests.

## Desktop Small-Message Hedge Checkpoint

The real Desktop durable publisher and bridge ingress now use authenticated
per-attempt frames for small messages, delayed normal/final copies, immediate
typed critical controls, and stored-receipt cancellation/RTT attribution.
Physical PUBACK completion remains distinct from outbox retirement. Dispatch
shares existing capacity, runs in bounded batches on the pool owner's tick,
and revalidates pair/key/generation for each copy. Twenty samples are required
before measured percentile hedge timing replaces the cold value on both endpoints.

The checkpoint passed 338 Python, 143 JVM, 5 catalog, and 51 isolated S20U device
tests (overlapping prior suites, not summed as all-new end-to-end tests). See
[Desktop hedge verification](../testing/MQTT_HEDGED_DISPATCH_DESKTOP_20260913.md).
Android's actual attempt scheduler/receipts, durable attachment striping, and
coordinated shipping deployment are still pending. No production App or Desktop
was replaced, no versions were released, and no PR was submitted.

## Desktop Pool Activation Checkpoint

- The actual Desktop lifecycle uses `MqttPoolClient` and `PeerRoutes`, not a
  separate demonstration entry point. Physical workers use the common catalog,
  independent TLS/reconnect generations, and the existing bounded ingress.
- Logical subscription and publish IDs cannot collide when different brokers
  use the same native MQTT packet ID. Only aggregate zero/one connection
  transitions enter the existing global bridge lifecycle.
- Authenticated `link_resume` requests and acknowledgements run through the
  existing relationship AEAD and identity-scoped ingress. Local epochs are
  persisted before publication; remote epochs are committed before activation.
  Resume ACKs must bind the live local request ID, epoch, and canonical digest.
- A common path requires all receive subscriptions on that path plus a confirmed
  local generation and an unexpired authenticated peer advertisement. Split
  SUBACKs across different brokers cannot falsely confirm pairing. Reconnecting
  the same broker requires a new local epoch/ACK, even if its name is unchanged.
- QR claims use the actual pairing handler and return confirmation on the
  ingress path when it is ready, otherwise another fully subscribed path.
  Pair confirmation does not by itself authorize later business publishing.
- The existing outbox waits for that pair's resume without consuming business
  delivery attempts while no authenticated path is ready. A single failed broker
  does not clear other paths' subscriptions or the shared inbox/run ledger.
- Closing the pool is bounded for the caller, while the owning bridge worker
  remains alive until outstanding connection workers exit. The supervisor cannot
  create an overlapping pool during slow DNS/TLS shutdown.
- Subscription callbacks use cached intent instead of scanning all contacts.
  Indexed inbound lookup revalidates the current pair. Resume admission is bounded
  and keeps its fair rotation through registry refreshes at 10,000 configured
  entries; that is not a 10,000-connection throughput result.
- Health distinguishes physical connections, receive readiness, and authenticated
  peer readiness. It exposes per-broker counts/generations, not private mailboxes.
- This adapter currently submits one physical publication per logical token.
  The policy's full hedges/races, authenticated attempt receipts, durable chunk
  scheduling, and coordinated phone/Desktop acceptance remain unfinished. Do not infer those
  capabilities from this checkpoint or install it as the complete feature.

Verification is documented in
[Desktop pool activation](../testing/MQTT_POOL_ACTIVATION_DESKTOP_20260913.md).
The final combined run passed 418 tests in 50.567 seconds, including 65 focused
pool/resume/pairing/ownership cases and both live JVM recovery modules. It is not
a phone end-to-end or public multi-broker delivery score.

## Integrated Ingress Hardening

The Android pool activation checkpoint now has 126 pure JVM tests and 123 normal
Gradle focused tests (with overlap), plus **37 completed S20U isolated device
tests**. The latter includes SQLite/Signal/security/outbox coverage and one small
synthetic TLS loopback per public broker. All three paths succeeded in that run;
this does not certify real App/Desktop pairing, task delivery, or attachments.
Paho's unbounded zero close timeout was replaced and the completed device close
took 1.53 seconds. An earlier prematurely cleaned-up run is not counted as a pass.
See [Android pool activation](../testing/MQTT_POOL_ACTIVATION_ANDROID_20260913.md).

- Android's actual `messageArrived` now uses one bounded, fair four-worker pool,
  not a permanent executor per Topic. Admission counts retained active payloads;
  rejected admission never sends a peer delivery receipt. Idle lanes are removed
  and idle worker threads exit. There is no Activity/window ownership.
- Subscription reconciliation builds an immutable Topic-to-Signal-identity map
  from configured Desktop/phone relationships. Topic rotation and concurrent
  Broker copies serialize on the same identity. Unknown or ambiguous aliases do
  not allocate a queue. Phone bindings are built in one scan, not one lookup per
  Topic. The obsolete Topic-only worker-scope helper and its test were replaced.
- Desktop's existing `InboundRoutePool` now likewise keys by configured Signal
  identity, preventing different route aliases from racing one Signal session.
- Desktop verifies sender and recipient before durably binding immutable message
  content. `inbound_content_hashes` belongs to the existing Link delivery database
  and stores only hashes, not a new task ledger or plaintext body. Conflicts are
  rejected before Blob persistence and dispatch, with privacy-safe diagnostics.
- Do not confuse this hash binding with durable full-message acceptance. It does
  not by itself fix the Desktop gap between Signal ciphertext binding, message
  storage, receipt emission, and downstream task creation. Desktop atomic receive
  remains a prerequisite for activating the three-path connection pools.

## Android Atomic Receive

- The real Desktop and phone ingress callbacks now commit Signal ratchet changes,
  the decrypted message body, immutable content binding, and verified-ciphertext
  replay binding in one SQLite transaction, before emitting a transport receipt.
  Commit rejection rolls back Signal state as well as the inbox, and is not
  misclassified as a reason to replace a phone's Signal session.
- Signal records moved from per-collection preferences JSON to encrypted individual
  rows in `galaxyssi_link_state_v3`. The inbox and route epochs share that database.
  The new installation format does not migrate old Signal preferences or old inbox
  claims. No current phone or Desktop user data is automatically deleted.
- Inbox keys bind authenticated pairing scope plus message ID, with SQL uniqueness
  and immutable-content checks. A completed record retains its replay tombstone;
  a pending record requires a readable durable body before any replay receipt.
- Bounded paging, eight-day completed-record retention, aggregate and per-peer
  quotas, and bounded alternate ciphertext bindings replace count-pruned global
  IDs. Accepted pending work is never evicted to admit new traffic. Transactional
  usage counters avoid scanning every retained record on each new message.
- Desktop and phone replay use their original handler and revalidate the current
  pair. Local pairing/Blob publication records are likewise pair-scoped. A bounded
  dispatch gate protects asynchronous work from concurrent fresh/replay dispatch.
- Attachment processing remains pending on missing/failed persistence. A foreground
  notification observer no longer completes a message before the foreground UI's
  asynchronous consumer commits it. Existing task/attachment stores remain the
  business idempotency boundary; inbox acceptance is not TASK_ACCEPTED or exactly
  once execution of arbitrary external effects.
- These changes are compiled, with host regressions passing. Real Android storage
  verification uses a separate, non-launchable package and the production Kotlin
  classes, not the production app identity. It is not full transport activation.
- S26U verification passed 29 tests: atomic inbox (17), durable route epochs (6),
  and sensitive-state regressions (6). Real libsignal ratchet/pre-key consumption
  rolled back with a failed inbox transaction, then the same ciphertext succeeded
  on retry. This is exception-injection verification, not a physical process-kill
  or reboot test. See [device report](../testing/MQTT_ATOMIC_INBOX_S26U_20260912.md).

## Desktop Atomic Receive Checkpoint

- Desktop now stores encrypted individual Signal records in `signal_state_v3.db`
  using SQLite WAL/FULL. Ratchet changes, validated plaintext, ciphertext binding,
  and receive quota accounting commit together. No old JSON identity migration or
  automatic deletion of production state is performed.
- The actual sidecar `/decrypt` endpoint returns a durable handoff receipt. The
  Python client persists the full authenticated envelope in the existing delivery
  database before calling `/receive-stored`. It can replay from either database
  after a JVM failure without decrypting an already-consumed ciphertext again.
  This is a recoverable two-stage handoff, not a cross-database transaction.
- Body and cipher identity are scoped to the configured pair and Signal peer;
  conflicts, unreadable bodies, invalid UTF-8, and quota failures fail closed.
  Per-record AEAD includes the record binding. No attachment-file AES is added.
- Bounded background handoff cleanup retries a lost local cleanup response even
  when no further duplicate MQTT packet arrives. Explicit peer/route revocation
  clears the corresponding journal/body data and quota usage.
- A repeated, unchanged in-memory concurrency probe failed 5/10 runs before the
  lock adjustment. Fair striped Signal transaction locks prevent hot work from
  repeatedly overtaking queued receive work; the same probe then passed 10/10
  runs, each with ten workers and 1,000 round trips. This is local scheduling
  evidence, not proof that arbitrary cross-broker network reordering is safe.
- Remaining: business-consumer recovery still needs integration. The old bridge
  `claim_message` / accepted-state shortcuts can skip pending work after a crash;
  storing the full body alone does not fix every handler or authorize repeating
  uncertain side effects. Pending-body replay, completed retention/cleanup, and
  wire ordering/bounded skew must be completed before pool activation.
- See [Desktop receive report](../testing/MQTT_ATOMIC_RECEIVE_DESKTOP_20260912.md).

## Verification So Far

- Python: 127 tests passed, covering broker pools/policy/route epochs, immutable
  content bindings (including three separate Python processes racing SQLite),
  existing Link delivery, bounded ingress, actual bridge dispatch/diagnostics,
  and phone-tool routing. Command from the Desktop backend directory:
  `python -m unittest test_inbound_content_binding test_mqtt_broker_pool test_mqtt_multipath_policy test_mqtt_route_state tests.test_link_delivery test_mqtt_inbound_pool tests.test_mqtt_link_diagnostics tests.test_mqtt_phone_tool_routing tests.test_link_transport_diagnostics -q`
  Runtime state for bridge imports was isolated with `GALAXYSSI_DATA_DIR` and
  `GALAXYSSI_STATE_DIR` under this worktree's ignored build directory. The routing
  fixture now supplies a fake Desktop display name instead of requiring a live
  Signal sidecar, and altered envelopes use a new immutable transport message ID.
- Android host JVM: 77 tests passed, including real Paho interface compilation,
  fake asynchronous connections, races, policy tests, cross-platform digest
  validation, bounded/fair ingress, concurrent broker callbacks, alias identity
  binding, canonical immutable hashes, async dispatch gate races, and cleanup
  after 10,000 historical peers. These are host tests, not
  real 10,000-peer network load. Command: `tools/dev/test-mqtt-multipath-host.ps1`.
- Catalog generation check passed: `python tools/generate_mqtt_catalog.py --check`.
- Five catalog-generation regression tests passed:
  `python -m unittest tools.test_generate_mqtt_catalog -q`.
- Total distinct executed host tests above: 209 (127 backend + 77 Android JVM + 5
  catalog). Re-running a test through Gradle is not counted as another distinct test.
- Full Gradle focused tests also passed: 66 tests, zero failures/errors:
  `GalaxySSILinkProtocolTest` (35), `MqttInboundRoutePoolTest` (13), and
  `MqttInboundBindingsTest` (5), `MqttImmutableContentTest` (7), and
  `MqttInboxDispatchGateTest` (6). These latter 31 overlap the host suite, so the
  combined distinct executed host test count is 244. Command from
  `apps/android`: `./gradlew.bat :app:testDebugUnitTest --tests com.galaxyssi.chat.MqttInboundRoutePoolTest --tests com.galaxyssi.chat.MqttInboundBindingsTest --tests com.galaxyssi.chat.GalaxySSILinkProtocolTest --tests com.galaxyssi.chat.MqttImmutableContentTest --tests com.galaxyssi.chat.MqttInboxDispatchGateTest -x :app:buildNativeMemory '-Pgalaxyssi.requireEmbeddedRuntime=false' --max-workers=2 --console=plain`.
- Low-volume real public loopback: one 75-byte synthetic packet on each available
  path, without app data or pairing keys. HiveMQ: connect 2516 ms, subscribed
  2907 ms, loopback 390 ms. Mosquitto: connect 3813 ms, subscribed 4188 ms,
  loopback 391 ms. EMQX returned CONNACK reason 136 and did not prevent the other
  paths from working. This is one local-exit smoke, not throughput, p95, or
  application delivery evidence.
- The smoke's generated report is under `build/reports/mqtt-multipath/`. A shutdown
  callback in the first report changes displayed final states to `closed`; the
  pre-close `snapshot` records the actual successful connections. The smoke script
  has since been fixed to preserve pre-close observations.
- Android `:app:compileDebugKotlin` passed in 4m 46s and
  `:app:compileDebugAndroidTestKotlin` passed in 8m 19s. Both excluded native memory
  generation and disabled embedded runtime packaging, for Kotlin/API validation
  only. No APK was produced by these compile checks. A subsequent pure-policy
  tracking-reservation adjustment was recompiled by the JVM host suite.
- Kotlin source-size policy and staged diff whitespace checks passed.
- The integrated Android ingress compiled with `:app:compileDebugKotlin` in
  3m 49s. Subsequent removal of the obsolete Topic-only helper is being checked
  by the full Gradle focused unit-test task, which passed in 6m 27s including
  recompilation of main and test Kotlin. This is not APK packaging or phone installation.
- Atomic receive: normal main compilation passed in 6m 23s, followed by normal
  instrumentation compilation plus 66 focused unit tests in 2m 57s. The final
  isolated package compiled the later quota/dispatch changes and built successfully
  in 13m 9s; S26U passed 29 selected tests. Combined distinct executed tests across
  the documented host/device suites are 273; this is not 273 end-to-end MQTT tests.

## Remaining Integration

The 2026-09-13 Desktop stored-message dispatch checkpoint passed 262 backend
tests, including 34 focused ownership/real-bridge cases and live JVM recovery.
See [Desktop stored dispatch](../testing/MQTT_STORED_DISPATCH_DESKTOP_20260913.md).
This supersedes the earlier statement that the actual bridge still used an
ID-only accepted-state skip; it does not activate the three-path transport.

1. Android and Desktop actual connection entry points now own their pools.
   Verify one shared application/service owner across ten real windows and the
   full device lifecycle; host compilation is not this acceptance.
2. Android authenticated resume and pairing/app-to-app publishing are integrated.
   Both endpoints' request/response and epoch refresh have host coverage, but
   cross-platform wire/device pairing acceptance remains outstanding.
3. Integrate generation-scoped physical attempts with the current publisher,
   outbox, receipt handlers, timing, subscription coordinator, and Run Kernel.
   Do not reset global business state when one path disconnects.
4. Complete immutable content binding and atomic durable acceptance before business
   side effects. Desktop now atomically journals ratchet/plaintext and durably
   hands the full body to Python. Its actual bridge now dispatches and recovers
   stored bodies through the existing business handlers and task manager; the
   ID-only skip/early accepted shortcut has been removed. OS locks guard actual
   handler ownership; pending work uses indexed, bounded service-owned admission.
   Completed-body retention/compaction and broader side-effect reconciliation,
   including interrupted cancel generation fencing, remain to be finished.
   Android now uses a shared Signal/inbox transaction;
   verify real native rollback and process-death recovery before activation.
   Outgoing receipts now validate authenticated current pair/key, stable message
   ID, complete durable-receive status, and a shared Signal wire digest against
   the persisted outbox proof. See [receipt binding](../testing/MQTT_DURABLE_RECEIPTS_20260913.md).
   Both Desktop and Android small-message physical attempts are now integrated.
   Android's actual publisher/receiver uses the symmetric dispatcher and stored
   receipt guard; see [Android dispatch](../testing/MQTT_HEDGED_DISPATCH_ANDROID_20260913.md).
   Actual cross-platform native Signal/MQTT acceptance remains outstanding.
5. Authenticated per-attempt/frame metadata and transport receipt codecs now have
   shared Android/Python vectors and negative tests. Desktop small-message
   dispatch/RTT and its Android counterpart are activated and use the final
   encoded frame bound. Account for frame overhead before current 512 KiB privacy buckets
   and chunk splitting; do not silently overflow existing direct-wire limits.
6. Android and Desktop actual `signal-chunk` receive paths now persist fragments
   in their existing Link/Signal databases, scoped to authenticated pair/key
   rather than receive Topic. Complete bytes wait for a committed inbox proof
   before release. S20U storage and explicit process-stop recovery passed; see
   [durable fragments](../testing/MQTT_DURABLE_CHUNKS_20260913.md).
   Authenticated bitmap acknowledgement, persisted outbound fragment state,
   alternate-path missing-only retry, and compact-proof queries are now wired
   into both actual publishers/receivers; see
   [fragment state exchange](../testing/MQTT_CHUNK_STATE_20260913.md).
   Window-coalesced feedback and acknowledged encoded-wire throughput scheduling
   are now integrated in both actual pools. See
   [chunk flow checkpoint](../testing/MQTT_CHUNK_FLOW_20260913.md).
   Finer retry timing, coordinated revocation/quota cleanup and final artifact
   acceptance remain. Reported speed is not raw attachment goodput.
7. Bounded Android ingress and both endpoints' per-Signal-identity serialization
   are integrated. Continue evaluating aggregate limits and real-device latency
   when the full transport is activated; isolated 10,000-peer lane cleanup is not
   a claim of 10,000 simultaneous model tasks.
8. Read-only connection diagnostics, coalesced progress, prioritized final/control
   traffic, automatic internal rollback to one observed healthy common path.
9. Run integration/fault matrices on owned test brokers, then designated-device
   tests. The latest user update switched this round to connected S20U (SM-G9880,
   ADB serial `R5CN319CESA`). The prior 37-case pool verification completed; the
   durable-receipt checkpoint separately passed 47 isolated device cases and the
   subsequent hedge-policy checkpoint passed 51 and Android-dispatch checkpoint
   passed 55 (including overlapping storage cases, not 190 distinct tests);
   the subsequent fragment checkpoint passed 68 device cases plus one separate
   two-phase process-stop recovery scenario (55 of the 68 overlap the prior
   checkpoint). The subsequent chunk-state checkpoint passed 86 device tests
   (including those 68) and repeated the two-phase actual process-stop case with
   persisted outgoing bitmap/path attempts. See its linked verification record
   for 216 backend and 178 JVM regression evidence and test boundaries.
   The chunk-flow checkpoint subsequently passed 87 S20U tests, the separate
   two-phase process-stop case, 228 backend and 190 host JVM cases, plus 105
   ordinary-configuration Android unit tests. Counts overlap prior checkpoints.
   An owned loopback TLS lab also exercises the real Desktop pool, authenticated
   resume, bidirectional transport and one-broker stop/restart; it is not native
   Signal, full UI/attachment, public-provider performance or phone power proof.
   A subsequent [native business checkpoint](../testing/MQTT_NATIVE_BUSINESS_20260913.md)
   now exercises real JVM Signal, actual contact dispatch, three-path duplicates,
   lost receipts, both endpoint process deaths and all-path outage recovery on
   the owned lab. It also fixes delayed old resume ACK handling symmetrically.
   This is not the QR ceremony, Android-native cross-platform delivery or full
   UI acceptance; the Desktop UI offline-send gate remains to be integrated.
   The later coordinated deployment installed the full production-package App
   on S20U and checked its main UI. Test-owned packages were removed after the
   earlier instrumentation; the pre-existing test package remains.
   Do not operate S26U or SM-T575 in this round.
   Earlier 29-test S26U evidence remains historical, not S20U acceptance.
   Isolated verification must not replace production
   app data; coordinated full installation and re-pairing remain separate steps.
10. Collect honest cold/warm latency, p50/p95, redundant traffic, background,
    recovery, and power evidence. Do not load-test public brokers.
11. Main was synced through `6e303ed06`, versions were bumped to Android
    1.1.113 (999) and Desktop 1.1.50, and full packages were deployed on S20U
    and this Desktop. No production uninstall or history deletion was performed
    during this deployment. Refresh main again before the eventual PR and finish
    the remaining acceptance gates. No PR has been submitted from this worktree;
    local commits remain development checkpoints, not complete-feature releases.

## Compatibility Decision

The user explicitly stated that this is development: they will uninstall and
reinstall the app and scan again. Build one new protocol across Android/Desktop;
do not add old-client capability fallback. This does not authorize silently
deleting their current app, chat history, or Desktop authorization records now.
