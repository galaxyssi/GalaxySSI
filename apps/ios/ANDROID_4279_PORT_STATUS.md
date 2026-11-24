# Android #4279 iOS Port

Android merge: `7e2e3916b2aec82709091ba3ca70eca0c0dc1a8b`.
Incremental predecessor: iOS #4529, `990bef6fd10a892dae236b58937d2f6f27cf3183`.
This main-targeted branch is cumulative; its complete main diff is not an independent #4279 delta.

## Implementation

- Add backward-compatible schedule_origin metadata. Explicit editor/model-tool saves identify their source; missing or unknown origins are not execution authorization.
- Page the exact conversation's native receipt history in batches of 50, beyond current UI caches. Require native trace/task binding, editor/tool receipt ID and current task name/schedule label. Do not trust legacy schedule-command receipts. iOS legacy receipts are native plain-text receipts, not Android rich cards; the matching adaptation is explicit.
- Persist unverifiable schedules disabled, next run zero and review required. Cancel nonterminal occurrences while retaining their prior result text. Repeated reconciliation does not advance revision again. Native local-task cancellation is requested separately by the coordinator; it cannot undo an action already performed by a remote device.
- Reconcile before startup/recovery, list/editor operations, due claims, run start/finish, direct trigger and foreground/background execution. Keep user-turn/revision checks. Alternate background handling delegates conversation work to the scoped coordinator instead of dispatching it through a generic chat path.
- Legacy resume in the UI opens the task/time editor. Model-tool metadata exposes requires_confirmation and instructs the model to require explicit recurring-execution confirmation. This does not add a lexical intent parser or infer consent from ordinary questions.
- After durable pause, store exact conversation/old-turn reply blocks transactionally. Canonicalize UUID case. Block new late rows and payload replacement at shared SQLite writes, transport admission, callbacks and alerts. Existing rows remain readable; identical-body read-status/trace updates are allowed. Blocks survive later review/resume, so old occurrences are not replayed.
- Migration never deletes/rewrites transcript bodies, attachments, timestamps or unread tokens. Only typed scheduled-result list previews remove the historical label, using an ephemeral copy; ordinary/iOS unlabelled replies remain unchanged. Transcript and model-context reads are unchanged.
- List/prewarm cache keys include review state and old-run bindings, so a migration or later review cannot leave stale projected labels in a prepared list. A surviving native occurrence source also suppresses orphaned replies after its run row is pruned.
- Import the exact English/Chinese legacy-review message. No Android/Desktop changes, iOS version bump or IPA.

## Evidence And Limits

Thirteen changed Android files are individually pinned/mapped. Source/resource contracts verify lifecycle gates and freeze read paging/unread indexes, existing workflow scheduling, Health and unrelated session code. Native migration, paged receipt, legacy codec, durable DB reopen/rollback, read-status and message-preservation fixture sources were added but are not executed evidence.

Windows has no Xcode. No Swift type checking, XCTest, real database migration/reopen/fault injection, message/attachment fingerprint comparison, dispatch/recovery/cancellation timing, notification/voice/UI or real-device acceptance is claimed. The Swift grammar parser also reports existing whole-file errors in GalaxySSIServices.swift and GalaxySSIStoreTests.swift at the baseline; counts and small-error-node signatures remain unchanged. Grammar checks do not establish compilation.
