# Android Voice Agent Run Bridge

PR-10 separates local task creation from confirmed remote execution and gives persistent Agent runs a foreground lifecycle on Android.

## Lifecycle

```text
voice command
  -> local RunCreated
  -> existing encrypted Agent Run event store
  -> MQTT task dispatch
  -> explicit remote Accepted
  -> Stage / Progress / Partial / Approval events
  -> Completed / Failed / Cancelled
```

Publishing MQTT data never implies acceptance. The UI and speech layer may use `Accepted` only after an explicit remote event. Running or progress events can update the task without fabricating acceptance.

Every run is keyed by a stable idempotency key and stores its conversation, turn, task, source message, Agent, device, trace, status sequence, partial sequence, and bounded event-ID ledger. Repeated creation returns the existing run. Duplicate events, stale sequences, private reasoning, and events arriving after a terminal state are ignored.

## Foreground behavior

The existing execution row is the task card. One stable transcript key is updated from creation through completion, so status changes do not create repeated rows. It shows the Agent, device, current stage, elapsed time, first visible discovery, cancellation, and task details. Progress rendering is coalesced to 200 ms while acceptance, approval, failure, cancellation, and completion render immediately.

Run state is event-sourced in the existing encrypted Agent Run store rather than a second task database, and is restored after Activity or process recreation. The background message service consumes lifecycle events even when the Activity is absent. A legacy Desktop that returns only a final text response still completes the matching run.

Handing a persistent remote run off releases the voice interaction coordinator immediately. The user can start the next command while the remote task continues. Acceptance and approval speech comes only from real remote events and is suppressed while the user is recording.

## Feature flag

`agent.voice_run_bridge_v1` defaults on for debuggable builds and remains opt-in for release builds during staged rollout.

## Verification

```bash
npm run smoke:android:voice-agent-run
```

The deterministic gate covers idempotent creation, explicit acceptance, running without acceptance, stale and duplicate events, terminal immutability, state restoration, partial-result ordering, private-event filtering, approval, dispatch failure, legacy final responses, and release of the voice session after remote handoff.
