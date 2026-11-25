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

## Still Incomplete

### Snapshot-less Outcome Review Recovery

The actual shortcut outcome-review provider path now binds an Auto turn only when no persisted planner snapshot exists. It captures one target for all local/cloud/paired-phone branches, including explicit no-route, and records that target only after a real snapshot passes the existing review-provider privacy/local-only/connector gate. Failure to commit current-turn metadata rejects provider selection. A saved snapshot is retained unchanged and does not rebind or overwrite newer Auto metadata; manual recovery also retains its original selection behavior. Original effect readback, uncertain-effect evidence and continuation ownership are unchanged. Broader resumed planning paths remain unported; these assertions are source-only and do not prove native recovery behavior.

This is NOT completion of Android #3119. Main service selection still starts without a full scored privacy/budget/capacity decision; this change must not be described as adding that missing policy engine. The local runtime currently delegates general callConnector actions to AgentIOSNativeActionExecutor, whose default branch rejects them; it is not a completed generic transport implementation. Coordinator's direct model/Agent sending is separate. The general control-plane timeout helper also lacks a Coordinator caller/candidate-observation source. These missing connections require implementation, not just policy tests.

The Desktop changes above are deliberately limited to the existing recovery implementation. Journal-backed publishLinkMessage explicitly rejects codexReplay records, so this patch does not claim that a new Codex replay works on journal transport. General asynchronous continuation, active pre-timeout observation/deferred discovery and broader scheduled/resumed provider identity still require integration. Parallel/attachment/native UI, network, process-restart and recovery acceptance are unverified. Older callbacks can still change legacy display labels; they cannot update the new exact Auto binding without its turn.

All 17 Android changed files are pinned with explicit dispositions. Manual selection, planning factory and quality-ranking implementations remain exact; only the primary Auto path/header and encrypted session metadata are extended. No transport, credential, version, Android, Desktop or IPA changes.

## Verification Limits

Source contracts and grammar/project checks do not establish Swift type correctness, executed XCTest or real routed delivery. No Xcode, native/network/device acceptance, ten-conversation test, privacy/budget gate execution or runtime fallback verification is claimed.
