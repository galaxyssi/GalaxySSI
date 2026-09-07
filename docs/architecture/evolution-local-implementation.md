# Private local candidate implementation

Desktop 1.0.51 connects automatic evolution candidates to a local model-driven
file-action loop. Initial goal decomposition alone did not provide this: the
previous implementation selector only advertised external CLI coding agents.

## Routing and ownership

- `auto` and `local-llm` select the private local implementation adapter.
- The same loopback-only, certificate-validating, proxy-bypassing chat client
  used for private planning handles inference. No cloud or external CLI fallback
  is attempted if configuration or inference is unavailable.
- Preflight advertises only this adapter for automatic evolution. `ready` here
  means the local endpoint configuration is valid, not a completed health probe.
- Explicit CLI selection remains available for user-directed implementation;
  this change does not globally remove CLI agents or change ordinary chat.
- The host still owns the isolated worktree, independent gates, review,
  commit, publication, CI observation and recovery. A model summary is not
  evidence that any of those steps passed.

## Action and observation

The model returns one JSON action. The host executes it, then supplies a typed
observation to the next inference. Parse errors identify the model action as the
failed input and explicitly state that no file action ran. File-tool failures
are reported separately. No framework-generated replacement action is inferred
from malformed model output.

Available operations:

- `list`: one directory, 64-entry keyset pages; no whole-repository inventory.
- `read`: UTF-8 source text, 16,384-character pages and the SHA-256 of the exact
  bytes read. The individual text-file envelope is 1 MiB.
- `write`: entire UTF-8 file within the declared task scope, with a matching
  `expected_sha256` or `null` for a new file. Writes replace a flushed temporary
  file atomically and retain the previous permission mode.
- `finish`: implementation or review summary; independent host checks follow.

Source paths are relative and reject traversal, Git metadata, symbolic links,
Windows reparse points and shared hard links. Empty write scope means read-only
review. These are file-tool boundaries inside the host-owned candidate, not a
claim of OS sandboxing against another privileged process.

There is no aggregate action-count or generation-duration budget in this loop.
The rolling model context keeps four action/observation pairs, with large write
contents omitted; the original task stays present and the model can reread
source. This is context management, not durable per-action replay. The existing
host task/attempt and process ownership mechanisms remain responsible for
restarting interrupted candidate attempts.

Cancellation is checked before inference and again before any returned action
is executed. It prevents writes after cancellation but does not yet interrupt
an already-streaming local inference immediately. Tool progress events include
operation and success status, not file contents or private reasoning.

## Validation and remaining scope

Unit tests exercise real temporary file changes, observation feedback, more
than 80 actions, pagination, stale-write rejection, scope and metadata paths,
hard links, permission preservation, cancellation and local-only selection.

`tools/testing/run_local_implementation_acceptance.py` creates a disposable Git
worktree from a one-file fixture and asks a real local model to change its
version. The harness verifies the resulting AST and untouched source checkout;
it does not write the requested edit, execute arbitrary generated Python, or
publish a PR. Supply the test instruction with `--prompt`, including Chinese
instructions when testing the Chinese workflow.

An initial Qwen3 1.7B Q8_0 live run failed: the model returned multiple JSON
actions and subsequently misdiagnosed its own parse failure. The candidate
remained unchanged and acceptance correctly failed. This motivated explicit
parse-versus-file observation stages. Live evidence is retained under
`build/local-implementation-real-qwen3` (not committed).

The follow-up run at `build/local-implementation-real-qwen3-observations`
passed: the real model issued list, read, write, read and finish, producing
`VERSION = "0.1.1"` while the source checkout retained `0.1.0`. The host AST
check passed and only `version.py` changed. Five model calls took 266.876 seconds
in this CPU validation run. This is correctness evidence, not a latency target
or a statistically representative model speed benchmark. No model reply or
candidate edit was replaced by the harness.

This is not yet full goal-to-merged-PR acceptance. The local adapter does not
run arbitrary shell commands, install dependencies, rename/delete files, or
offer a durable file-action journal. Independent host gates still execute tests
and feed failures into subsequent attempts. Large-repository context quality,
real local-model implementation reliability, immediate inference cancellation,
and integration with the full long-running campaign remain acceptance work.
