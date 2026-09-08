# S20U fair scheduler and delivery investigation

## Scope and devices

- Android: GalaxySSI 1.1.6 (892), SM-G9880 (S20U).
- Desktop: 1.1.15 working-tree build; no UI changes.
- Only the S20U was operated. App data and pairing were preserved.
- Generated fixtures use unique private conversations, task and turn IDs, and a
  small image containing `2 + 2 = 4`. No personal images are used.

## Implemented boundaries

- Local admission keys contain App route, conversation, client turn, task, and
  execution generation. Apps and their conversations use round-robin queues.
- The regular pool has 10 workers and 10,000 pending slots. A separate bounded
  two-worker control pool permits steering while regular tasks are running.
- Asynchronous Codex execution holds its admission slot until its task reaches a
  terminal, paused, or superseded-generation boundary.
- The task ledger records a dispatch boundary before the executor is called.
  Never-dispatched queued tasks retain their retry budget across restarts;
  ambiguous/already-dispatched tasks still consume the recovery budget.
- Pausing preserves the dispatch checkpoint. Persistence failure prevents
  execution. Old-generation running transitions and monitoring are rejected.
- Attachment receipt/request messages receive dependency priority 95, below
  final results (100), with access to the existing bounded reserved send lane.
  Attachment data remains normal priority.

## Local evidence

- 104 lifecycle, persistence, route and scheduler tests passed after the dispatch
  checkpoint change (`build/fair-pool-recovery-boundary-tests.log`).
- 18 durable MQTT/batching tests and two subtests passed after the dependency
  priority change.
- The synthetic 10,000-job pool test completed with 10 workers. This is not
  evidence of 10,000 concurrent model processes or multi-node execution.
- Repository `npm run check` passed.

## Real-device evidence before the priority fix

- First Desktop 1.1.13 text request: 14,152 ms, generation 1, expected marker.
- Repeat text request: 15,307 ms, generation 1, expected marker.
- Both subsequent image requests timed out at 180 seconds.
- Diagnostic correction: the image bytes did reach Desktop. For fixture
  `delivery-probe-857f43dd-284f-4349-87fa-725589d4688a-task`, the 4,442-byte image
  completed on Desktop at timestamp 1788888309844, approximately one second
  after the phone started sending it.
- The phone retained the dependent task as queued, attempts 0, blocked count 1.
  Its manifest/chunk outbox entries were no longer pending. The model task was
  never created. This isolates the delay to attachment acknowledgement and
  dependency release, not image size or model inference.
- No Blob outgoing journal exists on this device; these requests used MQTT.
- Signal decryption failures also appeared. Their causal relationship to the
  missing acknowledgement is not yet established. No encryption was disabled.

## Ten-stream real-device run on 1.1.14

- Ten streams submitted text concurrently; each stream submitted an image after
  its text completed. Eight streams completed both requests: 16 successful
  requests out of 18 actually sent. Two remaining images were not submitted
  because their prerequisite text requests timed out. Do not report 20 passes.
- Successful text requests took 11,443-21,458 ms; successful images took
  18,610-32,593 ms. Each passed marker, full request identity, generation 1,
  terminal success and image-answer assertions.
- The two text tasks below never appeared in Desktop's task manager or latency
  log during the test:
  `delivery-probe-238652dc-fdc2-497d-b708-cf59f9ec1da6-task` and
  `delivery-probe-bdd52f85-1ae9-4eab-ac34-4914f6150f3a-task`.
- Both phone and Desktop logs contained Signal decryption failures. Python's
  sidecar client already serializes operations per peer, and Android encrypt/
  decrypt methods are synchronized. A crypto race is therefore not proven by
  the logs alone; diagnose delivery/ciphertext state before changing the locks.
- The instrumentation failed at 183.825 seconds. Evidence:
  `build/s20u-ten-streams-live.log`, `build/s20u-ten-streams-device.log`.
- Sparse pool samples peaked at three active workers and returned to zero.
  This run proves concurrent client submission, not ten simultaneously running
  provider processes. Sustained provider saturation needs a separate test.

## Outstanding acceptance work

- Desktop 1.1.14 sequential real-device check passed: text 19,387 ms and image
  19,915 ms, generation 1, correct unique markers and image arithmetic. Full
  instrumentation duration was 42.34 seconds
  (`build/s20u-priority-delivery-live.log`). This supports the priority fix but
  does not establish sustained concurrent reliability.
- Resolve the two missing concurrent text requests and repeat the ten-stream
  test. Retain failure evidence; do not bypass encryption or reset pairing.
- Persist and restore complete queued request metadata, including attachment
  descriptors and model selection. Never-dispatched Codex recovery must start
  admitted work, whereas dispatched work must reconnect without duplication.
- Audit every asynchronous event mutation for atomic generation fencing, not
  only the initial callback check.
- Verify real interruption/restart and paired-App collision scenarios.
- Implement and test multi-node ownership, leases, fencing, and failover. The
  current scheduler is single-node only.

This report is partial progress, not full acceptance of the Agent isolation,
durable recovery, and multi-node scaling goal.

## Sidecar transaction hardening and 1.1.15 retest

- Signal encrypt/decrypt and peer replacement/removal now hold a server-side,
  bounded, peer-name-scoped lock across the entire session operation. The
  existing Python per-peer lock remains. This protects direct or overlapping
  HTTP callers too; it does not prove the previous failure was a lock race.
- `verifySignalConcurrency` passed 1,000 native libsignal round trips on 10
  threads with exact request/reply marker comparisons, using fresh in-memory
  identities. The sidecar distribution built successfully. Runtime health
  reported `sessionTransactions=true` after deployment.
- S20U's next ten-stream run received all ten text responses, taking
  29,637-88,880 ms. Only one of the ten subsequent images completed before the
  harness failed: 83,676 ms. Full test duration was 216.955 seconds. This is a
  failed end-to-end concurrency test, not 100% success.
- No Signal decryption exception was present in that phone process's log, but
  this observation is not proof of absence across all runs or endpoints.
- Desktop had already completed several image model tasks while the phone was
  still waiting. Read-only outbox metadata showed 2,031 queued normal-priority
  messages, plus published dependency and final-result messages. Both queue
  pressure and receipt delivery need further measurement; do not attribute
  variable public-broker performance to the new lock without additional data.
- The original two failed text requests remained in the phone outbox with
  `awaiting_delivery_confirmation`, five attempts and no attachment dependency.
  This is separate evidence from the new run, not a successful recovery claim.
- Evidence: `build/sidecar-session-concurrency.log`,
  `build/s20u-ten-streams-session-lock-live.log`,
  `build/s20u-session-lock-device.log`.
- Post-run read-only diagnostics at 02:05 local time found zero phone transport
  receipt journal rows. Image sources 1788890092409 and 1788890092410 had no
  outgoing request rows, remained nonterminal in the pending delivery journal,
  and had completed Desktop task records. This rules out a *persisting* phone
  request/receipt queue for those two requests at that observation time, not
  transient backlog earlier in the run. Next, correlate the Desktop result's
  encrypted transport message, peer receipt, and phone task-identity filter.

## Confirmed disconnect deadlock and Desktop 1.1.16

- At 02:18 local time, live health reported MQTT disconnected for more than
  twenty minutes despite a live worker and supervisor. A `py-spy dump` of
  backend PID 20336 showed the network thread in `on_disconnect` waiting for
  `pending_outbound_acks_lock`. The route worker held that lock across
  `publish()`, which entered Paho's disconnect handling and waited for its
  callback mutex. Other result/retry threads were waiting behind these locks.
- Durable sending now performs MQTT I/O outside the acknowledgement-map lock.
  A bounded, client/generation-scoped early-ACK history closes the registration
  race, including the interval before Paho marks its message info complete.
  A publish interrupted by a generation change remains retryable, and negative
  PUBACKs no longer mark delivery as published.
- Nine new callback-ordering tests cover early/late ACKs, negative ACKs,
  generation changes, client isolation, bounded history and disconnect during
  durable publish. Combined with route tests: 28 tests passed. Durable delivery,
  batching and the new tests: 27 tests plus two subtests passed. These counts
  overlap and must not be summed. Desktop's 29 JS checks and root repository
  checks also passed.
- The deadlocked Desktop was closed only after verifying zero active/pending
  model work. Desktop 1.1.16 started with the existing identity and pairing.
  No phone data was reset. S20U remains Android 1.1.6 (892).
- The sequential real test passed in 51.938 seconds: text 24,373 ms, image
  24,718 ms, exact identities, generation 1 and correct answer/markers.
  Latency telemetry now includes `desktop_peer_received` events (13 observed
  after this deployment), unlike the previous stalled observation. This proves
  receipt processing resumed; it does not independently prove every historical
  queued message was delivered.
- Evidence: `build/s20u-publish-lock-live.log` and
  `build/fair-pool-publish-lock-check.log`. The ten-stream retest is recorded
  separately below when complete.
- Remaining lock audit: fragmented sending also calls MQTT while holding its
  fragment-state lock. It needs a separate callback-safe dispatch/registration
  design and adversarial tests; this patch does not claim all publish paths
  are free of lock inversion. All recovery and multi-node acceptance items
  above remain open.

## Ten-stream real-device run on 1.1.16

- PASSED in 144.225 seconds: all ten text and all ten image requests returned
  successfully, with exact App/conversation/turn/task identity, generation 1,
  unique markers and the image arithmetic assertion. Each stream sent its
  image only after its text reply. This is twenty distinct test conversations,
  not a same-conversation multi-turn or multi-App isolation stress test.
- Text: 15,378-70,241 ms. Image: 47,456-102,482 ms. These high latencies are not
  a performance acceptance pass. The final four image tasks spent about eight
  to nine seconds between Desktop's `started_at` and `completed_at`; their
  much longer end-to-end times warrant further attachment admission and result
  delivery measurements, not larger model timeouts.
- One live scheduler sample observed four active workers; the pool returned to
  zero active/pending work after the run. This is not proof of ten simultaneous
  provider processes. Desktop remained connected, ready, with all ten expected
  subscriptions active after the run.
- Evidence: `build/s20u-ten-streams-publish-lock-live.log`,
  `build/s20u-ten-streams-publish-lock-device.log` (test-only markers, no private
  prompts). No PR has been submitted for this WIP, and the full persistent
  recovery/multi-node objective remains incomplete.

## Fragment callback isolation and Desktop 1.1.17

- Adversarial tests first reproduced five independent failures: a disconnect
  callback blocked behind fragment publication, early PUBACKs were lost, a
  negative fragment ACK could complete the logical message successfully, a
  different MQTT client could acknowledge the same numeric packet ID, and an
  identical ciphertext for another topic was incorrectly deduplicated.
- Fragment dispatch now reserves bounded capacity under the state lock, calls
  MQTT without that lock, then registers the result only if the transfer and
  connection generation remain current. A nonblocking single-pump owner avoids
  callback/publisher lock inversion. Transfers rotate when reserving slots.
- Fragment ACK lookup and deduplication include MQTT client and connection
  generation; deduplication also includes the destination topic. Early ACKs are
  bounded. Any negative ACK keeps the whole logical transfer retryable, never
  successfully published. Clearing an old generation cannot restore its state
  after a delayed publish returns or erase newly queued generation work.
- Existing limits remain eight physical fragment packets in flight and four
  per transfer. Added limits are 64 buffered transfers and 32 MiB of encoded
  packets; overflow is retryable backpressure, not deletion of the durable
  outbox. This does not change the per-packet MQTT capacity. Capability metadata
  now reports the encoder's actual constants instead of obsolete 48/32 KiB
  literals, and includes the buffer limits.
- Fifteen new fragment tests include 20 concurrent publishers (60 fragments),
  negative and early ACKs, reset/generation races, cross-client packet IDs,
  count/byte caps and an 800,000-character synthetic Signal-wire body passed
  through the real outer encryption, fragmentation and reassembly functions.
  The inner Signal body is a fixture, not a real libsignal ciphertext; this is
  a local transport test, not an additional phone/model acceptance result.
- 133 transport/scheduler tests plus six subtests passed; eight connector
  presence tests plus two subtests passed separately. Desktop's 29 JS checks
  and root repository checks passed. Evidence:
  `build/fair-pool-fragment-callback-tests.log`,
  `build/fair-pool-fragment-check.log`.
- Desktop 1.1.17 was deployed after checking zero active/pending model tasks.
  S20U's real sequential text/image test passed in 34.654 seconds: text
  14,820 ms; image 17,477 ms; unique markers, full task identities, generation 1
  and image arithmetic all matched. Evidence: `build/s20u-fragment-callback-live.log`.
  This tiny image fixture does not exercise a large Desktop-to-phone fragmented
  response; that real-device path remains to be exercised explicitly.
- Android production code and installed version remain 1.1.6 (892). No phone
  data/pairing was reset; no other phone was operated. No PR yet. Complete
  queued request recovery, atomic execution-generation fences, sustained
  multi-App isolation and multi-node ownership/failover are still open.

## Durable queued request recovery and Desktop 1.1.18

- Core remote Codex and generic Agent admission now persists a versioned,
  bounded private request snapshot in the same task/Run transaction. It retains
  transfer descriptors or allowed inline attachment bytes, selected model and
  reasoning options, language, execution mode and normalized budget. It excludes
  endpoint identity overrides, API keys, raw security grants and arbitrary local
  paths. Canonical App/conversation/turn/task identity comes from the task record.
- Snapshot data is absent from task public projections, recovery notifications
  and Run events. The internal recovery getter returns a detached copy. Tests
  verify rollback on a failed commit, mutation isolation, size/count limits,
  repeated restarts without consuming an unstarted task's retry budget, and
  no private snapshot data in public task or event output.
- A previously queued core request is readmitted to the bounded pool and starts
  normally after restoration; an already-dispatched Codex request still calls
  `recover_task` with its existing provider thread/turn and original model.
  This dispatch decision is captured before the new generation's dispatch
  marker is committed. Generic unstarted core requests are likewise readmitted
  instead of failing because a provider Run does not exist yet.
- Nine new snapshot tests and existing lifecycle/recovery tests passed:
  76 tests plus seven subtests in the broader run. These include a real task
  manager and temporary task database with a fake provider, restoring an image
  and a non-default model. They do not substitute for the device test below.
- `GALAXYSSI_MAX_PARALLEL_TASKS` now configures the actual default worker pool
  (default 10); `GALAXYSSI_MAX_PENDING_TASKS` controls its bounded queue (default
  10,000). Constructor bounds remain enforced. Capability metadata's default
  task count now matches the default pool.

### Real restart experiment on S20U

- Deployed Desktop 1.1.18 and temporarily selected one regular worker. The
  test sent two image requests from S20U. Before closing Desktop, API evidence
  showed only the two synthetic test tasks active:
  `delivery-probe-d60dda3e-2cf5-4aac-9812-bc2f60e7b666-task` running, generation 1;
  `delivery-probe-6492c6de-b860-4239-bfeb-efb1dc3210f0-task` queued, generation 1,
  `started_at=0`. No non-test task was interrupted.
- Closed Desktop normally, verified its backend port was released, then
  restarted the same build with the default ten workers. The phone, pairing,
  identity and chat stores were not reset.
- Both image tasks returned correct arithmetic and their unique markers at
  generation 2: running task 57,941 ms, queued task 58,643 ms, including the
  shutdown/startup interval. The queued task kept attempt 1; the previously
  dispatched task became attempt 2. Read-only task database inspection verified
  both snapshots still contained model `gpt-5.6-sol` and one transfer descriptor.
- Each stream then sent a new text request; both returned at generation 1 in
  10,458 and 10,739 ms. All four requests passed their complete identity checks.
  The instrumentation additionally required at least one generation-2 result;
  it passed in 71.837 seconds. The regular pool returned to zero active/pending
  work with `max_workers=10`.
- Evidence: `build/s20u-queued-image-restart-live.log`,
  `build/s20u-queued-image-restart-device.log`,
  `build/s20u-recovery-test-build.log`,
  `build/fair-pool-request-recovery-check.log`,
  `build/fair-pool-request-recovery-desktop-check.log`.

### Remaining scope

- This proves one controlled normal Desktop restart for two synthetic image
  tasks, not repeated power-loss safety or exactly-once external tool effects.
- Specialized admission branches (such as queued local clarification jobs),
  extended attachment retention beyond transfer cleanup TTL, stale callback
  mutation fencing, same-conversation multi-turn interference and multi-App
  collision scenarios still need explicit coverage and any required fixes.
- Multi-node leases, ownership fencing and failover remain unimplemented.
  The current implementation is a single-node pool, not 10,000 simultaneous
  model processes. No PR yet; the full goal remains active.

## Execution-bound mutations and upstream synchronization

- Fetched `origin/main` without a proxy and fast-forwarded this worktree from
  `8fcebbd58` to `1ee7c9381`, including PRs 2911, 2912 and 2913. Existing
  uncommitted changes were preserved, with no merge conflicts.
- State updates, visible events, partial output, trace appends and trace merges
  now accept an immutable full execution key. The manager checks App,
  conversation, client turn, task and generation under its mutation lock.
  Thirteen Codex callback/recovery mutation sites use the bound key rather
  than relying only on their entry-time generation check.
- Notification snapshots are detached under the manager lock; guarded writers
  recheck their generation before snapshotting. An old terminal notification
  cannot remove the new generation's task listener. Canonical event identity
  cannot be overridden by provider metadata and survives metadata truncation.
- Added nine mutation tests, including deterministic delayed-writer races and
  all five identity dimensions against six mutation calls (including empty
  partial output). Focused suite: 47 tests and 37 subtests passed. Additional
  transport/lifecycle suite: 83 tests and seven subtests passed. `git diff
  --check` passed. These are local tests, not a new real-device acceptance run.
- S20U was reinstalled with the existing Android 1.1.6 (892) APK using `adb
  install -r`, then launched successfully. Identity, pairing and chat storage
  were not cleared. The newly fetched Android source has not been rebuilt or
  installed. The running Desktop has not been replaced with these latest edits.
- Remaining: guard external side effects and result publication against stale
  callbacks, bind generic provider and trace callbacks, verify sustained
  multi-App/multi-turn behavior, implement multi-node ownership/leases/failover,
  and perform updated deployment and real-chain validation before claiming
  those requirements complete. No new PR has been submitted yet.

## Detached execution snapshots and Desktop 1.1.19

- Added lock-protected execution snapshot/current-key APIs. Codex final-result
  and telemetry callbacks read the snapshot for their immutable key instead
  of rereading a mutable task that may have resumed at another generation.
  Codex progress/result publication rejects a different execution identity;
  trace writes carry the bound key and reject stale callbacks.
- Generic runner terminal emission, `_set_status` and `_finish` retain the
  execution identity captured under the mutation lock. The event dispatcher
  rejects snapshots whose canonical identity no longer matches the task.
  Four additional tests cover detached reads, publication identity, stale
  listener delivery and a generation change between completion and emission.
- Focused lifecycle and MQTT callback tests: 70 tests and 41 subtests passed.
  Expanded `test_agent_task*.py` plus mutation suite: 215 tests and 146 subtests
  passed. Desktop checks: 29 Node tests passed; structure and root repository
  checks passed. These suites overlap and must not be added as unique coverage.
- Verified regular/control queues had zero active or pending work, closed the
  known Desktop instance normally and launched version 1.1.19 (root PID 16708).
  Health showed MQTT TLS connected, all ten subscriptions ready and the Signal
  sidecar ready. No user task, pairing or chat data was reset.
- The first Android build exhausted its configured 2 GiB heap. The confirmed
  build daemon for this worktree was stopped and that command returned failure.
  Retried with a command-local 4 GiB heap, two Gradle workers and a single-use
  daemon; project settings and other build daemons were not changed.
- Strengthened the device image assertion: a reply must contain the complete
  equation `2 + 2 = 4`, not just a `4` that could appear in the request marker.
  Updated device validation results will be recorded after installation.

### S20U concurrent multi-turn acceptance

- The 4 GiB build completed successfully in 12m20s. Installed Android 1.1.11
  (897) and its instrumentation APK on S20U only with `adb install -r`.
  Verified installed versionCode/versionName and launched the App after testing.
- Added opt-in `live_delivery_reuse_conversation=true`. With concurrency 2,
  each stream used one private conversation for a text turn followed by an
  image turn. All four tasks/turns were distinct. Both streams reused their
  own conversation ID; neither used the other stream's conversation.
- Real App -> MQTT -> Desktop 1.1.19 -> configured Codex -> App results:
  text 14,368 ms and 18,339 ms; image 16,551 ms and 13,915 ms. All four replies
  passed source/contact/conversation/turn/task matching, generation 1, unique
  marker, terminal success and the complete image equation assertion.
  Instrumentation reported `OK (1 test)` in 34.732 seconds.
- Sampled two active workers while both image tasks were running. After the
  test, regular/control active and pending counts were zero, idle workers had
  exited, MQTT stayed connected and all ten subscriptions were ready.
- Evidence: `build/s20u-execution-fence-android-build-4g.log`,
  `build/s20u-execution-fence-multiturn-live.log`,
  `build/s20u-execution-fence-multiturn-device.log`,
  `build/s20u-execution-fence-task-regressions.log`,
  `build/s20u-execution-fence-desktop-check.log` and
  `build/s20u-execution-fence-repo-check.log`.
- This validates two interleaved conversations with two sequential turns each
  on one real App. It does not prove simultaneous turns within one conversation,
  two independent physical Apps, sustained ten-provider saturation or multi-node
  recovery. Those requirements and remaining side-effect fences stay open.
- Refetched and rechecked `origin/main` after the device run. PR 2914 had
  advanced it to `fa6bffafa`; fast-forwarded that Android native-effect recovery
  change before submission. The device results above are specifically Android
  1.1.11 built at `1ee7c9381`, not a claim that PR 2914 was device-tested here.
