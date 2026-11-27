# Android #4618: measured turn timing and model provenance

Android merge: 4d24af48643352ea03c5603f4f1b160afbeacc85.
iOS base: 60529d22ae941e0ef20a27c8c4b386fc681fc13a (main).

## User surface

The existing elapsed-time footer becomes an accessible receipt button. A scoped
sheet separates phone send, Desktop-reported MQTT receive, visible-body observation
on this phone, terminal reply receipt on this phone and task completion. Desktop
wall timestamps are display-only: first-visible elapsed uses only the local
process's monotonic send/visibility anchors. No clock is reconstructed on restart
or after privacy clearing. Missing observations remain unknown, not zero latency.

Visibility is not recorded from onAppear or network delivery. A transparent native
probe requires a drawn body, a subsequent display interval with intersecting
visible/clipped geometry, the active key window/scene and exact current owner and
conversation. It stops after its one-shot observation and is dismantled with the
view. User/system rows, failed notices, planning control payloads and citation
previews are excluded. This is a 30-Hz UIKit draw/display observation, not measured
pixel presentation or a sub-frame latency claim. Actual device/UI behavior remains
unvalidated. Existing diagnostic telemetry and composer behavior are not replaced.

## Durable observations

Receipt rows use the existing encrypted UserDefaults facility with a shared key
material account, separate authenticated hashed owner/conversation/turn row keys,
16-KiB row limits and no full-row scans on the receive path. A lock serializes
small per-row updates. Only bounded identifier fields, booleans and timestamps
are saved: no messages, prompts, tool arguments/results, endpoint/credential
fields or provider reasoning. The live monotonic map is process-local and bounded
to 256 turns. Cipher failures have no plaintext fallback and do not change chat
execution results. Conversation deletion removes rows with an encrypted tombstone;
late callbacks do not create new rows. Full reset removes rows and shared key
material; privacy clearing invalidates live clocks and dismisses receipt UI.

Selection at send, Desktop wire request, Desktop-reported provider submission,
direct cloud request, cloud response-reported model/effort, observed local runtime
profile and operation device have independent fields. A Desktop submission is
never relabeled as the provider's actual model. Unreported actual model/effort
remains unknown. Provider IDs are not inferred from endpoints or response prose.

Signal-authenticated, registered-task payloads carry exact conversation/turn/task
binding. Provider progress must match provider:<task>:<attempt-1> and the current
execution generation. Bounded terminal turn_receipt replay is used only for the
same generation. Older generations/attempts or another outbound task cannot replace
the current submission. Starting another cloud attempt clears older response
identity; late responses cannot overwrite the newer attempt. No added polling,
provider calls, terminal replay bodies or Desktop code changes are introduced.

Cloud streaming observations wrap and forward the original request/events/cancel
path; compatibility/native-tool JSON paths read only explicit model/modelVersion
and reasoning_effort response fields. Stream effort stays unknown when the
existing stream protocol does not expose it. Legacy structured fallback/format
repair resets prior actual identity rather than reusing an earlier response's
model. Local planner, ordinary local reply and managed-browser completion paths
use returned runtime profile IDs, not configured labels. Internal/injected or
legacy paths that do not report an identity remain unknown, not guessed.

Operation devices are recorded only from successful, non-replayed, matching native
tool/receipt/invocation provenance. The registry authority, effect journal, audit,
permission and result verification code is retained exactly except for a post-
result optional observer. Merely selecting a phone/Desktop route is not evidence
that a tool executed there. The UI is a snapshot opened by the elapsed label,
not a new diagnostics feed or planner/tool-chatter viewer.

## Verification boundaries

Eleven synthetic Swift methods are authored for monotonic/one-shot visibility,
restart/privacy invalidation, encrypted scoped persistence, identifier bounds,
Desktop generation/task/event/attempt checks and terminal replay, cloud attempt
ownership, deletion/late callbacks, verified device provenance and body eligibility.
They are not compiled or executed. Source checks inspect actual call sites and
unchanged encryption/transport/authority implementations; they do not validate
native rendering, clocks, concurrency, provider adherence or cryptography at run time.

No Swift/native build, XCTest, device/live provider/network acceptance, measured
latency, CI monitoring, full repository check or IPA. No raw reports, screenshots,
private evidence or secrets are uploaded. iOS 15 and Android/Desktop code/versions
are unchanged. This does not complete the remaining Android-to-iOS backlog.
