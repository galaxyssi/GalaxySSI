# Agent Execution Presentation

GalaxySSI presents every active task with one consistent execution contract on
Android and Desktop.

## Required information

Every execution surface shows:

- the Agent, model, or GalaxySSI runtime currently responsible for the task;
- the execution host as an explicit badge, such as `On phone` or `On Desktop`;
- the execution runtime, such as Android native tools, phone Linux, a phone
  cloud API, a local model, a Desktop Agent, or a Desktop tool;
- the current step and continuously updated elapsed time;
- a visible cancel action while cancellation is supported;
- an expandable Run Timeline for detailed progress and evidence.

The final response remains separate from the execution timeline. Terminal tasks
never advertise cancellation.

## Run Timeline contract

Android and Desktop expose `galaxyssi.run-timeline/1.0`. Its canonical event
classes are:

- `plan`: the bounded plan or execution policy selected for the task;
- `tool`: a real tool invocation or update, never a fabricated placeholder;
- `retry`: an explicit retry, recovery, or replan attempt;
- `result`: the terminal successful outcome metadata;
- `failure`: the terminal failed, cancelled, or timed-out outcome metadata.

Provider-specific events remain available through `source_kind`. Every event is
bound to route, conversation, task, turn, and Agent identity. The projection
does not copy prompts, final response bodies, credentials, or raw tool output.
Android reconstructs missing plan and real tool lifecycle entries from its
encrypted recorded run before appending the terminal event. Desktop reconstructs
the same bounded timeline from its persistent task record, so process restarts
do not erase lifecycle history.

## Protocol object

Desktop task snapshots and phone task events carry an `execution_view` object:

```json
{
  "contract": "galaxyssi.execution-location/1.0",
  "executor_id": "codex",
  "location_kind": "desktop",
  "location_id": "workstation",
  "location_name": "WORKSTATION",
  "runtime_kind": "desktop_agent",
  "runtime_id": "codex",
  "runtime_name": "codex",
  "trusted_source": "paired_desktop",
  "status": "running",
  "current_step": "Reading source files",
  "cancellable": true,
  "started_at": 1785254400000,
  "completed_at": 0
}
```

This object is presentation metadata, not an authorization grant. Cancellation
still passes through the task manager, route identity checks, and the relevant
runtime cancellation source. Android-generated execution locations come from
validated local routes and tool identities. A remote event can only claim a
Desktop host; it cannot impersonate phone-native execution. A versioned
location is marked trusted only when it arrives through the paired Desktop
route with a non-empty Desktop identity.

Phone cloud APIs remain phone-hosted orchestration. Their runtime is
`phone_cloud_api`, which keeps them visibly distinct from both a phone-local
model and a Desktop Agent even though the provider performs inference outside
the device.

## Fallback behavior

Older or local-only task objects are rendered from their route:

- local system routes run on the phone;
- phone Linux, local model, and cloud API routes remain separate runtimes;
- Desktop Agent routes use the paired Desktop name;
- Desktop-hosted local models use the paired Desktop host;
- device routes identify a connected device;
- unknown routes remain automatic without inventing an executor.

The UI may localize labels, but it must not infer security permissions from
display text.
