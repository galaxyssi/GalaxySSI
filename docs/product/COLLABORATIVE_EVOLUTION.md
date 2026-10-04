# Collaborative Evolution

## Purpose

Make collaborative improvement inspectable and reusable: discover a gap, choose what to learn,
propose competing explanations, predict consequences, register a discriminating experiment,
observe execution, compare against a baseline, preserve failures, and retain only a scoped lesson.
Innovation is a first-class object, not an adjective in the coordinator's final answer.

This is an extension of the current research workspace and goal-driven work graph, not a new
background scheduler or a second model loop. It does not train model weights, guarantee original
discoveries, establish scientific truth, or automatically deploy self-written tools.

## Architecture

```text
Original user goal and preserved acceptance criteria
  -> Existing goal controller / incremental coordinator
     -> Capability gap and learning-priority proposal
     -> Independent innovation proposals
     -> Peer challenge / cross-domain combination / predictions
     -> Immutable preregistered comparative experiment
     -> Existing authorized cloud / native / Desktop executor
     -> Original scoped tool-evidence ledger
     -> Host recomputation of measured comparisons
     -> Independent lesson review and regression gate
  -> Versioned shared workspace, recallable in later group tasks
```

The coordinator still owns *which* work is useful. The host owns identity, authorization,
version consistency, atomic publication, evidence integrity and arithmetic. The existing DAG
handles dependencies, concurrency, pause/stop and durable continuation. No new polling loop,
broker control traffic, unlimited token budget or fixed research-stage count is introduced.

### Record Types

| Workspace kind | Required meaning | Host status |
| --- | --- | --- |
| `capability_gap` | Observed symptom, proposed gap category, competing learning options, expected gain/cost/relevance, chosen option and verification | Diagnosis and priority proposed |
| `innovation` | Hypothesis, mechanism, prior-art difference and search scope, falsifier, predictions, alternatives, conditions and risks | Hypothesis unverified |
| `experiment_plan` | Exact innovation and baseline revisions, prediction, method, source tool, environment, budget and target/regression/transfer cases | Preregistered, not executed |
| `experiment_result` | Exact plan, original tool receipts, interpretation and limitations | Host-derived incomplete/regressed/inconclusive/measured improvement |
| `capability_lesson` | Exact result, retain/reject/revise decision, applicability, negative conditions, procedure, transfer check and rollback baseline | Eligible for scoped reuse, or negative experience |

Gap and innovation authors can revise their own records; peers create linked alternatives.
Plans, results and lessons are immutable. A changed target or criterion needs a new plan, not
an overwritten success standard. Original versions and negative findings remain accessible.
Late results for superseded targets remain publishable as historical measurements, but cannot
authorize retention of the new version; negative lessons can still preserve the old experiment.
Transfer needs a preserved parent; combination needs distinct parents and retains contributor
lineage. A contributor cannot become an independent retention reviewer by combining their work
under a new author.

### Innovation And Measurement

1. Investigate prior art and contradictory evidence. `searched_scope_only` requires original
   returned source observations and page coverage; it never means globally novel.
2. State a falsifiable prediction and plausible alternative explanations. Keep competing ideas
   separate until a justified combination names its parents.
3. Preserve the baseline implementation/control, then register the experiment before trials.
4. Execute a suitable authorized test harness. It emits `galaxyssi.experiment-measurements.v1`
   with the plan hash, environment, budget unit, exact variant revision hash, case, repetition,
   metric, value and resource usage. The report can be a JSON object or exact JSON text inside
   the tool's original structured output. Desktop stdout wrappers are selectable with a JSON pointer.
5. The host resolves original receipts, checks execution source/time/version bindings, refuses
   duplicate or unregistered samples, applies the same budget ceiling, and recomputes averages
   and signed gains. Partial data is retained as incomplete. No model-authored aggregate is used.
6. Positive target gain plus passing regression cases is required for retention eligibility.
   A separate member must inspect every original report before retaining the scoped procedure.

This verifies *arithmetic on observed reports*. A buggy or fabricated test harness can still emit
misleading numbers. Harness review, representative test selection, calibration, statistical power,
domain validators and external replication remain essential. A synthetic test passing here does
not prove a real model became smarter. Existing scientific/physical goal-acceptance gates are
unchanged; simulation never becomes a performed physical experiment.

### Learning And Transfer

Each new research dispatch receives a bounded directory of accessible evolution records, pinned
to its durable goal contract. A recovered dispatch keeps its original context. Members can page
through further records using `collaboration_recall` (cloud/Desktop) or the phone native recall:

- `mode=evolution`: scoped directory, `cursor` pagination.
- `mode=evolution_rules`: the full typed schemas, `offset` pagination.
- `mode=workspace`: complete versioned originals.
- `mode=evidence`: complete original observations, with host-served page coverage.

Full schemas are fetched on demand, not added to every model prompt. The directory is an atomic
index in the existing encrypted workspace; it is not a whole-history scan. Blind current-round
work stays isolated, revoked members lose recall access, and deleting a group removes its index.
Changed referenced versions mark directory entries historical and requiring revalidation.

Scope is the authorized collaboration group, including later tasks in that group. There is no
automatic cross-group or private-memory disclosure. `eligible_for_scoped_reuse` is a recommendation
to retrieve and evaluate a procedure. It is not a globally installed Skill, changed model route,
code deployment, permission grant or automatic tool registration. Existing Skill installation,
sandbox and self-evolution review gates remain the only execution authorities.

## Mapping The Eleven Goals

| Goal | This increment | Still requires empirical work |
| --- | --- | --- |
| Discover gaps | Typed symptoms/categories and evidence-linked workspace | Quality of model diagnosis |
| Choose learning | Explicit alternatives, expected gain, cost, relevance and chosen action | Calibrated value-of-information estimation |
| Learn from tasks | Durable positive/negative lessons with provenance | Automatic packaging into reviewed Skills |
| Transfer experience | Parent lineage, applicability and explicit transfer cases | Broad cross-domain benchmarks |
| Propose/verify innovation | First-class hypotheses, falsifiers, prior-art scope, preregistration and measured comparisons | Real novel discoveries, domain-specific validation |
| Team invention | Independent proposals, peer work and combination lineage on the existing DAG | Same-budget team superiority |
| Predict before action | Predictions bound to registered tests and observed outcomes | A calibrated learned world model |
| Develop tools | Plan sandboxed implementation/testing with artifact versions and existing executors | Autonomous safe tool packaging and deployment approval |
| Improve workflows | Methods can be compared and stored as reusable scoped procedures | Sustained gains on real workloads |
| Prevent regression | Baseline preservation, regression cases and independent retention | Broad long-term retention and automated runtime rollback |
| Self-improvement research | The same goal controller can investigate an authorized improvement objective through this contract | Long-duration model-backed campaigns and external replication |

## Runtime Coverage

The common Android research prompt and publication validator apply to managed cloud and Desktop
members. The Desktop Codex recall bridge advertises both new read-only modes. Native recall uses
the same scoped handler. Provider adapters without original tool evidence can propose plans and
lessons but cannot claim measured retention. This change does not pretend every provider has the
same tool or observation capability.

There is no new UI, automatic model call when idle, or restart of existing protein research.

## Verification

Automated tests cover persistence, replay, atomic index writes, independent-work isolation,
cross-group denial, schema feedback, novelty claims, combination lineage, preregistration,
source/plan/version/environment/budget mismatch, incomplete/duplicate samples, regressions,
self-review rejection, page coverage and shared Desktop measurement interpretation.
Device fixtures use local synthetic reports only; they are not real-model improvement evidence.
