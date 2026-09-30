# Floating Agent Chat

## Reuse Boundary

`ScreenAssistantChatActivity` subclasses `MainActivity`, as the existing independent conversation windows do. It inflates the same `activity_main` layout, uses the same composer views and controllers, and retains `AgentTranscriptRecyclerAdapter` and the main rich-output renderer. Submission, model routing, attachment staging, mentions, microphone/continuous voice, task controls and conversation persistence are not reimplemented.

The floating-only responsibilities are non-modal window sizing, a compact header, collapse/restore, and source acquisition. Tapping the floating button does not submit a task. Send uses the normal main-page submission path. A screen attachment binds read-only analysis to that turn; removing it leaves the usual Agent behavior. The explicit phone-execution menu retains its authorization scope.

The copied `ScreenAssistantPromptActivity`, its standalone dictation controller and its composer policies are deleted. The plain-text result panel is deleted. The accessibility overlay retains the floating button, tool menu, crop selector and full-page capture progress controls. Actual Agent results render only in the real Agent page.

## Window And State

The mini chat is a non-exported, single-task Activity with a separate task affinity and no dim background. Its bounds fit visible system bars and the keyboard. Outside its bounds, the external app remains touchable. Compact and expanded states use the same view tree and conversation; resize does not recreate the Agent.

Collapse saves the normal window draft and moves only this task to the background. It does not invoke task cancellation or finish the Activity. Stop remains a separate explicit operation with conversation/turn validation. Process death has the same recovery semantics and limitations as the existing shared Agent runtime; an Activity window is not a guarantee that Android will keep the process alive indefinitely.

The mini chat cannot become the home Agent selection source. Home routing is inherited through the existing bridge. The normal main page layout and handlers are unchanged, apart from submission notification and content-preparation hooks overridden only by this Activity. The default preparation hook passes the original goal and attachments through unchanged.

## Content Analysis Sources (v1.3.29)

The existing header screen button opens four choices: current screen, entire content, files, and a web link. The page/link selection is a removable source row above the existing composer. Screenshots and files use the existing removable attachment previews. Empty-input voice and text-input send behavior, the shared process/timer display, Stop, expand, collapse and the always-front floating button are preserved.

Selecting entire content does not silently send a request. Sending a question starts the existing page collector on a worker thread, records its progress in the same transcript, and then hands the saved content to the shared model pipeline. Collection returns to the beginning, advances through the page, deduplicates viewport overlap and attempts to restore the original position. Target changes, user interaction and cancellation stop collection. Only one new content capture can own the physical screen at a time.

The new path produces bounded text and PDF attachments rather than an additional base64 HTML copy. It uses a 16 MiB capture budget within the existing 20 MiB per-attachment limit; reaching the budget is partial coverage, not successful full reading. PDF generation checks cancellation between pages. Other callers retain the existing HTML export behavior. Collection errors produce a terminal, actionable reply instead of leaving the pending indicator running; no model request is made on a failed or cancelled preparation.

Internal reading instructions and capture metadata are not the user bubble. The selected question is persisted as submitted, and the hidden execution input carries the document-reading requirements. A source/coverage disclosure can be expanded above the output. Counts are captured screens, never invented chapters. Collection coverage explicitly does not prove the model read or verified every section.

Files use the existing system document picker and attachment pipeline. Web links accept HTTP(S) without embedded credentials and are passed to the existing model web-reading tools; selecting a link is not represented as successful retrieval. Access restrictions and extraction gaps must be disclosed. The entire-page option uses visible scrolling, not an automatic original-URL discovery or a guarantee that collapsed/linked content was acquired. Users can choose the original file or link explicitly.

Source drafts and latest coverage are isolated by conversation. Follow-up questions reuse the last saved capture or link rather than scrolling the current live page again; selecting a different source or attaching a new input supersedes that context. Collapsing the chat does not cancel preparation. Destroying its Activity during preparation cancels and records that interruption; already dispatched model work remains owned by the existing runtime. Preparation is not yet a process-death-resumable collector job.

`ScreenAssistantContentDeviceTest` covers selection/removal and recreation, link handoff and cancellation propagation, default pass-through, cancelled preparation, saved PDF/text handoff and follow-up reuse. The existing keyboard and page-collector device suites remain regression requirements. Compiling these tests is not equivalent to running them or to validating a live provider result; report device acceptance separately.

The final v1.3.29 / 1072 build passed 35 focused unit tests and both APK build targets. It was installed with `adb install -r` on S26U (SM-S9480), without clearing App data. All seven content-source device tests and four shared-composer/real-keyboard tests passed on that installed build. The live 80-row fixture reached the collection boundary and verified first/last-row inclusion, text/PDF handoff and privacy exclusion. The source-menu screenshot was inspected; icon contrast and unselected checkbox visibility were corrected and retested. Existing accessibility authorization was restored after instrumentation, with the service bound and no crashed services.

No paid model request was issued by these tests. Live Codex/DeepSeek summary quality, arbitrary restricted websites, and actual Office-document reading are not newly certified by this receipt. The full repository check still stops at 340 pre-existing i18n text-policy findings; none are in files changed by this feature. Source-size and diff-whitespace checks pass. No PR has been submitted as part of this implementation request.

## Screen Evidence

Android 14+ captures the external application window directly, excluding the assistant. Earlier supported versions hide both accessibility overlays and the mini-chat decor during capture. Structured UI selects the external application rather than the assistant or keyboard. Protected/password screens are not imported as images. A fresh screenshot is visible in the standard attachment preview, can be removed, and is not sent until the user sends it.

This captures the screen when the input opens or when the capture control is used, not continuously. The screenshot can become stale if the user changes the underlying page before sending; capture again to refresh it. Full-page collection still performs visible scrolling, so its existing pause/interruption controls remain important.

## Opaque Article Recovery

Visual reading temporarily moves the floating Activity task behind the article and restores it afterward.
Decor invisibility and `FLAG_NOT_TOUCHABLE` alone cannot bypass Android's cross-UID Activity input sink.
Restoration only occurs while the same external window remains selected; it does not reopen over a different app.

Android v1.3.30 adds a narrowly scoped visual-scroll fallback when a user explicitly selects entire-page analysis and the target exposes no scrollable accessibility node. It checks the external package/window before each vertical gesture, temporarily makes the assistant non-touchable, captures overlapping viewports, and stops on cancellation, target changes, repeated unchanged images or the existing storage budget. Each saved viewport is also processed through the existing local OCR implementation. OCR is evidence, not a verified transcription; the original screenshots remain in the PDF. No links, forms or buttons are activated by this fallback.

Three unchanged observations suggest a visual boundary, not proof of complete source retrieval. The manifest records visual traversal separately from `complete`, and the UI states that hidden, collapsed or unloaded content may be missing. Restoration is recorded only after a visual match. Original-file/link selection remains preferable when available; there is no automatic original-URL discovery.

Read-only floating analysis derives routing requirements from the user's displayed question instead of internal attachment instructions. Reading an attached PDF does not impose the separate `KNOWLEDGE_SEARCH` connector requirement. Explicit user privacy restrictions and the normal availability/health/capacity checks still apply. Both initial routing and failure re-evaluation use this policy. The floating header brands ordinary and Agent-created conversations consistently without changing their stored titles or the main-page header.

### v1.3.30 Device Receipt

The final v1.3.30 / 1073 build was installed over the existing S26U app without clearing data. All 54 focused unit tests and 14 device tests passed. Device coverage includes physical scrolling and first/last-row OCR of an opaque fixture with the floating chat initially open, structured-page collection, cancellation, source persistence, branding, and selection of the configured Codex route. Background gesture readiness uses a main-loop delay rather than a rendering-frame callback, which may not run after the chat task is backgrounded.

The actual WeChat article produced 20 captured screens, including its final readership/comments section, a 4,576,822-byte PDF and a 10,963-byte text attachment. Both visual boundaries were observed, but `complete` remains false: visual traversal does not certify hidden content or OCR accuracy. Exact original-position restoration was not verified (`position_restored=false`).

Initial live end-to-end acceptance was incomplete. A preceding single-screen request reached Codex and returned a correctly qualified summary; the initial 20-screen request timed out, and no corresponding new task was present in the Desktop task database at inspection. The diagnosis and subsequent successful retest are recorded below. No PR was submitted in this repair turn.

### Attachment-Gated Task Encryption

Follow-up diagnosis found all three inputs on Desktop, with the 4,576,822-byte PDF committed at 14:43:37. Android released the task at 14:43:41; Desktop then reported Signal `InvalidMessageException` for the task ciphertext. It had been encrypted before the upload and delayed behind bidirectional chunk/receipt exchanges. `SignalDeferredSendProbe` reproduces this using libsignal 0.86.5: after 20 exchanges the premature ciphertext cannot be decrypted, while encryption after the exchanges succeeds.

Attachment-dependent requests now retain their original application envelope only in the existing encrypted local recovery store. No task Signal ciphertext is generated during the upload. After every validated attachment receipt releases the dependencies and an authorized route is ready, the outbox seals and commits the task ciphertext and its receipt hash before publishing. Subsequent retries reuse that committed ciphertext and the original message/conversation/task/turn identifiers. Failed preparation cannot publish the placeholder. Cancelled records are not recreated. This does not change text-message encryption, receiver authentication, or attachment integrity validation.

`AgentDeferredEncryptionDeviceTest` uses isolated outbox records (without clearing user data) to cover partial/all dependency release, failed encryption, committed-ciphertext reuse, corrupt deferred data and cancellation. The real Signal probe and deterministic tests are not substitutes for successful delivery and summarization of the actual captured document; that acceptance is recorded separately.

### Live Deferred-Encryption Receipt (2026-09-30)

The final-source APK and test APK built successfully. All 38 selected screen-assistant unit cases and both new deferred-encryption device cases passed. The APK was installed over S26U's existing data; no pairing, downloaded model, conversation or sending queue was cleared. The real libsignal probe reported `DEFERRED_SIGNAL_OK stale_ciphertext_rejected=true encrypt_after_upload=true`.

The same saved 20-screen article was submitted through the real floating composer, using the configured Auto Codex route, with its 10,963-byte text and 4,576,822-byte PDF attachments. Source message 2180 created Desktop task `9557ad2b-ecdc-30fe-814b-52a783d2d9fd`. Local timestamps:

- 15:43:03: attachment-dependent request queued; no task ciphertext generated yet.
- 15:46:28: Desktop committed the complete PDF.
- 15:46:31.632: phone accepted the final stored-attachment receipt and released the task.
- 15:46:31.707: phone sealed the task for its first send.
- 15:46:31.959: Desktop task admitted; Codex then ran successfully.
- 15:48:18.204: Desktop recorded completion, with a Chinese summary covering the article's final troubleshooting section.
- Phone screenshot: the same summary and final-section details were visible, the pending indicator stopped, and the turn displayed `已处理 5分26秒`.

This passes the actual captured-document upload, task admission, model execution, return delivery and UI completion scenario that previously timed out. It is not a claim of universal network reliability or perfect original-document coverage. Upload still took about 209 seconds, Desktop execution about 106 seconds, and the displayed end-to-end time was 326 seconds. The model used the saved OCR text; successful PDF transport does not prove every screenshot was visually inspected. The result retained the warning about hidden or unloaded content. Broader throughput tuning, weak-network repetition and arbitrary document coverage remain separate acceptance work.

### Bounded Upload Scheduling

Local MQTT capacity rejection is now distinct from physical send failure. Only when a valid path was selected but no physical publish was attempted does the single-packet outbox roll back that attempt, release its receipt credit, and defer locally for one second. It keeps the committed ciphertext, identifiers and absolute recovery deadline. Physical publish failures, ambiguous delivery and fragment transfers retain their existing recovery semantics. No packet/byte/concurrency limit is raised.

When another message occupies the receipt window, fresh work rechecks capacity within one second rather than sleeping for that message's entire 30-second receipt deadline. A message already sent still retains its full receipt deadline. Deferred task encryption now occurs after receipt-credit admission, with that credit released if encryption preparation fails. Tests cover bounded windows, no physical publish on backpressure, credit recovery, preservation of retry counts and unchanged handling of already-published messages. Live performance measurements are recorded separately; these policies do not establish a throughput guarantee.

The scheduling candidate passed 87 focused unit tests and all three deferred-encryption/backpressure device tests. It was installed over S26U's existing data. A repeat through the floating composer sent the identical 20-page, 4,576,822-byte PDF (SHA-256 `4ac52dd6d6b3b5fe71aac4be6b35a08ff4cb7dad4fa8b6359516bd948b0f6382`) and text attachment, without reducing quality or omitting pages. Source 2209 produced exactly one Desktop task record, `423bb62b-65a1-3940-9e29-31fc52104105`:

- 16:15:09.732: request queued behind its attachments.
- 16:17:00.598: final attachment storage receipt accepted; upload approximately 111 seconds versus 209 seconds in the preceding run.
- 16:17:00.669: task sealed; Desktop admitted it at 16:17:01.726.
- 16:18:21.746: Desktop completed the summary, including the article's final section.
- S26U displayed the completed result and `已处理 3分22秒`, versus 5 minutes 26 seconds previously.

This single before/after sample reduced upload time by approximately 47% and displayed end-to-end time by 38%. Provider execution also varied (80 versus 106 seconds); do not attribute that portion to the transport fix. It is not a repeated-run median/p95 or weak-network guarantee. The result explicitly said it read the saved text and did not individually zoom/verify the PDF figures; that visual-verification limitation remains.

## Verification

Device tests use isolated conversations without making paid model calls. They check actual composer/adapter identity, no automatic submission, non-modal bounds, input actions, keyboard visibility, resize preservation, recreation/draft restore, shared rich-output updates, collapse without cancellation, home-route exclusion, and external-window capture. Live-provider acceptance is reported separately from these tests.

The v1.3.11 / 1055 candidate passed both APK build targets and 155 focused unit tests across 15 suites, with no failures or errors. It was installed over the existing S26U App without clearing user configuration or models. All 11 mini-chat/presentation device cases passed after fixing hidden-output invalidation and correcting the test to match the main composer's existing more-menu policy. A further 24 device cases passed for full-page collection, phone controls, cancellation, home routing and stable Auto routing. The paused request cancellation also has a unit regression confirming it only cancels the owning turn.

The final source revision additionally separates the compact header's session/model touch targets and identifies each phone-action approval by a revision rather than its text. Repeated identical approval descriptions still require separate decisions; dismissing an approval dialog cancels its request. Both APK targets and all 156 focused unit tests passed. This revision is not installed or device-retested yet because S26U disconnected during visual inspection. The 35 passing device cases above refer to the preceding candidate.

These device cases validate shared UI and controlled local behavior, not new live-provider completion, actual spoken continuous-voice recognition, every attachment picker, or Downloads viewer/save acceptance. Final visual inspection must be completed before claiming that acceptance.

## Submission Closeout

The submitted release increments Android to v1.3.12 / 1056 and Desktop to v1.3.12. Both Android APK targets were rebuilt after the version change, with all 156 focused unit tests passing. Android package metadata reports v1.3.12 / 1056; Desktop package and lockfile versions agree. The 16 KB audit passed for 74 AArch64 libraries and the QNN package audit passed for 24 libraries. Desktop regression reran 90 Python cases, with 89 passing and one existing Windows process case skipped.

`npm run check` stopped at the repository's existing i18n text-policy failures. All 333 reported findings were compared with `origin/main` and matched existing source lines; this change adds none. Broader device/packaged smoke commands and the unfiltered Android unit suite were not run for this submission. The focused device coverage above remains candidate-build evidence, not v1.3.12 device acceptance. No new installation, Desktop restart or merge is performed as part of submitting this PR.
