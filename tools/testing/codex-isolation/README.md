# Codex Isolation Preflight

This model-free diagnostic checks whether a local Codex command sandbox can
read and write an allowed synthetic workspace while denying reads and writes
to a sibling synthetic canary directory. It is a prerequisite check, not a
production sandbox implementation or proof that an efficacy study is blinded.
No Android or Desktop application code, release version, routing, credentials,
global configuration, or running Desktop instance is changed.

An independent task directory is not a read boundary. The legacy
`workspaceWrite` policy normally restricts writes but permits broader reads.
The diagnostic compares that behavior with a child-process-only named profile:
workspace protections inherited from `:workspace`, root reads denied, minimal
runtime and the explicitly selected Python directory readable, temporary-root
access denied, the canary directory explicitly denied, and command networking
disabled. It does not silently fall back to broader access after an error.

An explicitly selected `denied-subtree` mode instead permits root reads but
denies the freshly created canary directory. It additionally tests an
unprotected sibling: reading that sibling must remain possible, while writing
outside the workspace must remain denied. A successful subtree result is
therefore not workspace-only read isolation. These are separate diagnostics,
not fallback stages; each invocation requires a fresh output directory.

## Run

Use Python 3.11 or newer. Use the exact Codex executable used by the connector.
The output directory must be new and outside any Git repository. Reports contain
local paths and runtime hashes; do not upload them. Only freshly generated
canary content is accessed, never an existing evaluator or private document.

```powershell
python -B -m unittest discover -s tools/testing/codex-isolation -p test_preflight.py -v

python -B tools/testing/codex-isolation/preflight.py `
  --executable C:\path\to\codex.exe `
  --directory C:\private-diagnostics\isolation-probe-001

# Separate, explicitly narrower diagnostic; not a retry of the strict policy.
python -B tools/testing/codex-isolation/preflight.py `
  --executable C:\path\to\codex.exe `
  --directory C:\private-diagnostics\subtree-probe-001 `
  --boundary denied-subtree
```

The tool starts its own app-server, calls only `initialize` and `command/exec`,
then terminates that child. It never starts a model turn or changes settings
with `config/value/write`. Named permissions exist only in that child's CLI
overrides. Platform enforcement may apply temporary sandbox ACLs in the normal
way. No operating-system sandbox setup or global policy migration is attempted.

Each check is retained: eight for `workspace-only`, twelve for `denied-subtree`.
Positive controls must actually read and
write the workspace successfully. A denied probe must execute successfully and
report a `PermissionError`; an RPC rejection, missing interpreter, timeout,
malformed output or generic nonzero exit is **inconclusive**, not a pass.
The report binds the exact probe, Codex and Python executables by SHA-256.
Raw provider stderr and error text are not copied into reports; selected known
errors have safe diagnostic codes and all RPC errors have message digests.
Reports use schema v2 with the explicit boundary and separate pass flags.
Exit code 0 means only the selected **command** boundary passed; 2 means it
did not. Invocation/setup errors can also produce a nonzero exit.

## Current Runtime Caveats

Current runtimes can reject the old `sandboxPolicy.readOnlyAccess` parameter
and require `command/exec.permissionProfile`. Do not submit both fields.
Some Windows runtimes reject root-read denial even when the named profile is
valid, reporting that elevated sandboxing requires effective root read access.
The safe outcome is `windows_runtime_requires_root_read` and a failed readiness
gate, not an automatic broad-read retry or a claimed protected evaluator.

If explicitly testing `denied-subtree`, inspect both its denial results and
its broader-read positive control. This mode does not locate all sensitive
files, protect unlisted directories, certify tool-path isolation, or apply a
policy to an actual study. Never place real evaluator data in the canary paths.
Windows may retain sandbox ACL entries on probe directories; do not reuse those
directories as production workspaces or silently alter their ACLs to force a pass.

The restricted probe is not yet connected to ordinary or evaluation model
turns. Passing it does not test image tools, MCP, plugins, network enforcement,
child agents, input assembly, other thread stores, symlink escapes or evaluator
process separation. It therefore always reports
`ready_for_blind_efficacy_study=false`. These surfaces need their own controls
and negative tests before a prospective blinded comparison can be claimed.

Official references:
- [App-server command execution](https://learn.chatgpt.com/docs/app-server)
- [Permission profiles and enforcement scope](https://learn.chatgpt.com/docs/permissions)

Keep failed diagnostic runs, frozen research protocols and original scores.
An isolation limitation does not prove past answer leakage occurred, but it
precludes certifying that leakage was impossible.

## Ephemeral Thread Capability Preflight

`thread_preflight.py` additionally initializes an empty ephemeral provider
thread. This is a model-free diagnostic, not an App experiment or production
integration. It never calls `turn/start`, `turn/steer`, `thread/resume`, or
`thread/fork`; those methods are outside its RPC allowlist. Select the model and
effort explicitly for metadata verification; no model is actually invoked.

```powershell
python -B -m unittest discover -s tools/testing/codex-isolation -p 'test*.py' -v

python -B tools/testing/codex-isolation/thread_preflight.py `
  --codex C:\path\to\codex.exe `
  --python C:\path\to\python.exe `
  --model YOUR_SELECTED_MODEL --effort high `
  --output C:\private-diagnostics\thread-probe-001
```

The first short-lived child discovers configured MCP names and skill paths.
The second child disables those entries with process-local CLI overrides,
verifies effective flags, and starts an ephemeral thread with a fresh named
`denied-subtree` permission profile. It requests no dynamic tools, environments,
selected capability roots, additional runtime workspace roots, or provider
model fallback. Its working directory is a fresh synthetic workspace.
Web search, apps, plugins, browser/computer use, memory, hooks, image tools,
skill search, goals and child agents are disabled for this probe. Ordinary App
conversations and user configuration are unchanged.

It checks the returned permission profile, model, effort, working directory,
extra runtime roots and instruction-source metadata. It then queries the skill
inventory for the exact workspace and the thread's MCP inventory. A successful
inventory check requires no skill scan errors, zero enabled skills, and no MCP
tools, resources or resource templates. Every returned MCP server must report
`disabled`; an empty server list is also acceptable. A disconnected, failed,
unknown or partially paginated inventory is not equivalent to disabled.
Six synthetic command checks independently verify workspace access, protected
subtree denial and deliberately permitted unprotected sibling reads.

Important compatibility details:

- Use the exact skill path reported by the runtime. Some versions require the
  `SKILL.md` path, even though the configuration reference describes a directory.
  The inventory must confirm zero enabled skills; requested settings alone do
  not pass the gate.
- Configured, disabled MCP entries can remain in the status list. Count enabled
  capabilities and inspect runtime state, not just the number of servers.
- `disabledPluginIds` in a thread response is not enforcement evidence. Some
  app-server schemas explicitly state that this field does not filter tools.
- Config responses can exceed 1 MiB. This diagnostic allows at most 16 MiB of
  JSON characters per response; the shared command probe retains its 1 MiB
  limit. Oversized responses fail explicitly rather than silently timing out.
- Missing, rejected or changed fields fail closed. There is no automatic
  broad-permission retry, global settings write or sandbox ACL modification.

Only aggregate capability counts, booleans and digests enter the private report;
raw config, credentials, skill text, server endpoints and thread IDs do not.
Every invocation uses a fresh private directory. The exact new thread is
unsubscribed and both owned child processes are closed. A cleanup failure
prevents successful status. Keep failed runs as well as successful runs.

Exit 0 and `preflight_passed_not_model_verified` mean only that the metadata,
inventory and synthetic command checks passed. Actual model tool selection,
input assembly, evaluator placement, inherited instruction text, network
enforcement and all production/resume paths are **not verified**. In particular,
the command boundary still permits reads outside the denied subtree. Both
`production_turn_isolation_verified` and `ready_for_blind_efficacy_study` remain
false, even after a successful preflight. Do not describe this as a blinded
efficacy result or a production sandbox guarantee.

See the [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
alongside the schema generated by the exact installed app-server version.
