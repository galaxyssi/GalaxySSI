# Evidence-Driven Capability Gap Diagnosis

## Scope

This is item 1 of the collaborative evolution program, built on the shared evolution
workspace. A failed call is a symptom, not proof that an agent lacks knowledge. Network,
authorization, tool configuration, missing evidence and an inadequate method can look alike.
The agent must be able to distinguish them using evidence rather than repeat an arbitrary retry.

The implementation borrows two principles, not entire frameworks:

- [Reflexion](https://arxiv.org/abs/2303.11366): retain useful feedback across attempts.
- [CRITIC](https://arxiv.org/abs/2305.11738): ground correction in external tool observations.

Neither paper proves that this implementation improves a model. Model-backed diagnosis
accuracy, unnecessary retries, successful recovery, latency and cost need separate evaluation.

## Runtime

1. The existing cloud/native/Desktop evidence ledger stores the byte-exact original output.
2. Failed observations receive a small atomic index entry. Receipts derive `host_problem`
   from original fields, with source paths and `cause=not_diagnosed`. Raw messages, credentials
   and full tool inputs are not duplicated into this directory.
3. `collaboration_recall mode=problems` exposes a paginated, group/assignment-scoped directory.
   The next dispatch receives a bounded snapshot pinned with its original goal contract.
   A recovered dispatch retains its original snapshot; explicit recall can fetch newer records.
4. The agent proposes a `capability_gap`, alternative causes, a learning option and a probe.
   It distinguishes knowledge/tool/method/verification/coordination from environment,
   authorization and unknown causes. The program does not choose the diagnosis or retry policy.
5. An immutable `capability_diagnosis` binds the exact gap revision, actual source observations,
   selected hypothesis/learning option, uncertainty and expected observable fields.
6. The existing work DAG dispatches an authorized probe. A `capability_probe` cites the original
   later tool result. The host checks source, time, identity, digest and full-source read coverage,
   and compares registered expected scalar values against the original JSON output.
7. Missing fields, partial coverage, unchanged failure output and negative results are retained.
   The member can change its hypothesis, request peer assistance or continue unaffected work.
   New predictions need a new diagnosis; existing evidence must not be retrofitted to pass a test.

Probe feedback distinguishes byte-identical output from repeated status/error-code signals
whose request IDs or timestamps changed. Equal signals are only a coarse observation, not proof
that the environment, cause or information gain is unchanged.

No fixed attempt count selects a recovery strategy. No new scheduler, model polling,
permission grant, side-effect execution, UI or broker message type is introduced.

## Contracts

`capability_diagnosis` and `capability_probe` are immutable evolution workspace kinds. They
use the existing atomic publication journal, encrypted storage, versioned history, read coverage
and blind-round isolation. Complete schemas are available through `mode=evolution_rules`.

Each expectation names an exact executor origin/tool, a JSON pointer and a scalar expected
value. Missing differs from explicit null; numeric values compare numerically without string
coercion. An optional `report_pointer` selects a JSON object or exact JSON text (including
Desktop's `original_json` wrapper); the field pointer traverses that parsed report. Neither
pointer executes code or interprets arbitrary prose.
The agent chooses what would discriminate its explanations; the host enforces what was declared.
This comparator is not a general domain or scientific validator.

Host states are `diagnosis_proposed`, `probe_incomplete`, `probe_expectations_met` and
`probe_expectations_not_met`. Even a matching probe keeps `cause_verified=false` and
`gap_resolved=false`: it shows an observed prediction, not a proven cause or learned capability.
The agent must interpret confounders and can register stronger tests. Retaining a reusable
improvement still requires the experiment, regression and independent-review contract.
Original user goal acceptance remains separate and unchanged.

Changed gap revisions mark earlier diagnoses/probes historical and requiring revalidation.
The failed original remains in the directory as history after recovery; it is not a live task
status or an instruction to retry. Old observations remain readable through normal evidence
recall. Pre-existing failure rows are indexed only if replayed, avoiding a startup migration
or full database scan. A directory with no results does not mean there are no capability gaps.

## Failure Boundaries

- Original observations and the failure index commit together; storage failure cannot expose
  an index entry without its original. Completed effects are not rerun to obtain a receipt.
- Replay preserves original bytes and hashes, including after index reconstruction.
- A peer cannot see another member's blind same-round observations without a dependency.
- A model cannot replace original evidence with its own assessment or a recall receipt.
- A probe cannot reuse the pre-diagnosis symptom or change its registered source.
- A failed probe remains publishable evidence; it is not rejected because it disproves the idea.
- Publication format failures retain their existing precise feedback and assistance path.
- Whole-provider failures without a tool observation remain in existing dependency/recovery
  feedback, not fabricated as tool receipts. This directory is not a complete incident monitor.
- Permissions and unavailable physical resources remain explicit constraints. Simulation can
  test a hypothesis but cannot certify a performed physical experiment.

## Program Progress

The shared contract is PR #3365. Each of the eleven requested capabilities requires its own
integration and verification increment; the shared contract is not completion of all eleven.
This increment addresses observed capability-gap diagnosis. Learning prioritization, reviewed
Skill packaging, broad transfer, innovation campaigns, team synthesis, calibrated prediction,
tool development, workflow optimization, retention/rollback and self-improvement orchestration
remain subsequent increments with separate PRs.
