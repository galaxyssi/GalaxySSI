# Discriminating action experiments

The optional `hypothesis_test` field extends the existing `action_forecast` and
`prediction_outcome` contracts. It does not add a second planner, executor or
research round limit. The full agent-facing schema is in the `prediction` topic
of `evolution_rules`.

## Capability

An agent can describe competing explanations, observable categorical outcomes
and conditional likelihoods for candidate actions. The host computes expected
information gain for each action. The agent still chooses the action, weighing
information alongside utility, risk, resources and feasibility.

The selected experiment is bound to ordinary goal/live work through
`prediction_work`. Its comparison is included in the immutable worker context.
Original tool observations then produce a posterior over the declared hypotheses.
The next forecast can carry this exact posterior using `prior_outcome`, rather
than resetting beliefs or copying an untraceable confidence score.

For hypotheses H, action a and categorical observation Y, the computation is:

```text
p(y | a) = sum_h p(h) p(y | h, a)
p(h | y, a) = p(h) p(y | h, a) / p(y | a)
EIG(a) = H(p(H)) - sum_y p(y | a) H(p(H | y, a))
```

Information is measured in bits. Arithmetic uses normalized decimal probability
distributions and a floating-point entropy calculation. Prior and likelihood
inputs must each sum to one within 1e-12; action event marginals must agree with
the prior-weighted likelihoods. Mismatches identify the offending action/event.

This is established Bayesian experimental design, not a claimed new algorithm.
See [Foster et al., AISTATS 2020](https://proceedings.mlr.press/v108/foster20a.html)
and [Foster's model-selection explanation](https://ae-foster.github.io/posts/2022/04/14/bed-model-selection.html).

## Evidence and uncertainty

- Categorical events classify one original report field with distinct values.
  All event checks must cite the same original observation.
- Missing or failed observations do not become negative labels. Observations
  outside the registered environment-validity window do not update beliefs.
- An unmodeled category or zero predictive mass preserves an explicit model
  misspecification state, with no invented posterior.
- Individual observations can increase entropy. The host retains that result;
  it does not discard surprises to manufacture apparent learning.
- A posterior is conditional on the declared hypothesis space and likelihoods.
  Neither their calibration nor their completeness is certified.
- Chained forecasts preserve question, hypothesis identities and claims, goal,
  criterion, domain and environment. They derive priors from the exact observed
  posterior. Changed hypotheses require a new comparison.
- Conditional likelihoods must account for previous history and dependence.
  Recorded provenance does not establish statistical independence.
- Hypothesis outcomes can inform innovation opportunities and revised methods.
  They do not bypass controlled method comparisons, independent review or
  conditional-workflow retention checks.

## Tests and remaining evidence

`CollaborationHypothesisTestTest` exercises information/no-information contrasts,
actual local fixture observations, surprising and impossible outcomes, missing
data, stale evidence, mixed-trial rejection, malformed distributions, posterior
carryover, task admission, recovery and scoped persistence. Existing prediction
tests cover the shared tool-report identity and authorization boundaries.

These tests verify a general production mechanism. They do not demonstrate that
a real model autonomously discovers useful hypotheses, accurately estimates
likelihoods, chooses valuable experiments, or improves on unseen tasks. Those
claims require separate prospective studies with externally validated outcomes.
