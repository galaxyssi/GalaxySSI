# Floating Agent Chat

## Reuse Boundary

`ScreenAssistantChatActivity` subclasses `MainActivity`, as the existing independent conversation windows do. It inflates the same `activity_main` layout, uses the same composer views and controllers, and retains `AgentTranscriptRecyclerAdapter` and the main rich-output renderer. Submission, model routing, attachment staging, mentions, microphone/continuous voice, task controls and conversation persistence are not reimplemented.

The only new responsibilities are non-modal window sizing, a compact header, collapse/restore, and importing the external screen as a normal removable attachment. Tapping the floating button does not submit a task. Send uses the normal main-page submission path. A screen attachment binds read-only analysis to that turn; removing it leaves the usual Agent behavior. The explicit phone-execution menu retains its authorization scope.

The copied `ScreenAssistantPromptActivity`, its standalone dictation controller and its composer policies are deleted. The plain-text result panel is deleted. The accessibility overlay retains the floating button, tool menu, crop selector and full-page capture progress controls. Actual Agent results render only in the real Agent page.

## Window And State

The mini chat is a non-exported, single-task Activity with a separate task affinity and no dim background. Its bounds fit visible system bars and the keyboard. Outside its bounds, the external app remains touchable. Compact and expanded states use the same view tree and conversation; resize does not recreate the Agent.

Collapse saves the normal window draft and moves only this task to the background. It does not invoke task cancellation or finish the Activity. Stop remains a separate explicit operation with conversation/turn validation. Process death has the same recovery semantics and limitations as the existing shared Agent runtime; an Activity window is not a guarantee that Android will keep the process alive indefinitely.

The mini chat cannot become the home Agent selection source. Home routing is inherited through the existing bridge. The normal main page layout and handlers are unchanged, apart from a no-op submission notification overridden only by this Activity.

## Screen Evidence

Android 14+ captures the external application window directly, excluding the assistant. Earlier supported versions hide both accessibility overlays and the mini-chat decor during capture. Structured UI selects the external application rather than the assistant or keyboard. Protected/password screens are not imported as images. A fresh screenshot is visible in the standard attachment preview, can be removed, and is not sent until the user sends it.

This captures the screen when the input opens or when the capture control is used, not continuously. The screenshot can become stale if the user changes the underlying page before sending; capture again to refresh it. Full-page collection still performs visible scrolling, so its existing pause/interruption controls remain important.

## Verification

Device tests use isolated conversations without making paid model calls. They check actual composer/adapter identity, no automatic submission, non-modal bounds, input actions, keyboard visibility, resize preservation, recreation/draft restore, shared rich-output updates, collapse without cancellation, home-route exclusion, and external-window capture. Live-provider acceptance is reported separately from these tests.

The v1.3.11 / 1055 candidate passed both APK build targets and 155 focused unit tests across 15 suites, with no failures or errors. It was installed over the existing S26U App without clearing user configuration or models. All 11 mini-chat/presentation device cases passed after fixing hidden-output invalidation and correcting the test to match the main composer's existing more-menu policy. A further 24 device cases passed for full-page collection, phone controls, cancellation, home routing and stable Auto routing. The paused request cancellation also has a unit regression confirming it only cancels the owning turn.

The final source revision additionally separates the compact header's session/model touch targets and identifies each phone-action approval by a revision rather than its text. Repeated identical approval descriptions still require separate decisions; dismissing an approval dialog cancels its request. Both APK targets and all 156 focused unit tests passed. This revision is not installed or device-retested yet because S26U disconnected during visual inspection. The 35 passing device cases above refer to the preceding candidate.

These device cases validate shared UI and controlled local behavior, not new live-provider completion, actual spoken continuous-voice recognition, every attachment picker, or Downloads viewer/save acceptance. Final visual inspection must be completed before claiming that acceptance.

## Submission Closeout

The submitted release increments Android to v1.3.12 / 1056 and Desktop to v1.3.12. Both Android APK targets were rebuilt after the version change, with all 156 focused unit tests passing. Android package metadata reports v1.3.12 / 1056; Desktop package and lockfile versions agree. The 16 KB audit passed for 74 AArch64 libraries and the QNN package audit passed for 24 libraries. Desktop regression reran 90 Python cases, with 89 passing and one existing Windows process case skipped.

`npm run check` stopped at the repository's existing i18n text-policy failures. All 333 reported findings were compared with `origin/main` and matched existing source lines; this change adds none. Broader device/packaged smoke commands and the unfiltered Android unit suite were not run for this submission. The focused device coverage above remains candidate-build evidence, not v1.3.12 device acceptance. No new installation, Desktop restart or merge is performed as part of submitting this PR.
