# Collaboration Resource Observations

## Purpose

An optional host resource envelope must be visible to the members choosing and
performing work, without turning that envelope into a new goal or acceptance
rule. Ordinary unbounded production tasks receive no default timer, dispatch
cap, step limit, or assumed monetary budget from this mechanism.

`AgentTeamResourceObservation` is a typed, host-created, read-only observation.
It is bound to the group, parent run, turn, task, child, member, dispatch, original
goal and assignment. It is not deserialized from member-authored metadata.

## Meaning

- The pool is shared across the parent run, not reset for each member.
- `phone_delegate_admissions_not_provider_requests` counts phone delegations.
  One such delegation can cause many provider requests and tool actions.
- `cloud_http_request_admissions_not_completed_requests` counts durable App
  request reservations, not proof of successful network requests or billing.
- `parent_execution_window` is distinct from `new_admission_window`. Expiring
  the latter alone does not cancel work that was already admitted.
- Counts and remaining milliseconds are sampled before the current dispatch;
  that dispatch is not yet included. Other members may consume the pool after
  sampling. The snapshot is advisory, not a reservation or continuous feed.
- Unknown billed cost, token allowance and provider request totals remain null.

Existing admission and cancellation mechanisms remain authoritative. A resource
observation grants no permissions, starts no extra calls, and cannot weaken the
goal contract or certify goal completion when resources run out.

## Delivery And Recovery

Research prompts include the observation as a required atomic section for every
role. Closed-book and legacy action prompts use the same host representation.
The shared action bridge delivers it to cloud and remote Desktop adapters without
requiring a second search loop or Desktop-specific prompt replacement.

The optional cloud trial policy reads its existing durable admission ledger at
prompt preparation. Reopened ledgers retain debits; revoked scope fails closed,
and a clock earlier than policy creation reports an unknown time and closed
admission rather than extending the window. Models cannot edit this ledger.

Resource facts are outside the immutable goal/context snapshot. A new preparation
may use a fresh observation while retaining exactly the pinned goal and evidence.
This does not mutate prompts in already-running remote sessions or implement
continuous resource refresh. Other host controllers must supply their own real
observations; the mechanism does not infer missing quotas.

The adaptive remote pilot supplies the same production observation from its
actual monotonic deadline and shared phone-dispatch counter. It verifies that
the exact observation survived in the production prompt, records it in the
dispatch journal, and does not replace assignments, goals, protocols or prompts.

## Validation Boundary

Tests cover ownership, unknown values, immutable observations, durable shared
counts, clock rollback, closure, every research role under context pressure,
preserved goal snapshots, and both adapter prompt paths. These checks establish
resource transparency, not that models allocate resources well. That requires
new real trajectories demonstrating useful experiments, counterexample-driven
revision, retained methods and transfer; neither efficiency nor capability gain
is inferred from the implementation alone.
