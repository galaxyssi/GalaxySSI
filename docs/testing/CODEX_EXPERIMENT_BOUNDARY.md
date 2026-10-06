# Scoped Codex Experiment Boundary

`CodexAppServer` accepts an optional trusted-host `experiment_boundary` object.
It applies an experiment policy inside the real adapter's process startup, task
admission, thread start/resume, turn submission, state storage and server-request
handling. Omitting it preserves ordinary behavior. It is not a phone option,
remote payload field, global default, or a new way to widen permissions.

## Host Contract

Construct `CodexExperimentBoundary` with an explicit scope ID, dedicated existing
workspace, separate existing protected subtree, state file beneath that protected
subtree, exact conversation IDs, and the model/effort chosen for the experiment.
Provide the configured MCP names and exact runtime-reported skill paths discovered
by the model-free preflight. No model name is hardcoded in the boundary.

The host must own this configuration. Do not create it from model output or an
untrusted remote task request. Use a separate adapter instance for each experiment
scope; do not attach it to the shared ordinary-chat singleton. The optional
[host registry](CODEX_EXPERIMENT_DISPATCH.md) now binds exact authenticated App
tasks to separate instances in MQTT dispatch, recovery and cancellation. This
code integration is not yet real-phone/model end-to-end acceptance.

Private workspaces and ledgers must be outside Git, not symlinks or junctions.
The workspace and protected subtree cannot overlap. The constructor and admission
gate reject paths outside the declared workspace, images, unknown conversations,
changed model/effort, and incompatible stored state. The current evaluation path
is deliberately text-only; ordinary multimodal tasks are unaffected.
Use `read_only=true` for structured planning requests. That profile extends
`:read-only`, not `:workspace`; readonly requests still cannot use a writable
registration. Optional `denied_roots` exclude other experimental workspaces.

## Enforcement

- The adapter starts its own child with named permissions and process-local CLI
  overrides, not the ordinary network-enabled legacy sandbox override.
- The command profile denies the protected subtree and temporary roots, allows
  the experiment workspace, and disables command networking. It still permits
  other host reads. This is **not** workspace-only host isolation.
- Web search, apps, plugins, browser/computer use, memory, hooks, image tools,
  skill search, goals and child agents are disabled for this instance.
- Effective config and skill inventory are checked at startup and before each
  model turn or steer. Thread policy and MCP tools/resources are checked on
  start/resume, and capabilities are checked again before model input.
- Thread start requests no dynamic tools, external environments or additional
  runtime roots, and disables provider fallback. Resume uses only fields in the
  installed resume schema; it is limited to locally recorded, previously verified
  threads. The schema does not expose all start-only options on resume.
- Model input accepts only text. Extra input references, history/path injection,
  changed model/effort and alternate control RPCs are rejected before dispatch.
- Dynamic tool calls are refused even if unexpectedly requested. Permission and
  approval requests are denied; unknown server requests receive an explicit error.
- If verification fails, the scoped process is closed. There is no ordinary-mode
  fallback. An unknown/missing thread is not silently replaced, and an ambiguous
  thread-start timeout is not automatically retried.

## Persistence

The private ledger stores owned thread IDs, working directories and conversation
bindings with a fingerprint of the scope/policy. It never reads the ordinary
Desktop conversation map. Writes are atomic; damaged or incompatible state is
rejected instead of being interpreted as a fresh conversation. No verification
flag survives process restart: the runtime and resumed thread must pass again.

A runtime may not persist a newly created thread until it has an actual turn.
A model-free empty-thread restart can therefore return `thread not found`.
Preserve that observation; do not invent a successful resume or dispatch a model
just to conceal the failure. A real App-selected task with actual model history
is required for end-to-end recovery acceptance.

## Verification and Remaining Work

```powershell
python -B -m unittest test_codex_experiment_boundary `
  test_codex_conversation_threads test_codex_startup_concurrency -v
```

Run from `apps/desktop/core/galaxyssi-link/backend` with its declared dependencies.
Tests exercise the actual adapter request wrapper and ordinary-chat regressions,
using synthetic provider responses. Live model-free probes separately check the
installed runtime, but do not establish model behavior or study blinding.

Outstanding before efficacy collection:

- Verify the registered App-selected MQTT path on a real phone and model turn,
  including restored checkpoints, cancellation and input assembly.
- Verify actual-model negative canaries through every available input/tool path.
- Enumerate and protect all evaluator copies, caches, logs and auxiliary stores;
  blocking one subtree does not certify that no other copies are readable.
- Verify transport/input assembly, selected model provenance, inherited prompts,
  network enforcement, lifetime resource ownership and actual recovery.
- Keep failed runs, unknown usage/billing and previous efficacy results unchanged.

This boundary does not prove higher intelligence, team superiority, equal cost,
experimental novelty, or publication readiness. No manuscript or live research
records belong in the repository.

References: [App-server](https://learn.chatgpt.com/docs/app-server),
[permissions](https://learn.chatgpt.com/docs/permissions), and the
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
Always verify fields against the exact installed app-server schema.
