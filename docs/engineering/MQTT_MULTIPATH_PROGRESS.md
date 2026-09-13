# Multi-Broker Implementation Progress

Branch: `feat/automatic-multi-broker-20260912`

Base: `2c4a76415` (latest origin/main when this worktree was created).

The goal remains the complete Android + Desktop specification, including real
pairing, task delivery, attachments, recovery, diagnostics, performance evidence,
version updates, and a PR. This record is not a reduced P0 scope or completion claim.

## Latest Checkpoint

Latest development artifacts were built from code revision `a36b6b240`: Android
1.2.0 (1005), 421,145,752 bytes, valid debug v2 signature, embedded-runtime/16KB/QNN
checks passed; all 293 prior lib/assets entries remain byte-identical. A separate
Desktop package bundles Python and the rebuilt Signal sidecar, with verified
Windows version resources 1.2.0.0 / 1.2.0 and 291 matching backend source files.
The final isolated packaged backend/UI smoke passes after configuring a separate
Git source checkout and shorter test temp directory; failed attempts are retained.
See [artifact evidence](../testing/MQTT_RELEASE_ARTIFACTS_20260913.md). No production
Desktop replacement or phone installation occurred. The acceptance backlog and
goal remain open; artifact generation is not device/performance acceptance.

## Previous Path State Checkpoint

Android now displays local path lifecycle, per-path reconnect attempts and
broker-pending sends in its existing protocol diagnostics. Desktop exposes the
equivalent lifecycle/counters in the existing diagnostics response. Complete
desired subscriptions are required for local receive-ready status; it never
means peer delivery. Android's 214 host tests and full Kotlin/resource compile
pass; Desktop's 68 focused tests and 44 checks/structure pass. Native Signal
recovery passes 20 business messages / three path cycles with empty endpoint
logs. See [path diagnostic evidence](../testing/MQTT_PATH_STATE_DIAGNOSTICS_20260913.md).
No device installation, rendered Android verification or production restart was
performed. The full acceptance backlog remains open; this is not completion.

## Previous Packaging Checkpoint

Desktop packaging now requires its declared executable-resource tool before any
sidecar build or packaged-process stop, and verifies Windows resource readback
instead of warning and reporting success with Electron metadata. Seven focused
tests and all 44 Desktop checks pass. An isolated copied executable now reports
FileVersion 1.2.0.0 / ProductVersion 1.2.0 and the correct product fields using the
lockfile-verified rcedit binary. The full production package was not rebuilt or
started. See [resource gate evidence](../testing/MQTT_DESKTOP_PACKAGE_RESOURCES_20260913.md).
This clears the source-level silent-failure defect, not the final package/runtime
release gate. PR #3045 remains the user's stop boundary.

## Previous Diagnostic Checkpoint

Both endpoint policies now provide bounded recent verified-delivery observations,
with 32 samples per path, TTL filtering, peer removal and network-reset cleanup.
PUBACKs, wrong/duplicate receipts and unattributed completion do not become RTT
samples. Missing values stay null, and p95 requires 30 samples. Android's existing
protocol diagnostic rows and Desktop's loopback diagnostic response expose this
data without changing chat UI or routing. The full Android resource/Kotlin build
and final-source incremental confirmation pass; 210 Android host cases and 124
combined Desktop cases pass, as do Desktop's 37 checks and structure check. The
native diagnostic run passed 20 business messages / three path cycles with empty
endpoint logs; real receipt samples appear on observed paths while unobserved
paths and small-sample p95 stay null.
See [delivery diagnostics](../testing/MQTT_DELIVERY_DIAGNOSTICS_20260913.md).
This is not full diagnostic/status, device or performance acceptance. S26U remains
absent; SM-T575 and the production Desktop are not operated. No APK was packaged
or installed in this diagnostic checkpoint. PR #3045 remains the stop boundary.

## Previous Admission Checkpoint

Per-invocation receive instrumentation identified a queue-admission race:
background recovery could reserve a newly stored message before its live handler
claimed it, unnecessarily deferring that first authenticated delivery. A live
never-executed `stored` message may now proceed under its existing OS guard;
retry backoff and interrupted unsafe-effect handling remain unchanged. The
deterministic live-first regression was red before the fix. Expanded backend
tests pass 242 cases, native-tool tests 41, and Desktop checks 37 plus structure.

The first post-fix native control/load run passed 61 cancellations, all 30 load
overlap checks and a complete 32 MiB artifact with one available result. All
30 requests and returns in each measured cohort ran live, with no recovery
deferral or dropped observations. Loaded cancel-result p95 was 4905.64ms,
passing the existing 8000ms provisional budget. A structure check overlapped
the beginning of that run. An isolated repeat also passed all business and
live-receive checks, with loaded cancel-result p95 6291.23ms. Post-change native
recovery also passed 20 business messages / three path cycles, with normal exit
and empty endpoint logs. See [live admission evidence](../testing/MQTT_LIVE_ADMISSION_20260913.md).
The complete acceptance backlog below remains open. Per the user's latest
instruction, PR #3045 is the stop boundary; no additional feature scope follows
this PR. No phone or production Desktop was operated in this checkpoint.

## Previous Lock Checkpoint

Desktop's broker pool now releases its state lock before calling Paho publish,
while retaining bounded in-progress reservations and validating the connection
generation again after publication. Deterministic pre-fix tests reproduced a
Paho/PUBACK lock inversion and stale packet registration across disconnect;
both pass after the fix. Concurrent early ACKs, failed publication cleanup and
the unchanged capacity bound are also covered. The focused regression selection
passes 167 cases; 36 native-tool tests pass in their documented environments.

Two post-fix native load runs each passed 61 durable cancellations and a complete
32 MiB artifact with one available result and no shutdown/cleanup errors.
Loaded cancel-result p95 was 9556.26ms / 12504.30ms, both **failing** the
unchanged 8000ms budget. Paired original ACK calls in the repeat took 313.07ms
p95, with no multi-second ACK-return-to-dispatch gap. Receive queue/decrypt/store
and return-delivery stages remain to be measured before the next optimization.
The earlier ACK-profile run that hung during attachment completion remains
recorded; no stack was captured there, so its exact cause is not claimed proven.
The lab now records paired per-call ACK stages, retains completed samples on a
later failure, and captures stacks on long RPCs/shutdown. See the
[control/load evidence](../testing/MQTT_CONTROL_ATTACHMENT_20260913.md).
No phone or production Desktop was operated; full acceptance remains incomplete.
The final post-fix owned native recovery run passed 20 business messages and
three path cycles, with empty endpoint logs and a normal exit.

## Previous Control Checkpoint

An owned native control/load harness now checks real authenticated task
cancellation and durable task status while a 32 MiB file is being received.
Two runs each passed 61 cancellations (30 idle, 30 loaded, one excluded warm-up),
all 30 measured overlap checks, and exact file/stream hashes with one available
artifact. Loaded cancellation-result p95 was 8096.08ms then 6760.19ms against a
predeclared 8000ms budget: one failure and one pass, **not stable acceptance**.
No production code changed between those runs. Receiver-local stage measurements
narrow the next investigation toward pre-dispatch receive/ACK handling; they do
not prove a broker or lock is at fault. The tooling's 29 unit tests and Desktop's
37 checks passed. See [control/load evidence](../testing/MQTT_CONTROL_ATTACHMENT_20260913.md).
This remains a no-model Desktop receiver with phone-shaped payload fixtures,
not Android/P2 striping, real provider interruption, UI or release acceptance.
S26U remains absent; no other phone or running Desktop instance was operated.

## Previous Query Checkpoint

The receive-backlog query now uses a partial large-body index instead of scanning
all completed small-message history per admission. The 10,000-row deterministic
test falls from 130,000 SQLite VM instructions to fewer than 100, with no temporary
sort. Final regressions passed 339 Python cases (including 72 focused), Desktop's
37 checks, and native PNG/video ingress. Two real 30-per-strategy small-message
runs before/after this index passed the existing 1.10 within-run p95 ratio budget
(0.920/0.976), with 66 business checks each and no redundant submitted frames.
These timings do not establish a causal cross-run speedup or phone/public-network
performance. See [query and latency evidence](../testing/MQTT_RECEIVE_INDEX_20260913.md).
No production deployment occurred; S26U/device and full release gates remain open.

## Previous Compaction Checkpoint

Real native input-attachment testing exposed retained completed Signal bodies
filling the per-peer 16 MiB quota. Desktop now atomically replaces successfully
dispatched, native-released large bodies with bounded non-executable proofs,
retaining message/content/cipher identities and duplicate ACK safety. The
post-fix owned PNG, H.264/AAC, 5 MiB and 21 MiB run passed; the 21 MiB case
includes receiver process death, one path loss and replay of a completed chunk.
The final receive quota accounting was 181631 bytes, not physical SQLite size.
Focused tests passed 69 cases; the final expanded selection passed 336. An
independent repeat also passed all previous cases and a 32 MiB file, leaving
367384 quota-accounted bytes after 234 completed chunk records. See
[native attachment/compaction evidence](../testing/MQTT_RECEIVE_COMPACTION_20260913.md),
including failed runs and the test workspace isolation correction. This is a
Desktop receiver test with a phone-payload fixture, not Android/UI or a P2
performance completion claim. No production deployment occurred.
The subsequent native regression passed 20 business messages and three path
cycles with empty endpoint logs, including delayed receipts and deferred sends.

## Previous Receipt Checkpoint

The shared unsampled hedge now waits 2s while the independent unknown-path
ranking prior remains 500ms. Two owned 30-per-strategy healthy runs passed the
provisional p95 ratio gate (0.977 and 0.859), with no redundant business frames.
A separate selected-primary-loss run passed thirty injected samples with a
3.010s p95 under the predeclared 8s budget. These do not prove Internet/Android
performance or that the selected primary was the physically fastest. Earlier
failed cohorts remain visible in the [cold-hedge report](../testing/MQTT_COLD_HEDGE_20260913.md).

The subsequent native recovery smoke failed: stored business data did not retire
the sender outbox after a single path returned. A deterministic bridge case
reproduced a missing stored-receipt retry during the receiver's local resume.
Android and Desktop now retain bounded short-lived receipt proofs, retry through
the existing maintenance owner, and revalidate authorization before publication.
Final regressions passed 282 Python (including the 104-case focused selection)
and 206 host Kotlin cases. Owned native runs
passed 40 and 20 business messages; the latter deliberately holds real resume
ACKs and verifies recovery before the sender's 30s replay. See
[receipt recovery](../testing/MQTT_RECEIPT_RETRY_20260913.md). The normal full-runtime
Android build and instrumentation Kotlin compilation passed in 8m 59s, with 91
focused JVM cases. APK 1.2.0 (1005) is built and archived. No phone installation
or production Desktop replacement occurred.
All full-scope acceptance gates remain active; PR #3045 is still a draft.

## Prior Checkpoints

Native owned-network measurement now captures real durable-queue, physical-send
and authenticated receipt-commit timestamps instead of controller polling. Two
30-per-strategy baselines exposed redundant cold hedges. Android/Desktop now
share recent samples across eligible paths of the same peer until the primary
has its own full window, while still requiring twenty samples and preserving
immediate stop/cancel racing. Tests passed: 93 focused Python, 195 host Kotlin,
10 measurement/CLI, plus 79 ordinary Android JVM cases and a full-runtime build
in 9m 1s. The owned native fault run passed 19 business messages.

Two post-change performance runs each passed all 66 business checks. One passed
the provisional p95 ratio gate (0.669), but the other **failed** (1.577), with
13 redundant frames confined to its first sample-poor multi-path block. Stable
non-regression is not established; the 500ms under-twenty-sample default and
failed-fastest-path/cold-start matrix remain to investigate. Do not select only
the passing run. The CLI now returns 2 for a failed provisional gate. See
[native latency checkpoint](../testing/MQTT_NATIVE_LATENCY_20260913.md).
The full APK remains 1.2.0 (1005), newly built but not installed. Draft PR #3045
remains the delivery vehicle. S26U is absent; no other phone or production
Desktop instance was operated in this checkpoint. All larger-scope gates below
remain, including artifacts, pairing, ten real windows, Doze and power.

An owned-network timeout led to a deterministic Desktop publisher defect:
authenticated readiness can expire after outbox selection, and the deferred
result was incorrectly registered as a nonexistent broker token zero. The
publisher now preserves the queued ciphertext and releases the unsent selection
without consuming retry budget. Final expanded Desktop regression passed 169
cases. Native TLS/Signal boundary verification and three path rotations passed
19 business messages with empty endpoint logs. The earlier pre-fix 30-cycle
baseline passed 99 messages but did not reproduce the first intermittent timeout.
S26U remains absent and no other phone was operated. See
[deferred selection checkpoint](../testing/MQTT_DEFERRED_SELECTION_20260913.md).

The ordinary connector inbox now has a process-owned WorkManager fallback after
page consumers, using the original task runtime, supervisor lease and shared
finalization/projection. Startup scans restore its durable wake-ups. Seven device
cases are added, but the designated S26U is disconnected and no substitute phone
was operated. This is not yet a passed headless lifecycle gate. See
[background connector checkpoint](../testing/MQTT_BACKGROUND_CONNECTOR_20260913.md)
for verification and remaining partial-commit/timeline boundaries.
Final normal full-runtime build passed in 5m 1s with 102 JVM cases across nine
suites. APK 1.2.0 (1005) is built, not installed; Desktop is unchanged. These
results do not establish the new device/lifecycle acceptance gate.

The next headless-consumer integration exposed a prerequisite in run recording:
window/background instances had independent stale caches, and an older run's
completion selected that old run as the current conversation head. The recorder
now has a single application-Context owner shared by all callers, and historical
updates do not select a run. Seven new encrypted-recorder device cases plus the
prior 28 cases passed on S26U (35 total); the new seven passed independently again.
This is shared run ownership, not completed headless connector consumption. See
[run recorder ownership](../testing/MQTT_RUN_RECORDER_OWNERSHIP_20260913.md).
The normal full-runtime build subsequently passed in 4m 39s with 154 JVM tests
across 19 suites. Its 1.2.0 (1005) APK is built but not installed. Both isolated
test packages were removed; S26U production is still 1002 and Desktop is unchanged.

The production background recovery worker now commits its result to the original
transcript before workspace completion, with a scoped pending checkpoint and a
projection-only replay path that does not instantiate the Agent runtime. Its
redundant approval loop was removed. Four new real-worker cases plus the prior
24 cases passed on S26U (28 total, 6.322s); the four new cases passed independently
again. This includes ten concurrent saved-result workers, not ten live models or
Activity windows. The ordinary connector inbox's complete process-owned consumer
remains unfinished. See [recovery result projection](../testing/MQTT_RECOVERY_TRANSCRIPT_20260913.md).
The normal full-runtime build then passed in 7m 38s with 129 JVM tests across
17 suites. Its 1.2.0 (1005) APK is built but not installed; S26U production remains
1002 and both isolated test packages were removed. No Desktop changes in this
follow-up.

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

## Current Acceptance Backlog

This is the current status grouping, not a percentage-complete estimate. All
numbered specification requirements still apply; these six groups collect
remaining work rather than replacing those requirements with six narrow tests.

| Group | Current evidence | Still required |
| --- | --- | --- |
| Performance | Prior lock-fix failures are retained; receive admission was then fixed, with two native control/load passes at 4.906s / 6.291s p95 under the unchanged 8s budget | Repeat single/hedged/striped cold/warm and faulted-path comparisons; verify Android and real model/control latency |
| Pairing and devices | Both endpoint pools and authenticated routing are integrated; earlier device/host checkpoints exist | Fresh coordinated S26U/Desktop pairing, all discovery paths, App/App and multiple-phone route isolation, controlled small public-provider compatibility checks |
| End-to-end artifacts | Native Desktop ingress verifies PNG/video/5/21/32 MiB, hashes, recovery and one artifact | Real Android/P2 striping, both directions, preview/open/save, missing-only alternate-path recovery and full revocation/quota cleanup |
| Windows and background tasks | Shared stores, supervisor ownership and partial no-Activity result projection are implemented/tested | Ten real windows/model tasks, closing all Activities, complete continuation/learning/handoff projection and interrupted commit recovery |
| Failure and safety matrix | Owned native process deaths, path losses, receipt loss, duplicates and negative host tests cover subsets | Full cross-platform network/Doze/reboot/reordering/concurrent-artifact matrix, correct status and no duplicated effects or task reassignment |
| Diagnostics and resources | Per-path transport observations and bounded ownership exist; verified-delivery windows are now exposed in Android protocol diagnostics and the Desktop diagnostic response | Product diagnostic/status acceptance, retry/byte/throughput presentation, single/three-connection PSS/CPU/threads/network/power comparison on Wi-Fi/mobile/weak links; repeated screen-off long runs |

Release closure is additional: finish gates, package the final Desktop, verify
its Windows executable resource metadata on the final package, install the coordinated final APK on
the explicitly authorized device, and finalize the evidence/PR. PR #3045 is
already OPEN/DRAFT. Public versions are Android/Desktop 1.2.0; the current
Android source/build uses versionCode 1005. Source/test changes after packaging
are not deployed merely because the version string matches.

Current device scope is S26U only. On this checkpoint ADB shows SM-T575 instead;
it is not operated. Historical S20U scope below is archived evidence, not current
permission or a statement that the newest builds were installed there.

## Historical Integration Checklist

The following checklist predates several checkpoints above. Version, deployment,
PR and remaining-work statements are historical and are superseded by the
current acceptance backlog; retain them only to understand earlier evidence.

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
