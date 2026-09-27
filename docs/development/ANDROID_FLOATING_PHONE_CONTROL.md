# Floating Phone Control

The existing screen assistant now has separate read-only analysis and explicit phone-task entry points. Its visual bubble and home-screen Agent selection are retained. Long press offers phone task, open App, Chrome and device tools; the result panel offers pause, continue, confirm and stop. Collapsing the panel does not stop a task.

## Execution

- Reuse the Android supervised Agent loop. A selected remote Agent plans; Android executes phone tools and returns observations. Do not ask the Desktop to operate its own screen.
- Phone-task routing delegates navigation capabilities to local tools, rather than requiring the reasoning provider itself to advertise Android navigation. Privacy, budget, health and capacity checks still apply. Phone plans use a separate allowed-tool policy; code-project plans keep their existing policy.
- `galaxyssi.phone.ui.inspect` selects an external application window, excluding accessibility overlays, the IME and GalaxySSI prompt windows. Nodes include actual bounds, capabilities, enabled/check states and a revision. Password fields are redacted.
- `galaxyssi.phone.ui.act` requires the observed window, revision and node path, then revalidates the node. It performs one click, long click, text update or scroll and returns a new observation. Dispatch acceptance is not proof of business success.
- UI pages and mutation receipts start with a compact `_frame` containing the current window, package and full revision. It survives the existing 4,000-character dependency-output budget; a missing frame or node still requires another inspection, not an unguarded retry.
- One shared physical-display lock serializes mutations. Pause, approval and recording waits do not hold that lock. Stale coordinate actions are disallowed in floating tasks.
- Analysis tasks receive a restricted tool registry and cannot authorize phone mutations. UI/page/tool content remains untrusted evidence. Sensitive labeled sends, deletions and payments require an explicit confirmation in the panel; this is not a universal semantic detector for every third-party UI.
- Existing native tools supply installed-App launch, battery/network/location, notifications, user-visible camera and microphone capture. Their existing Android permissions and native consent policies still apply.
- Chrome open/search/read/navigation runs in installed Chrome with its existing session. No credentials or cookies are copied. Missing navigation controls are reported, not guessed; an Agent can inspect and open Chrome's actual menu.

## Screenshots And Recording

On Android 14+, screenshot the target window directly. Older supported screen-assistant versions hide the assistant and wait two display frames before capture. Respect secure-window failures; never bypass protected content.

The latest requested screenshot is also attached to the same turn for the next model observation, without accumulating previous screenshots. Screenshot and recording receipts use the existing image/video output blocks.

Screen recording uses a fresh Android MediaProjection consent dialog, a mediaProjection foreground service and a Stop notification. It records H.264/MP4 without microphone audio, hides the assistant while recording, and restores it on completion/cancellation/failure. Only a completed, nonempty local file is returned. Recording duration is bounded to 120 seconds per tool invocation; longer recordings need a separate explicitly designed lifecycle.

## Boundaries

- Structure exposes currently accessible UI, not invisible/offscreen content. Pagination reads the node inventory; scrolling is needed for further content. Canvas/WebView/custom controls may need screenshot perception.
- The existing screen-assistant submission bridge still requires GalaxySSI to have initialized its main runtime once in the current process. This change does not claim cold-process, unattended headless execution.
- Paused/approval state is process-local. Process death must not silently authorize or resume phone mutations; a new explicit task is required.
- Google Play distribution and OEM accessibility/background restrictions need separate policy/device validation.

## Floating Composer

Question, follow-up and phone-task prompts reuse the home composer's text selection, typography, voice-wave and send-plane assets. The window remains above the IME and system navigation bar. Its height follows the input rather than using the old fixed 180dp surface; long drafts scroll inside the editor while both actions stay visible. Close/back never submits, blank input cannot submit, and recording/recognition disables submission.

Voice input shares the existing home PCM audio hub and configured online/QNN/Whisper ASR. It does not create another model runtime or invoke Android's unrelated speech recognizer. A visible prompt temporarily claims the home QNN client's foreground state and releases it after capture/finalization. Closing or backgrounding the prompt stops its microphone session. Recognized text returns to the draft only, without command classification, tool execution or an automatic Agent submission.

## Home Routing And First Tap

Screen analysis and follow-ups inherit the current conversation of the most recently foregrounded GalaxySSI window, not the new-conversation default preference. Manual target, model and reasoning effort are copied without changing the source conversation. Auto copies the displayed preferred target into the screen conversation while retaining normal privacy, budget, health, capability and capacity checks; it does not lock the task to that provider or disable failover. An old screen conversation's DeepSeek preference cannot override the current home choice.

Read-only screen analysis routes directly through this selected reasoning provider instead of applying ordinary command/provider-name heuristics to the page evidence. A page mentioning DeepSeek, navigation commands or notification commands cannot choose a different provider or become a local command merely because of those words.

New conversations start in Auto and prefer a configured Codex, including a paired Codex awaiting its initial heartbeat. Existing manual conversations and remembered Auto routes remain unchanged. An absent/unconfigured Codex does not block another configured provider.

A completed result panel no longer consumes the first bubble tap only to collapse: one tap starts a fresh analysis and immediately shows a cancelable preparation state. Running tasks still expand/collapse without duplicate submission. An initializing source window is given up to 15 seconds to finish hydration, with nonblocking 100ms readiness checks and cancellation between checks. This is a startup wait, not a model execution timeout. A fresh connector registry is read off the main thread instead of testing a stale UI runtime snapshot. A genuinely missing runtime still requires opening GalaxySSI once; submission failures are logged and have a distinct visible status.

## Validation

Unit coverage: target selection, overlay/IME exclusion, split screen, stale revisions, bounded pages, sensitive-action confirmation, read-only authorization, pause/resume and cancellation during approval.

Current S26U candidate: 266 selected unit tests pass, including full-revision preservation across large node pages and actual truncated dependency handoffs. Nine controlled device tests pass on Android 16, using unique invocation identities and waiting for the test page to stabilize. No user apps or other connected devices are part of these tests.

The configured home-Agent acceptance test also completed a real inspect/click/type/verify loop on the disposable fixture. The first passing run took 259.12 seconds, including stale-observation recovery and an Auto provider change. After the compact-frame fix, the final installed production code passed again in 291.737 seconds with successful inspect and mutation receipts. An intervening run was cancelled and is not counted as a pass. These are functional acceptance samples, not a latency guarantee or a representative performance benchmark.

Acceptance cleanup follows its own request's turn IDs, not the shared last-turn preference. Leaving the disposable fixture aborts that test; cleanup does not cancel a newer user task or overwrite newer screen-assistant selections.

Device coverage uses a separate test-APK fixture with no user data: underlying UI with a visible assistant panel, password redaction, screenshot capture, click/input observations, stale-action rejection, and panel pause/continue/stop. Real Chrome login flows, each camera/microphone/location permission and recording consent remain additional acceptance scenarios, not implied by unit tests.

The v1.3.8 composer update passes 18 focused unit tests and 12 controlled S26U device tests. Added cases cover a 20-paragraph Chinese draft, fully visible voice/send hit targets, blank submission rejection and closing a populated draft without dispatch. Actual long-press-menu entry and two-line keyboard input were checked over the existing public Chrome page. QNN dictation capture and no-speech shutdown were observed. In the separate live acceptance check, the user confirmed that spoken text appeared in the draft; logs confirm QNN capture stopped after approximately four seconds. After submission, a real page-analysis reply appeared in the floating panel with the completed state. The reply distinguished observed screen content from unverified external information. This functional sample does not establish low latency: the cloud request took approximately 92 seconds and performed additional external research. Broader menu coverage and research-latency optimization remain separate acceptance work.

The v1.3.9 routing update passes 111 focused unit tests and 20 controlled S26U device tests. The six home-routing device cases use isolated preference namespaces, preserving the user's configuration. Coverage includes the Auto Codex new-session default, existing manual selections, model/effort inheritance, replacing an old screen-session cloud preference, follow-up routing, preparation feedback and cancellation. The installed S26U build is version 1.3.9 (1053); its new-session header was observed as Auto Codex. One real bubble tap immediately showed preparation, inherited Auto Codex and published a Codex request. This establishes initial routing and submission, not completed remote execution or a latency guarantee. Subsequent transport failures and normal Auto failover remain separate acceptance conditions.
