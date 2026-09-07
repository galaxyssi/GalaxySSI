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

The HTTP read timeout and 2 MiB response envelope bound one inference transport,
not campaign lifetime or task count. Audit entries contain public decision reasons
or error types, not full prompts or raw failed HTTP bodies, and stay in local state.
Model absence yields `local_model_unavailable` without changing the failed node.

## Evidence and limitations

Tests cover the observation -> model decision -> DAG update -> child dispatch
sequence, new dependency proposals, unchanged-child retries, disabled behavior,
stale replies after pause, graph cycles, policy rejection, restart after a saved
decision, wait deduplication, and refusal to fabricate completion.

Real loopback HTTP tests verify request content, proxy bypass, redirect refusal,
tool refusal, and remote-endpoint rejection. Model decisions in those tests are
deterministic fixtures, not genuine LLM inference. No usable model endpoint was
found in the default Desktop configuration during this stage, and no local model
was downloaded or installed. Genuine local-model planning quality, initial goal
decomposition, model-selected completion evidence, UI presentation, and full
provider-driven multi-PR campaign acceptance remain to be verified or completed.
