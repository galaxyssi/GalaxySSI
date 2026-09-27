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

## Validation

Unit coverage: target selection, overlay/IME exclusion, split screen, stale revisions, bounded pages, sensitive-action confirmation, read-only authorization, pause/resume and cancellation during approval.

Current S26U candidate: 266 selected unit tests pass, including full-revision preservation across large node pages and actual truncated dependency handoffs. Nine controlled device tests pass on Android 16, using unique invocation identities and waiting for the test page to stabilize. No user apps or other connected devices are part of these tests.

The configured home-Agent acceptance test also completed a real inspect/click/type/verify loop on the disposable fixture. The first passing run took 259.12 seconds, including stale-observation recovery and an Auto provider change. After the compact-frame fix, the final installed production code passed again in 291.737 seconds with successful inspect and mutation receipts. An intervening run was cancelled and is not counted as a pass. These are functional acceptance samples, not a latency guarantee or a representative performance benchmark.

Acceptance cleanup follows its own request's turn IDs, not the shared last-turn preference. Leaving the disposable fixture aborts that test; cleanup does not cancel a newer user task or overwrite newer screen-assistant selections.

Device coverage uses a separate test-APK fixture with no user data: underlying UI with a visible assistant panel, password redaction, screenshot capture, click/input observations, stale-action rejection, and panel pause/continue/stop. Real Chrome login flows, each camera/microphone/location permission and recording consent remain additional acceptance scenarios, not implied by unit tests.
