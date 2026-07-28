# Agent Execution Presentation

SignalASI presents every active task with one consistent execution contract on
Android and Desktop.

## Required information

Every execution surface shows:

- the Agent, model, or SignalASI runtime currently responsible for the task;
- the execution location, such as the phone, a named Desktop, the cloud, or a
  connected device;
- the current step and continuously updated elapsed time;
- a visible cancel action while cancellation is supported;
- an expandable Run Timeline for detailed progress and evidence.

The final response remains separate from the execution timeline. Terminal tasks
never advertise cancellation.

## Protocol object

Desktop task snapshots and phone task events carry an `execution_view` object:

```json
{
  "executor_id": "codex",
  "location_kind": "desktop",
  "location_id": "workstation",
  "location_name": "WORKSTATION",
  "status": "running",
  "current_step": "Reading source files",
  "cancellable": true,
  "started_at": 1785254400000,
  "completed_at": 0
}
```

This object is presentation metadata, not an authorization grant. Cancellation
still passes through the task manager, route identity checks, and the relevant
runtime cancellation source.

## Fallback behavior

Older or local-only task objects are rendered from their route:

- local system and local model routes run on the phone;
- Desktop Agent routes use the paired Desktop name;
- cloud model routes use the cloud location;
- device routes identify a connected device;
- unknown routes remain automatic without inventing an executor.

The UI may localize labels, but it must not infer security permissions from
display text.
