# Android Conversation Windows

## Contract

- The external-link control immediately precedes the existing conversation/model header.
- Independent documents subclass MainActivity and use its original layout, colors, transcript renderer, model selector, contact list and composer.
- A new document has a stable random window key and a unique Intent data URI. Android Recents owns its card and preview. The manifest permits up to 32 recent documents; ten are the acceptance target.
- Opening a conversation already represented by a document focuses that task. The source becomes a fresh conversation only after the destination is ready.
- Every window has independent selection, text/file draft, transcript anchor and auto-follow state in encrypted local storage. The shared transcript and model settings remain keyed by conversation ID.
- Restoring a document prioritizes its last selection over its original launch Intent. Legacy main-page selection and draft are migrated once.
- Transcript changes are coalesced; only visible windows refresh. A visible conversation list refreshes its loaded range while retaining its scroll anchor.
- Window-created empty conversations are protected from legacy empty-conversation pruning.

## Task Ownership

AgentTaskRuntime remains the process-level task owner. Window teardown does not cancel its supervisor. Task persistence uses a process-level executor, and terminal state can be persisted after the Activity is destroyed. Existing MessageService and pending-delivery recovery continue handling remote results. Closing a window is not the pause or cancel command; existing task controls retain those responsibilities.

Android may stop the process under memory pressure, force-stop or device shutdown. This feature does not promise uninterrupted computation through those events. Existing durable checkpoints and remote result recovery are reused; ten windows do not override adaptive execution concurrency or remote-provider limits. Running and queued work are distinct.

## Verification

Device scope: SM-T575, serial R52R90282TY only. Debug package 1.1.3 (889). No application data reset is required.

Unit suites:

- AgentTaskSupervisorTest: 21 cases.
- AgentTranscriptStoreConcurrencyTest: 3 cases.
- AgentTranscriptWindowTest: 3 cases.

Instrumented suite: AgentConversationWindowsInstrumentedTest.

- Independent and durable window selections and drafts; shared rename.
- Ten real document windows plus an originating window; source reset, draft handoff, document reuse, shared list refresh and ten bounded background supervisor jobs completing after window closure.
- Recreation restores the latest selection and unsent draft despite a stale original launch conversation.
- Optional live model test (`run_live=true`): submit through the actual composer, close its document, require the result in the durable inbox/transcript, then reopen the document and require the assistant reply in its rendered transcript data.

The bounded supervisor jobs are lifecycle tests, not ten live LLM requests or an Agent quality benchmark. The optional live test is reported separately.

Build/device logs and screenshots are written under the worktree's ignored build directory. Screenshots produced by instrumentation are also under the app external-files window-test directory.

## First Iterations

- The initial document test missed the second Activity because Instrumentation removes a monitor after a wait. A fresh monitor is now registered per launch.
- Visible-row text assertions cannot detect a renamed RecyclerView item outside the viewport. The shared-list assertion now examines the actual adapter data, preserving the user's scroll instead of forcing a jump.
- Rapid handoff exposed startup animation snapshots in Recents. Independent documents now release their startup overlay when hydrated and draw before acknowledging the handoff. Normal main-page startup animation is unchanged.

## Final Outcomes

- 27 targeted unit cases passed. Build, whitespace and Kotlin source-size checks passed.
- Latest application artifact: 1.1.3 (889), installed with `adb install -r` on SM-T575, retaining existing data.
- Device lifecycle suite: three tests passed in 34.718 seconds; the opt-in live test was skipped in that run. All eleven real Activity tasks existed together. All ten bounded supervisor jobs completed after the target window was closed. Draft handoff, source reset, document reuse, shared RecyclerView adapter refresh and stale-Intent recreation assertions passed.
- PSS at eleven Activity tasks: 454,283 KiB (about 444 MiB), for the entire app process in this synthetic scenario. This is not per-window memory or a long-running model stress result.
- Separate opt-in Codex test passed in 24.995 seconds. The composer dispatched through the configured `connector-codex` MQTT route; the Activity was destroyed while its task was active, the result persisted, and reopening displayed the exact expected nonce reply.
- Final screenshots: `build/ten-windows-current.png`, `build/ten-windows-recents.png`, `build/live-reply-restored.png`. Independent document previews no longer show CONNECTING.
- An earlier live assertion incorrectly required immediate transcript projection with no Activity alive. Existing MessageService persists remote responses into the durable response inbox first; the final test verifies both durable arrival while closed and visible transcript projection after reopening. The failed attempt remains in `build/conversation-windows-live-test.log`.
- Signal envelope decryption errors were observed during both live attempts, followed by successful decrypted packets. They were not bypassed or fixed by this change. The final live reply succeeded; transport reliability remains a separate follow-up risk.

Residual coverage: this verifies ten real windows with bounded supervisor work and one real Codex request, not ten simultaneous LLM completions. Power loss, prolonged Doze, large attachment drafts and extremely deep transcript anchors were not stress-tested in this feature run. Android's Recents image is a last-frame snapshot, not a live task-progress view.
