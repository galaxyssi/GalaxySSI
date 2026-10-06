# Numeric Model Replay

## Scope

`numeric_model_cases.v1` is a host-side, side-effect-free computational
validator. It evaluates a saved pure numeric model on an exact set of preserved
input/reference/tolerance cases. It does not execute model-authored code, trust
model-authored scores, certify reference data, or establish generalization.

This is useful for calibration, mathematical model comparison and regression
checks when a pure expression is an appropriate representation. Arbitrary
Python programs, learned model weights and physical experiments need other
execution and validation mechanisms; this adapter does not stand in for them.

## Preserved Contract

A computational criterion must be established before claiming completion:

```json
{
  "id": "registered-cases",
  "requirement": "Verify the saved numeric model on exactly the registered test cases; this does not establish generalization or physical validity.",
  "verification": "computational",
  "evidence_kind": "observed",
  "status": "open",
  "evidence": [],
  "validator": {
    "id": "numeric_model_cases.v1",
    "variables": ["x"],
    "cases": [
      {"id": "positive", "input": {"x": 2}, "expected": 4, "absolute_tolerance": 0.001},
      {"id": "negative", "input": {"x": -3}, "expected": 9, "absolute_tolerance": 0.001}
    ]
  }
}
```

The saved delivery has substantive `body.content` and:

```json
{
  "computation": {
    "validator_id": "numeric_model_cases.v1",
    "model": {"op": "mul", "args": [{"variable": "x"}, {"variable": "x"}]}
  }
}
```

The canonical validator binding participates in the existing goal coverage
hash. Insignificant numeric zeroes (`2.0` versus `2`) normalize before hashing,
so JSON persistence does not invent a changed plan/model. Decimal strings remain
strings; use them when input precision must survive platform JSON parsers.
A continuation cannot replace variables, inputs, references, tolerances
or cases to turn failure into success. Status and model revisions can change;
each revised delivery requires a current independent review. Existing source
requirements, contributor checks, dissent handling and goal coverage remain in
force. The literal scope prevents this adapter from certifying a broader goal.

## Numerical Semantics

- Leaves are `{constant: finiteDecimal}` or `{variable: registeredName}`.
- Unary operators: `neg`, `abs`, `exp`, `expm1`, `log`, `log1p`, `sqrt`, `sin`, `cos`.
  `expm1` and `log1p` preserve small changes that would lose precision through
  subtracting or adding one around an ordinary exponential/logarithm.
- Binary operators: `add`, `sub`, `mul`, `div`, `pow`, `min`, `max`.
- Every argument must be a valid expression object with exact declared fields.
- Evaluation uses finite float64 values and `StrictMath` transcendental
  operations. Every intermediate result must be finite. There is no source
  parser, file access, network, function call or mutable external state.
- Final values are compared with the preserved decimal references and absolute
  tolerances using `BigDecimal`; an authored pass flag or error score is rejected.
- Division by zero, invalid logarithms, overflow and other domain failures remain
  failed cases, including when a later expression would hide the non-finite value.

The host reports case count, failure count, maximum error on finite cases and a
counterexample. A revised model is checked against every original case again.
The report binds both specification and model hashes. It does not prove that the
cases were held out, that fitting was independent, or that references are true.

## Trials Before Completion

Members do not have to claim the goal is achieved to obtain numerical feedback.
The existing cloud/native/remote workspace publication path accepts immutable
`numeric_model_trial` records:

```json
{
  "id": "candidate-check",
  "kind": "numeric_model_trial",
  "title": "Check the proposed response curve",
  "body": {
    "content": "A finite-case check; reference validity remains separate.",
    "numeric_model_trial": {
      "purpose": "Find counterexamples to this candidate",
      "reference_basis": "Describe and cite the actual reference sources",
      "limitations": "Visible cases, not held-out generalization",
      "validator": {"id": "numeric_model_cases.v1", "variables": ["x"], "cases": [
        {"id": "probe", "input": {"x": 2}, "expected": 4, "absolute_tolerance": 0.001}
      ]},
      "computation": {"validator_id": "numeric_model_cases.v1", "model": {
        "op": "mul", "args": [{"variable": "x"}, {"variable": "x"}]
      }}
    }
  },
  "parents": [],
  "observations": []
}
```

The App computes `host_evolution.evaluation`; a valid failed trial is saved with
its actual values/errors, not discarded as invalid publication. Invalid model
syntax remains a different error. All-domain-failure reports have no invented
finite error score. No external runtime or model is called by this adapter.

A new trial can name `previous_trial` and preserve the same reference in
`parents`. Both versions are replayed on exactly the same registered cases.
Changed inputs, references or tolerances cannot be presented as a same-case
improvement. The host lists pass-status improvements/regressions, finite-error
decreases/increases, domain-error recovery/regression and whether the model
changed at all. Progress within a still-failing result remains visible; a domain
error is never replaced by an invented numerical score. It does not collapse a
tradeoff into an improvement claim.
Old failures and disagreements remain in the same scoped immutable workspace.

These trials are discoverable through existing `mode=evolution`/workspace reads;
the full schema is under `mode=evolution_rules, topic=tools`, not copied into
every member prompt. A trial does not establish an immutable goal criterion by
itself and cannot bypass final exact-version review, original-goal coverage or
the independent retention process.

The local execution envelope is 4,096 cases, 64 variables, 2,048 expression nodes,
depth 48 and 2,000,000 case-node evaluations. These bound one local replay's CPU,
memory and stack use; they are not research step, round or lifetime limits.
Larger or unsupported verification requires a suitable plan/adapter without
weakening the original scientific requirements.

## Claim Boundary

`observed` refers to actual host recomputation, not a claim that the inputs came
from a physical experiment. Reference provenance, selection bias, domain coverage,
causal validity, uncertainty and independent holdouts remain separate obligations.
Passing a finite suite is not general accuracy, a learned capability, scientific
novelty, a safe executable release or proof of superintelligence.
