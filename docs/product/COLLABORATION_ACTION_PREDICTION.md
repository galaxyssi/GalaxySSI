# Action Prediction And Feedback

Collaborative-evolution increment 7 extends the existing scoped research workspace and durable
task DAG. It adds an explicit environment/task model, compared action forecasts, observed errors
and a correction path. It does not train a neural world model or run an idle background model.

## Design Basis

[DreamerV3](https://www.nature.com/articles/s41586-025-08744-2) demonstrates the value of learned
environment models and imagined consequences in its evaluated control domains. Here the transferable
design principle is to separate model, imagined outcomes and observed feedback. GalaxySSI does not
implement Dreamer, inherit its benchmark results, or claim equivalent world-model learning.

[U-Calibration](https://proceedings.mlr.press/v195/kleinberg23a.html) motivates evaluating forecasts
in relation to decisions, rather than treating a single scoring rule as sufficient. This increment
reports Brier scores for observable binary events, missingness and selected-sample scope. It does
not claim a low Brier score proves calibration, low decision regret or good causal identification.

## Records And Execution

1. `task_environment_model` preserves the original goal/criterion, environment, applicability,
   refresh conditions, causal hypotheses, confounders and state classified as observed, assumed
   or unknown. Observed state cites original evidence with full read coverage. Actions name their
   preconditions, expected transitions, side effects, reversibility and authority requirements.
   A defer/no-action alternative must remain available.
2. `action_forecast` registers common measurable events, probabilities for every action, declared
   utility and uncertainty before acting. The host recomputes linear expected utility. The member
   chooses the action and explains risk/resource/information tradeoffs; maximizing a score is not
   forced by code. Event probabilities are marginals, not a joint distribution or causal guarantee.
3. Existing live and next-round planners admit `prediction_work:{forecast:<exact ref>}`. Goal,
   criterion, run, turn, work ID and executing person must match. A forecast freshness deadline is
   agent-selected for environmental validity, not a fixed research timeout. New expired assignments
   request replanning. Admitted work retains its binding across recovery; workers are instructed to
   recheck conditions and permissions before new external actions. This is not a per-tool sandbox
   gate and does not override the existing tool authorization or side-effect recovery mechanisms.
4. Authorized tools produce original `galaxyssi.action-outcome.v1` reports, carrying exact forecast,
   model, action, work and environment identities. JSON text in Desktop stdout wrappers is supported.
   `prediction_outcome` checks original source, run/turn/executor and chronology, evaluates the
   registered fields, and computes binary Brier errors itself. Wrong forecasts remain visible.
   Failed tools/missing fields are unobserved, not false events. Only the chosen action is observed;
   unchosen alternatives are not post-hoc counterfactual measurements. Late observations retain a
   validity flag and do not silently disappear.
5. `prediction_calibration` aggregates exact-model outcomes, rejects repeated snapshots of the same
   forecast, and preserves event coverage, selected-sample scope and selection bias. Members can
   publish a corrected model with `previous_model`, the actual feedback, changed assumptions,
   reasoning and a new discriminating test. That correction is not automatically considered better.
   Historical predecessor/feedback links are preserved without making a corrected model depend on
   old environmental facts remaining current. Its new active basis must be current before dispatch.

All four record types are immutable. A correction or changed action uses a new record/work ID.
Existing encrypted storage, paging, access revocation, blind work isolation, delete-group cleanup,
pause/stop and execution recovery are reused. No second scheduler, network traffic while idle,
fixed research-step limit or automatic spending authority is introduced. Ordinary work takes a
no-workspace-I/O fast path. There are no UI, Desktop runtime or Watch changes in this increment.

## What Remains Unproven

The host verifies arithmetic and original report provenance, not whether the tool/harness measures
the real phenomenon correctly. Report-to-work association includes tool-returned work/action IDs;
it is not independent certification of a harness or a new runtime attestation mechanism. An Agent
can still choose poor events, utilities or biased examples. Independent harness review, held-out
future actions, representative environments, temporal drift tests and real-model decision-quality
evaluation are necessary. A model correction is a preserved hypothesis until these checks support it.

The local synthetic tests demonstrate actual deterministic computation, prediction-error scoring,
immutable admission, correction lineage and persistence. They do not establish learned general
world knowledge, better real-world choices, scientific discovery or physical experiment success.
The original goal acceptance contract remains authoritative.
