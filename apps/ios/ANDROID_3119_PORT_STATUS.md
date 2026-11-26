# Android #3119 Routing Admission

Android merge: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`.
Incremental predecessor: iOS #4533, `ddcb2a69acd02ea12d20fb469e779d4d87b85a4f`.
This branch targets main and includes unmerged predecessors. Its full-main diff is not this independent increment.

## Implemented Boundary

When a routing decision exists, intersect connector targets with its exact primary/fallback target IDs before availability filtering, heartbeat recovery, preferred-target lookup, quality calibration or baseline fallback. Catalog-only resources are informational, not admitted candidates. An explicit preference cannot override this boundary. No admitted reasoning target means nil, not a fabricated catalog candidate.

When no decision is provided, existing capability/default/recovery behavior stays unchanged. Explicit admitted preferences, device rejection, required capabilities, no-route decisions and recoverable heartbeat logic remain in place. This patch does not generate new privacy/budget/capacity decisions or assert that existing decisions cover every policy.

Native regression fixture source covers excluded preferred/catalog targets, an unavailable admitted primary, admitted recovering versus excluded healthy targets, and tool-only decisions. Existing admitted-preference and phone-tool-with-connector-fallback fixtures remain unchanged. Neither old nor new native fixtures are executed on Windows.

## Scoped Auto Identity And Primary Dispatch

Add optional backward-compatible target/turn state to the existing encrypted native conversation payload. No separate plaintext preference store or display-label-to-ID inference. Preserve conversation timestamps and the unpromoted draft state. Only cache/publish after the database write succeeds. Session removal and encrypted persistence retain their normal ownership boundaries.

Begin binds a Hermes user turn to its exact conversation. Older replay turns cannot replace a newer turn. Dispatch updates require the bound turn and automatic selection; manual updates, missing scopes, archived/merged sessions and unavailable sentinel IDs are rejected. This metadata does not grant provider or transport authorization.

The primary local/cloud/Agent dispatch chain captures one automatic target ID rather than re-ranking independently in each branch. Before the selected branch proceeds, commit its exact ID for the current turn or fail. A healthy eligible remembered primary returns without alternate quality ranking; unavailable or capability-ineligible primaries follow the existing selector. Header reads the same exact target identity and no longer invents Codex or adopts a stale live/session display label. Manual presentation and configuration remain unchanged.

New native fixture sources cover encrypted reopen, conversation isolation, stale turn/replay rejection, manual protection, legacy decoding, exact Auto header identity and healthy-primary selection. These sources are not executed. Source guards do not establish persistence fault behavior or actual routing acceptance.

## Synchronous Connector Fallback

The actual native/control-plane executor result paths now carry the owned fallback trail and Auto-reroute metadata; manual locks and explicit false flags dominate. On synchronous known failure, recompute the current route order, ignore the remembered candidate order, retain attempted/retried/deferred history, and prepare the next action through the existing owned-trail helper. Preserve exact task/conversation/turn scope and target-specific effect-attempt identities. Do not reset the durable effect journal or action ID.

Reject mismatched action results, waiting responses, unknown effect/node outcomes, conflicts, manual/team routes and unobserved remote timeout outcomes. Removed/excluded deferred candidates cannot be resurrected. Existing failure-domain limits apply to fresh/deferred/retry candidates. Before/after synchronous connector dispatch, record the actual action/result target into the current encrypted Auto binding; old turns cannot overwrite it. Legacy display labels use the executed fallback action rather than the original failed action.

New regression fixture sources cover fresh ordering, no resurrection/repeated targets, scope/model-field handling, target-specific attempt identity and locked/uncertain outcomes. They are not executed. The timeout resolver and durable effect executor kernels are unchanged; this is not a new active remote-observation implementation.

## Attachment Submission And Parallel Preparation

Composer captures the submitting owner/contact/conversation before starting asynchronous work and passes the existing required-conversation guard to send. If navigation happens before send starts, reject rather than sending the captured attachment into another session. After completion, only the current foreground/unlocked owner, conversation and composer request may restore an empty draft or merge its captured attachments. Session/plaintext reset and new voice capture invalidate old composer callbacks. Only consumed attachment IDs are removed from voice-pending input; newer voice snapshots are not cleared by old failures. This does not introduce persistent per-conversation composer drafts: abandoned pre-send input is not restored into another conversation.

Synchronous and parallel connector preparation refresh eligible automatic routes before appending task/session/conversation/turn metadata. Refresh starts from the existing action and preserves custom/prompt/scope parameters. Manual locks, explicit Auto-disabled actions, team specs and owned active fallback trails are not rerouted. Missing routes use the existing unavailable sentinel rather than the stale target. The common scoped builder appends metadata to the refreshed action, not the original dictionary. Parallel accepted/successful results may update only their current encrypted Auto binding. Native checkpoint/effect ownership remains unchanged; this is preparation-time routing, not executed parallel/device acceptance.

New native fixture sources cover exact owner/conversation/request scope and refreshed parameter/manual/team preservation. They are not executed. Pure scope tests do not simulate SwiftUI task scheduling, gestures, privacy transitions, real attachment bytes or concurrent provider dispatch.

## Existing Desktop Asynchronous Recovery

The real Desktop reply-recovery sweep already queries the original owned task independently of a stored fallback list. In that existing path, authenticated confirmed failures now recompute alternative rankings from current callable targets restricted to the existing paired/verified same-Desktop contacts. The original Codex retry budget, timeout recognition, attempt identity, invocation validation and disclosure gate remain unchanged. This does not add cross-Desktop/cloud replay or fabricate a timeout from silence.

Queued/sent recovery attempts and locally committed accepted replies can update Auto only through a current owned source, exact conversation/turn and trusted paired route/Agent binding. Manual, team, managed child and goal-work records do not enter this metadata update. An old turn cannot replace a newer Auto binding. Recovery success/delivery is not inferred from that metadata write.

Fixture sources cover eligible alternative containment, no duplicates and the original budget consuming current ordered alternatives. Existing manual-recovery/source contracts verify the budget and receipt/timeout/authentication kernels remain exact. No fixtures or live recovery are executed.

## Scheduled Conversation Dispatch Follow-up

The existing conversation scheduler now commits its exact outgoing Auto turn before selecting a provider. A stale turn or failed encrypted binding stops dispatch through the existing failed-run path. Local, cloud and Agent branches consume one captured target ID, including an explicit empty ID when no target exists; they cannot independently re-rank or re-enable the legacy local-provider override. Selected provider identity is recorded before execution, with the paired-phone snapshot and Desktop disclosure checks retained. A rejected dispatch metadata write follows the existing disclosure failure path. Deterministic phone tools do not fabricate a model dispatch.

Existing schedule provenance/revision, private/paused/collaboration restrictions, plan-only rejection, occurrence identity, duplicate suppression and result reconciliation remain unchanged. Generic connector continuation is separate and remains incomplete. Schedule assertions are source contracts only; no scheduler/provider/device acceptance was run.

## Live Admission Before Stable Selection

Primary Auto selection, synchronous/parallel route preparation, fresh synchronous fallback and the existing same-Desktop alternative replay rankings now filter the actual target catalog through exact-ID registrations with the existing live global-run-slot counts. Full registrations, unavailable endpoints and missing mandatory registered capabilities cannot win via remembered preference. Local-only and restricted-data boundaries apply before stable selection; another installation's similarly named registration cannot lend trust or capacity. The original replay budget's same-target attempts remain unchanged; this does not claim new admission of those attempts or alter their existing publication gates.

The same preselection path reuses the existing task budget and network detector: explicit cloud/paid-provider, trusted/offline/unmetered network policies and disabled connector calls are enforced. Phone resources remain possible without a network. The current budget implementation deliberately treats token/cost/memory/battery counters as telemetry, so this patch does not restore old Android hard cutoffs. Manual paths, disclosure authorization, actual slot acquisition and transport publication remain separate and unchanged. Registration projection consumes the same catalog snapshot. The preferred ID remains the actual remembered ID even when admission excludes it; only an admitted healthy preferred primary skips ranking, rather than prematurely treating the default replacement as a new stable primary.

This is live admission, not the full Android score/circuit-health/failure-domain router. Global slot counts only cover runs tracked by the existing slot owner; this does not claim every direct model/Agent call is accounted for or reserve a slot atomically at selection. Existing disconnected-heartbeat recovery is retained when there is no contradictory registration. The header still reflects the remembered identity until a real dispatch commits a replacement. Native fixture source covers capacity, exact-ID registration, privacy, mandatory capability and explicit provider/network restrictions, but has not been executed.

## Native Queued Connector Continuation

The native serial finish path now saves the actual queued connector receipt and source-message UUID on the existing encrypted plan node, marks the action/task waiting and returns before completion, result publication or next-action/model continuation. The task snapshot uses the existing guarded save/rollback implementation through a general name; browser callers retain their original wrapper and unchanged transaction body. A malformed/unowned or unpersistable wait blocks advancement. Queue receipts project running calls with no completion timestamp or successful output, not tool success.

The host listens to the existing post-commit managed-response bus and also checks on home refresh/foreground delivery recovery. It reloads the exact encrypted owner record, accepts only its committed terminal response with matching owner/Agent/source/contact/conversation/turn/task/generation, stages that terminal result in the task snapshot, then invokes ordinary finalization. A response that arrived before wait-state save can be found by the post-save wake. Already-applied managed owners remain usable because the durable response is retained. This is not a raw wire listener or a new authentication bypass. Paused tasks require the existing resume path; cancellation, foreground/protected-data, execution/permission and session gates prevent automatic continuation.

Before refreshing any serial connector route, observe the original effect claim, including a claimed-but-unsettled effect. Existing/unknown dispatches do not become fresh targets. Actual initial and fallback execution parameters are checkpointed before invoking the delegate, so a restarted plan retains its original effect identity. The effect executor's claim/dispatch/commit implementation and immutable node journal remain unchanged; only its read-only observation method now exposes an unfinished claim through the original unknown-outcome result. Unknown/non-retriable/corrupt-receipt outcomes explicitly block fresh fallback. The previous tracking-failure follow-up's boolean unknown flags are now checked as well as error codes.

The producer follow-up below wires supported generic requests. Exact committed terminal failures can now enter the guarded fallback transition described below; active timeout observation remains incomplete. Serial connectors are not made into parallel native batches; the preexisting batch policy already rejects non-native multi-action batches. Terminal staging is durable, but the existing final UI/history/projection saves are not a new atomic multi-store workflow. Original journals are not rewritten to claim terminal evidence; that evidence remains in the managed-response ledger. Native source fixtures cover codec/scope/owner/generation containment, queue-versus-completion projection and explicit no-reroute flags. They are NOT executed; restart, network, parallel and device acceptance remain unverified.

## Queued Connector Producer

Install a real queued delegate in the app's native runtime. Preparation is pure and generates a stable 52-bit numeric source plus UUID remote task from scope, owned effect attempt and profile fingerprint. The transport invokes the producer only after durable managed-owner registration, live interception and the waiting event. The main-actor producer then requires the already saved exact waiting node, original durable source UUID, current profile/permission snapshot, active session and current execution/privacy/budget policy before any external call. Host-added execution policy is retained; only that known provider-added field is excluded when comparing the prepared action with the saved action. The provider uses the same managed ledger as the coordinator.

Supported backends now invoke the exact ready local profile, the existing cloud stream engine, or the existing authenticated paired Desktop outbox. Cloud image bytes are restored with exact IDs from the originating turn; stream completion is required rather than accepting partial text on disconnect. Paired requests require one verified paired route, saved task identity, disclosure permission and supported explicit model/effort. No model-ID normalization may silently replace an explicit retired selection. These are actual calls/enqueue paths, not a capability-only registry or placeholder result.

Current limits are explicit: local inference requires extracted text, cloud accepts text/images and no non-default effort override, and the numeric managed paired path is text-only. Unsupported raw files/audio/video or paired attachments fail before sending, rather than pretending their bytes were delivered. Broader attachment/context/typed rich-output parity is NOT complete. Local selected-profile calls use the existing native generation cap; this does not establish Android's full long-output/cooperative model behavior.

One producer kickoff per owner is allowed in the running coordinator. A request is not blindly sent again after process restart; original effect/managed-owner recovery remains passive. Errors after an attempted backend call save unknown/non-retriable evidence and block the task, retaining the original pending owner/slot; they do NOT fabricate a terminal remote failure. A failed unknown-state commit leaves the request unresolved. An actual committed late completed-success response can resolve the local uncertainty; failed/cancelled observations cannot erase the unknown-effect warning. Known preflight failures do not assert an external effect. Unknown evidence is retained when a cached queue receipt is restored. A completed local/cloud response or known preflight failure is staged in a profile-scoped encrypted response store, then committed to the managed ledger before slot release/removal of the staged copy. Foreground/home recovery retries committed-response delivery, not external work. An initial staging write failure is surfaced without claiming delivery; no storage-fault recovery guarantee is made when neither journal can write. Local/cloud interrupted jobs do not yet have a remote status-query equivalent and may require explicit outcome reconciliation; no automatic failover/restart execution is claimed.

New source fixtures verify pure stable identity/profile separation, exact prompt/source preservation across host-policy preparation, one kickoff after registered ownership, no kickoff on ledger failure and no duplicate start through adapter replay. They do not execute the main-actor producer, network, local inference, SQLite fault/restart workflow, cloud tools, MQTT or device UI. Source/project/grammar checks cannot substitute for those acceptance tests.

## Known-terminal Asynchronous Failure

After exact owned terminal response staging, only failed/timed_out responses with Auto still selected may request a fresh eligible fallback. Cancelled, delivery-failure, manual/team, Supervisor-stop and unknown/non-retriable outcomes do not qualify. Existing fresh-ranking, trail, failure-domain and remote-observation gates remain authoritative. Save the failed attempt in bounded plan history, replace its plan node, validate the plan and commit the pending fallback before calling the normal permission/confirmation/dispatch path. A failed staging commit sends nothing. This is not silence-driven retry or a new active timeout observer.

Control-plane run IDs now use the existing owned effect-attempt key, as remote source/task identities already do. A legitimate same-provider retry therefore cannot collide with its previous managed owner. First-attempt and manual identities remain unchanged; foreign/unowned trails cannot change identity. Wait validation uses the same identity helper. Cached original dispatch reads retain the original response-language parameter rather than rebuilding its identity from current global settings. The new identity fixture is source only, not executed native acceptance.

## Still Incomplete

### Native Managed Observation Deadline

The existing managed Desktop sweep synthesized a failed response when status/result queries expired. That is not proof the original external task failed and could incorrectly trigger native Auto fallback. Exact saved native waits now bypass this synthetic terminal response and retirement. Preserve the pending owner and native wait, record a separate observation-overdue marker through guarded task save, and keep existing rate-limited status/result queries available on legacy and journal transports. A save failure still cannot authorize a synthetic terminal response. Other managed consumers retain their previous behavior.

Query expiry does not set effect-outcome/non-retriable flags or change the task phase. A later authenticated owned terminal failure may therefore enter the normal fallback policy; actual post-dispatch transport uncertainty retains its separate stronger protections. Native fixture source distinguishes overdue observation from an unknown external effect. This reuses existing passive Desktop observation, not a new generic local/cloud timeout observer, replay, protocol or successful network/restart acceptance claim.

### Failed Connector Receipt Tracking

The real control-plane transport no longer ignores errors registering an already dispatched connector's managed response ledger and live interceptor. Validate positive source identity, matching action ID, valid generation and nonblank normalized conversation/turn/task before treating a receipt as waiting. Malformed receipts and tracking failures produce a failed, explicitly unverified/unknown, non-retriable result under the original action ID. Preserve routing/manual/scope metadata and attribute the failure to local transport rather than provider health. Replayed adapter starts see the cached unknown result, not a second delegate call.

Because the delegate may already have sent an external effect, this path does not release its run slot immediately, tombstone its response or remove a successfully saved owner. Existing real-receipt/lease-expiry handling remains responsible for the slot. No claim is made that an invalid/unpersistable remote receipt can be recovered automatically. The native waiting follow-up handles valid owned queued receipts through the scoped producer above; broader timeout/observation connections remain incomplete. Legacy optional contact matching is unchanged in the general resolver; the new native continuation requires exact nonblank contact identity. Failure-injection/malformed/replay fixture sources were added but NOT executed.

### Snapshot-less Outcome Review Recovery

The actual shortcut outcome-review provider path now binds an Auto turn only when no persisted planner snapshot exists. It captures one target for all local/cloud/paired-phone branches, including explicit no-route, and records that target only after a real snapshot passes the existing review-provider privacy/local-only/connector gate. Failure to commit current-turn metadata rejects provider selection. A saved snapshot is retained unchanged and does not rebind or overwrite newer Auto metadata; manual recovery also retains its original selection behavior. Original effect readback, uncertain-effect evidence and continuation ownership are unchanged. Broader resumed planning paths remain unported; these assertions are source-only and do not prove native recovery behavior.

This is NOT completion of Android #3119. At the original checkpoint main service selection started without a full scored privacy/budget/capacity context. The scored-route follow-up below now connects that context to main Auto selection, dispatch refresh and fresh fallback using the existing admission/scoring policies; it does not cover every planner entry point or restore superseded resource-counter limits. The installed queued producer supports the scoped input/backend combinations above, not the full Android generic connector contract. Coordinator's direct model/Agent sending remains separate. The general control-plane timeout helper still lacks a Coordinator caller/candidate-observation source. Those missing timeout/deferred-observation and broader attachment connections require implementation, not just policy tests.

The original Desktop changes above were limited to the existing recovery implementation. The journal Codex follow-up below removes its explicit replay rejection with exact current attempt authorization and original-message receipt projection. Broader asynchronous continuation, active pre-timeout observation/deferred discovery and broader scheduled/resumed provider identity still require integration. Parallel/attachment/native UI, network, process-restart and recovery acceptance are unverified. Older callbacks can still change legacy display labels; they cannot update the new exact Auto binding without its turn.

All 17 Android changed files are pinned with explicit dispositions. Manual selection, planning factory and quality-ranking implementations remain exact. The scoped Auto, admission, host continuation and queued producer changes above are additive to those existing policies. No credential, version, Android, Desktop or IPA changes. Existing network engines/outboxes are reused, not replaced with a new protocol.

## Verification Limits

### Native journal delivery acceptance follow-up

See `ANDROID_3119_NATIVE_DELIVERY_ACCEPTANCE.md`: numeric-source message delivery
completions now reach the exact saved native waiting receipt through an owned
task commit before completion consumption. Replay cannot refresh its acceptance
clock or overwrite newer remote progress. Uncertainty, phase and original result
ownership remain intact. Seven fixture methods are source only; active timeout and
broader callback/native acceptance remain incomplete.

### Phone local-model resource identity follow-up

See `ANDROID_3119_PHONE_LOCAL_MODEL_RESOURCE.md`: the actual reserved iOS local
adapter is now a phone/on-device resource with a bound model/context profile,
instead of a remote-local resource that could demand network access at dispatch.
Ready-state, remote model boundaries, run-slot identity and inference code are
retained. Eight fixture methods are authored only; offline generation is not
claimed executed or accepted.

### Scored main-service route context follow-up

See `ANDROID_3119_SCORED_ROUTE_CONTEXT.md`: main Auto choice, dispatch refresh
and fresh fallback now pass an explicit scored decision with actual admission,
budget/environment, exact registration attributes, health and scoped usage.
Healthy admitted primaries avoid alternative calibration/shadow work; other
candidates remain complete until the existing selector bounds them. Eight
fixture methods are source only; no native routing acceptance is claimed.

### Resumed planner model identity follow-up

See `ANDROID_3119_RESUMED_PLANNER_ROUTE.md`: user-requested native replanning
and rolling continuation no longer fill a missing snapshot from global planner
settings. They retain exact saved snapshots, otherwise reuse the scoped current
conversation selection with Auto admission/binding and manual/privacy gates.
Eight fixture methods are authored only. This does not complete generic routing,
active timeout observation or Android #3119 acceptance.

### Journal Codex recovery follow-up

See `ANDROID_3119_JOURNAL_CODEX_REPLAY.md`: pending bounded Codex attempts can
enqueue through journal transport without legacy-client readiness. The projection
resolves only an exact current replay owner and original plan-only payload; its
delivery receipt maps locally to the original chat row without rewriting journal
identity. Existing confirmed-failure qualification and retry budget are unchanged.
Seven Swift fixtures are source only, not native replay acceptance.

### Owned native rich reply follow-up

See `ANDROID_3119_NATIVE_RICH_REPLIES.md`: the native final-message producer now
retains only exact committed connector rich output and reuses artifact completion
hydration. Agent artifact updates select exact incoming scope rather than a newer
unrelated turn match. Non-team numeric Blob admission checks the existing managed
generation; peer UUID and team authorization paths are retained. Swift fixture
source is authored only; broader parity and native/device acceptance remain open.

### Raw paired connector attachment follow-up

See `ANDROID_3119_MANAGED_RAW_ATTACHMENTS.md`: native paired requests now save
their exact raw attachment intent and reuse journal/Blob/chunk/deferred-body
paths with numeric-source receipt binding. Known file-delivery failures retain
scoped evidence and are not provider outages. Earlier text-only restrictions in
this historical port log describe their original baselines, not this follow-up.
Native/transport/fault/device acceptance and the broader parity work remain open.

### Owned task-status observation follow-up

See `ANDROID_3119_OWNED_STATUS_OBSERVATION.md`: authenticated Desktop recovery
observations now project strictly advancing, exact-owner status into native
waiting receipts on both transports and existing recovery sweeps. Status-only
terminal observations do not authorize completion or fallback. This is not the
missing generic active timeout scheduler or broader attachment implementation.

Source contracts and grammar/project checks do not establish Swift type correctness, executed XCTest or real routed delivery. No Xcode, native/network/device acceptance, ten-conversation test, privacy/budget gate execution or runtime fallback verification is claimed.
