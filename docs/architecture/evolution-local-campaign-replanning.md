# Local model campaign replanning

Desktop 1.0.46 connects failed durable evolution campaigns to a background planning
service. It addresses the missing transition from an observed DAG failure to a
model-authored retry or dependency revision. It does not mark the overall goal
complete or replace the remaining real-provider and long-duration acceptance.

## Runtime flow

1. The runtime starts/stops the planner alongside the existing scheduler and CI
   observer. Disabled evolution or disabled automatic task starting sends nothing.
2. The planner examines auto-start campaigns with observed failed nodes. A graph
   fingerprint identifies the exact objective, revision, task states and evidence.
3. A tool-free local model receives that graph plus relevant proposal scope and
   acceptance criteria. Returned JSON can choose `retry`, `revise`, or `wait`.
4. The decision is persisted before application. A restarted service can reuse it
   without requesting the same decision again.
5. Under campaign operation ownership, the reducer verifies that the graph still
   matches the observed fingerprint. Pause, revision, or other state changes make
   the old answer inapplicable.
6. New proposals undergo existing source policy checks; the full graph is validated
   before persistence. New proposal identities are deterministic and use
   `campaign_reserved`, preventing ordinary proposal scheduling from duplicating
   their dispatch. Existing running/completed task identities remain immutable.
7. The normal campaign scheduler dispatches revised work. This planner does not
   directly execute commands, publish code, merge PRs, or declare a goal finished.

## Privacy and performance

The user requires private self-evolution observations to remain local. Planning
therefore uses the configured Desktop local model only. The endpoint must be a
literal loopback IP (or localhost mapped to 127.0.0.1); a model must be configured.
Ollama generate/chat paths map to its existing OpenAI-compatible chat endpoint.

The client uses a direct HTTP(S) connection with normal certificate verification,
ignores proxy environment variables, does not follow redirects, sends no tools,
rejects tool-call replies, and never falls back to a cloud or CLI provider. This
does not attest whether an independently configured local server itself forwards
requests elsewhere; operators must use a genuine local model server.

There is one local inference operation at a time per planner service. It runs
outside the UI and outside the campaign mutation lock, so user pause/revision can
proceed while inference is running. A separate OS owner prevents two services from
planning the same campaign simultaneously. Successful `wait` observations are not
re-inferred until the graph changes. Transport/format errors receive a retry delay,
not a terminal task result. There is no aggregate action or revision budget.

Starting with Desktop 1.0.47, the client requests SSE streaming. The 60-second
socket inactivity timeout does not impose a total generation deadline while
events keep arriving. Intermediate reasoning is consumed but not retained;
only final content is assembled. The existing 2 MiB wire response envelope counts
all events, including ignored reasoning. Truncated streams, tool calls, abnormal
finish reasons, and missing completion markers cannot become decisions. Servers
that return a normal JSON response remain supported; they must return before the
socket inactivity timeout because they expose no progress. Audit entries contain public decision reasons
or error types, not full prompts or raw failed HTTP bodies, and stay in local state.
Model absence yields `local_model_unavailable` without changing the failed node.

## Validation feedback

Desktop 1.0.48 persists a structured `validation_feedback` observation when JSON
parsing or DAG validation rejects a model-authored decision. The next inference
for the same graph receives the validation detail and prior answer as untrusted
evidence, together with the accepted operation shapes. The model still chooses
the action; the framework does not repair or rewrite its answer on its behalf.

The latest prior answer is limited to 8192 characters and validation detail to
2048 characters, with truncation marked explicitly. This bounds diagnostic
context, not task count or campaign lifetime. Feedback survives service restart
and transient transport failures, but is dropped when the graph fingerprint
changes or a valid decision is applied. Infrastructure errors are not falsely
presented as decision validation failures. The existing retry delay remains in
effect; no aggregate action budget was introduced.

Tests cover malformed JSON locations, rejected graph shape, dependency cycles,
corrected decisions after restart, intervening network failures, stale feedback,
and bounded diagnostic context. The opt-in acceptance harness can observe several
real-model decisions using `--max-decisions`; that bound applies only to the test
invocation, not the runtime Agent loop.

Real Qwen3-1.7B feedback acceptance on 2026-09-07 preserved the failed graph
through every invalid answer. The initial three-decision run still returned
invalid nested operation objects. After clarifying top-level field types, a
fresh run returned a `retry` in 53.468 seconds, then changed to `revise` after
receiving the cancelled-child validation error (113.453 seconds). The revision
incorrectly introduced new proposals under existing node IDs and was rejected.
This demonstrates real validation-observation feedback influencing model action,
not successful cancelled-child replacement. That quality acceptance remains open;
no code, PR or completed goal is claimed by these controlled child scenarios.

## Evidence and limitations

Tests cover the observation -> model decision -> DAG update -> child dispatch
sequence, new dependency proposals, unchanged-child retries, disabled behavior,
stale replies after pause, graph cycles, policy rejection, restart after a saved
decision, wait deduplication, and refusal to fabricate completion.

Real loopback HTTP tests verify request content, proxy bypass, redirect refusal,
tool refusal, remote-endpoint rejection, active streams exceeding the socket
timeout, and silent streams still timing out. Their model decisions are fixtures.

An opt-in real-model harness is available at
`tools/testing/run_evolution_local_planner_acceptance.py`. It requires a new
isolated state directory and `--allow-inference`. It uses the production planner,
proposal store and DAG ledger, but controlled child task outcomes. It does not
claim real code development, publication, phone acceptance or complete goal success.

On 2026-09-07, official Qwen3-1.7B Q8_0 and llama.cpp b10839 CPU were installed
outside the repository, with their SHA-256 hashes checked. The test server used
loopback, four threads, one slot and 8192-token context; production Desktop
configuration was unchanged.

- Nonstreaming baseline: failed at 60.03 seconds despite continuing generation.
- Streaming transient failure: valid retry applied in 28.968 seconds; original
  child reused; reopening the planner caused no additional inference.
- Streaming cancelled child: response received after 63.656 seconds, proving
  generation can continue beyond the former wait. Its invalid decision shape was
  rejected without changing the original objective or failed graph.

These single observations are not comparative latency benchmarks: caching and
stochastic generation differ. The cancelled-child case remains a model-quality
failure, not a passing acceptance case. Structured validation feedback was added
in 1.0.48; real-model results must still be evaluated independently. Initial decomposition, model-selected
completion evidence, UI presentation, and full provider-driven multi-PR campaign
acceptance remain incomplete.
