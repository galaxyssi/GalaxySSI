# Scheduled Final-Goal Verification

## Status

Desktop source 1.1.8 adds scheduled final verification to the existing campaign
planner. This is not deployment qualification: the real-model compound semantic
controls documented in `../testing/CAMPAIGN_COMPLETION_VERIFICATION_20260908.md`
remain unresolved. This change does not enable production evolution, install
an App or replace a running Desktop. It does not claim the complete autonomous
PR/CI-repair objective is finished.

## Lifecycle

An automatically started campaign with an active, nonempty DAG whose retained
children are all completed enters `awaiting_verification`. Previously the planner
ignored this state and final review required an explicit testing harness.

The planner now performs these steps under its existing per-campaign planning
owner, outside the short DAG transition lock:

1. Collect fresh original-goal, immutable candidate, actual publication and
   integrated CI evidence. Re-evaluate literal and preservation constraints;
   old acceptance is not final-goal acceptance.
2. Replay applied removal events from the SQLite ledger. Satisfied-work
   checkpoint retirements require a current proof whose hash, complete source
   observation and command fingerprint match the applied revision. Superseded
   failures and pruned pending work remain plan changes, not satisfaction claims;
   replacement contexts must match their actual predecessor observations.
3. Ask the configured loopback-only verifier to assess the complete original
   objective, not merely generated child criteria. Oversized evidence is rejected
   rather than truncated into a possible pass.
4. Persist the raw response before parsing, then persist the structured verdict.
   Invalid output is diagnostic evidence, not permission to finish or rewrite code.
5. Collect the evidence again, verify unchanged source/graph/provider identity,
   and save a content-addressed final proof.
6. On pass, compare the graph under the existing campaign operation lock and use
   the existing `finish` transition, including its published-outcome checks.
7. On fail or inconclusive, give the graph-bound original-goal assessment to the existing
   planner. It may add missing work using `revise` or wait for evidence; completed
   node identity and content remain immutable. It cannot remove completed tasks
  simply to claim success.

The explicit final-review harness delegates to the same collector, reviewer and
completion transition. It no longer has weaker retired-work or source checks.

No model/GitHub request occurs inside the new final transition wrapper. Existing
published-outcome checks read the persisted CI watch. External evidence is a
fresh, commit-bound observation, not an atomic transaction with GitHub.

## Recovery and Caching

- Final observations live under `campaign-planning/final-<campaign-hash>.json`;
  immutable proofs live under `campaign-planning/final-proofs/<hash>.json`.
- Raw responses and failed observations are archived under
  `campaign-planning/final-attempts/<hash>.json` before retry can replace the
  current record. The hash excludes polling time so identical errors deduplicate.
- Cache identity includes the contract, complete graph, complete evidence and
  verifier URL/model identity. The URL/model digest excludes credentials.
- A saved valid response is reparsed and its evidence is recollected after
  restart. A top-level cached `pass` cannot override the raw assessment.
- A malformed response is retained but is not reused on the next attempt.
- Local model errors and unavailable/changed evidence leave the campaign active
  and apply a 60-second observation retry interval, not a lifetime task budget.
- Unchanged rejected evidence does not repeatedly call the verifier or planner.
  A changed verifier configuration invalidates that cache. Injected internal
  verifier adapters can supply `final_verifier_revision` in planner configuration.
- The original goal and each completed child remain unchanged by failed review.
- Pause, disable and graph changes are checked before applying completion.
- Process death before finish resumes the saved review; death after the ledger
  transition cannot complete the task a second time or restart implementation.

The model identity is an endpoint/model configuration identity, not attestation
of model weights behind a mutable alias. Stronger verifier qualification remains
necessary. Single-call original-goal semantic assessment also remains subject to
the known model errors; deterministic evidence checks do not prove arbitrary
natural-language reasoning.

## Validation Boundaries

Focused tests exercise real SQLite-backed DAG transitions with controlled
provider/verifier observations. Separate subprocess tests use `os._exit(83)` on
both sides of completion and reopen the same persistent state. Evidence-adapter
tests reject stale candidate hashes/contracts, missing PR facts, failed current
CI, violated preservation, missing watches and stale/invalid retirement proofs.
Applied-history tests also exercise repeated failed replacements, pending plan
pruning, missing recovery records and an unapplied archived checkpoint proof.

These tests establish framework mechanics. They are not real-provider semantic
qualification, a new autonomous candidate publication, a device restart test,
or a deployed end-to-end phone/Desktop test. The original real campaign and its
historical evidence were not reset or rewritten to manufacture a passing run.
