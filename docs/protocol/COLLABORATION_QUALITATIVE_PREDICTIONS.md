# Qualitative research predictions

`action_forecast` supports `prediction_mode: "qualitative"` when numeric
probabilities or utilities are not justified. Omitting the mode preserves the
existing probabilistic contract. This mode uses the same durable workspace,
original observations, `prediction_work` admission, goal criteria and scheduler.
It does not add another model, execution loop or automatic retry policy.

## Forecast

Keep the existing model, action, executor, work, source, validity, event and
rationale fields. Omit `utility_unit`, event utilities and choice probabilities.
For each registered action, provide `expectations` covering exactly all events:

```json
{
  "prediction_mode": "qualitative",
  "choices": [
    {
      "action_id": "probe",
      "reasoning": "Measure the disputed behavior",
      "uncertainty": "No calibrated probability model",
      "resources": "One local measurement",
      "risk": "Read-only fixture",
      "expectations": {"ordered": "expected"}
    },
    {
      "action_id": "defer",
      "reasoning": "No new observation",
      "uncertainty": "Unmeasured",
      "resources": "None",
      "risk": "Question remains open",
      "expectations": {"ordered": "unknown"}
    }
  ]
}
```

This is a fragment, not a complete publication. An `expected` label predicts
that the event's registered field equals its registered scalar value;
`not_expected` predicts inequality. `unknown` asserts neither. These labels are
testable claims, not certainty or calibrated confidence.

## Competing explanations

An optional `hypothesis_test` carries `question`, `assumptions`,
`prediction_basis`, `misspecification_check`, distinct `{id, claim}` hypotheses,
registered `event_ids`, and a `predictions[action][hypothesis][event]` matrix with
the same three labels. Every action, including defer, covers the same hypotheses
and events. There are no priors, likelihoods, posterior carryover or fabricated
information-gain estimates.

The host reports the events on which explicit predictions disagree. This is
not a score of experiment usefulness. An uninformative experiment remains
permitted; the planner decides whether it serves another goal or whether to
propose a different measurement or problem representation.

## Observation and correction

Use the existing `galaxyssi.action-outcome.v1` report and `prediction_outcome`.
Run, turn, executor, source, forecast, model, action, work and environment identity
checks remain in force. A hypothesis test must use one original measurement,
not a favorable combination of fields from different trials.

Each hypothesis retains matching, contradictory and unresolved event IDs. A
valid contradiction remains visible even if another field is unresolved.
Missing fields, tool failures, observations outside declared validity and unknown
expectations do not establish scientific contradiction or support. All proposed
explanations can be contradicted; the system does not force a winner.

Qualitative outcomes keep numeric probability scores, utility, posterior and
information gain null. `observed_events` counts obtained fields; `scored_events`
is zero because there is no Brier score. `prediction_calibration` rejects these
outcomes rather than pooling them as perfect numerical forecasts.

The coordinator can cite exact outcome feedback in a new environment model and
admit a new forecast/work item. Existing observed workflow inputs can also use
the original receipt fields to choose later actual work. The comparison itself
does not auto-select that work, prove causality or certify an improved method.

## Persistence and scope

Admission carries the mode, expectations and hypothesis comparison into the
worker context. Existing immutable work IDs and claims govern replay. The
increment preserves model routing, existing probabilistic forecasts, ordinary
direct work, pause/stop behavior, source access and side-effect dependencies.

Tests exercise contract validation, original measurement feedback, model
correction, real scheduler admission and store reopening using synthetic local
data. They are software evidence, not autonomous scientific discovery or proof
of capability growth.
