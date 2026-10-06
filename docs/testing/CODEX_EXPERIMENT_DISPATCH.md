# Registered App Experiment Dispatch

This is a host-opted-in evaluation path, not a new production model default.
With `GALAXYSSI_CODEX_EXPERIMENT_REGISTRY` unset, ordinary App tasks retain their
existing executors, workspace layout, tools and recovery behavior. Opt-out does
not read registry files or start an extra server.

## Private Registration

The variable names an existing private JSON file outside Git. The trusted host
pre-registers exact tasks before dispatch. Never construct it from MQTT fields,
model output or a downloadable document. The file must be within each scope's
protected subtree. Workspaces and thread ledgers must not overlap, be shared
across arms, or use symlinks/junctions. Registered peer workspaces become denied
roots in each other scope's profile.

The shape below uses placeholders, not usable credentials or a model default:

```json
{
  "format": "galaxyssi.codex-experiment-registry.v1",
  "scopes": [{
    "scope_id": "pilot-arm-a",
    "client_route_id": "authenticated-route-id",
    "client_conversation_id": "new-phone-conversation-id",
    "task_ids": ["predeclared-task-id"],
    "task_conversations": {
      "predeclared-task-id": "exact-backend-member-conversation-id"
    },
    "conversation_ids": ["exact-backend-member-conversation-id"],
    "workspace": "ABSOLUTE_EXISTING_PRIVATE_ARM_DIRECTORY",
    "protected_root": "ABSOLUTE_EXISTING_PRIVATE_EVALUATOR_DIRECTORY",
    "state_path": "ABSOLUTE_PRIVATE_EVALUATOR_DIRECTORY/thread-ledger.json",
    "model": "EXACT_APP_SELECTED_MODEL",
    "effort": "high",
    "read_only": true,
    "mcp_names": [],
    "skill_paths": []
  }]
}
```

Obtain actual MCP names and exact skill paths from a model-free inventory first;
empty arrays do not bypass verification of enabled capabilities. Choose the
model and effort in the App and register that exact selection. A mismatch is
rejected, not silently substituted. Each task is pinned to one backend member
conversation even when a scope has several members.

The registry freezes for a Desktop lifetime. Editing/removing it or changing
its configured path does not reload live permissions. End the experiment and
restart deliberately when changing registrations. Keep the private registry and
ledgers for checkpoint and artifact recovery; do not delete them during a run.

## Dispatch and Recovery

- Admission compares the authenticated MQTT route with the host registration,
  original phone conversation, exact task/member identity, model and effort.
- Current integration accepts text-only structured connector tasks. It does not
  enable screen analysis, attachments, arbitrary ordinary tasks or worker handoff.
  Structured planning retains a read-only profile; nothing upgrades it to writes.
- Each registered scope gets a separate real `CodexAppServer` instance. It never
  imports ordinary Desktop conversation bindings or automatically stages earlier
  ordinary-chat artifacts. A busy identity fails instead of creating a new thread.
- Private task directories are deterministic descendants of the registered arm
  workspace. Workspace/artifact helpers resolve those directories, while normal
  phone cleanup preserves experiment evidence for explicit host retention.
- A task snapshot stores an admission fingerprint outside restorable remote
  options. Recovery requires the same host registration and fingerprint. A remote
  hint alone is not a grant. Missing grants cannot fall back to the ordinary server.
  Admission rejection is persisted as a failed task and sent through the normal
  task-event channel, rather than leaving the phone waiting for a model response.
- Completed experimental output does not trigger the ordinary cross-provider
  recovery, prior-file import or artifact-repair heuristics. Evaluation retains the
  original result instead of covertly adding helper calls. The App remains in
  charge of explicitly dispatched subsequent experimental nodes.
- Cancellation targets the registered server; Desktop shutdown closes all owned
  scoped servers. Model/effort/capability and owned-thread checks remain active.

## Acceptance Boundaries

Synthetic tests drive the real MQTT handler with provider doubles, including
start, recovery, cancellation, changed selection, missing fingerprints and busy
threads. They also cover ordinary Codex/workspace behavior and host registration.
A separate model-free live probe exercises the actual registered server factory
and eight command canaries: own/peer/protected/unprotected reads and writes.

This is not a claim of real MQTT delivery, real-model checkpoint recovery, full
host isolation or efficacy. The current Windows profile still allows unprotected
host reads. Evaluator copies, provider transcripts/caches, logs, input assembly,
network behavior and real-turn recovery need independent verification before a
blinded study. Whole-lifetime provider cost remains unknown.

Keep protocols, answers, private registrations, reports and manuscripts outside
GitHub. Preserve failed probes and prior null efficacy findings. More successful
infrastructure checks are not evidence that multi-agent reasoning is superior.
