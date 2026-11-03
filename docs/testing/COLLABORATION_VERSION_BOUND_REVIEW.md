# Version-bound interim review

## Purpose

An author can publish an immutable artifact before its entire assignment
finishes. The coordinator can now decide that an existing, unadmitted
independent review has sufficient published inputs and replace its
whole-producer wait with those exact versions. This avoids requiring a
duplicate review solely to consume an interim artifact.

This is a general collaboration capability, not a fixed research pipeline,
automatic acceptance rule or a forced review timer. The model still chooses
whether to wait, bind published inputs or propose a genuinely distinct check.

## Contract

The incremental `galaxyssi.work-expansion.v1` object accepts optional
`rebind_reviews` alongside its existing `work` array:

```json
{
  "format": "galaxyssi.work-expansion.v1",
  "summary": "The frozen candidate is ready for its independent check.",
  "work": [],
  "rebind_reviews": [{
    "work_id": "review-candidate",
    "expected_revision": 0,
    "reason": "The published source and test contract cover this check.",
    "inputs": [{
      "dependency": "produce-candidate",
      "uses_milestones": ["<exact host-issued milestone token>"]
    }]
  }]
}
```

`input_revision` is exposed in the coordinator inventory. An accepted change
increments it and persists the previous revision, coordinator node, reason,
replaced dependencies and tokens in the same graph checkpoint. Replay of the
already applied coordinator result is idempotent. A stale revision is an
explicit validation failure, not an invitation to silently overwrite a plan.

Only existing independent `VERIFY` or `CHALLENGE` work is eligible. Every
replaced dependency must be a current required input; the milestone must
belong to that exact producer node. Review subjects require another author.
An explicitly declared supporting prerequisite, such as the reviewer's frozen
test dataset, may also be bound without waiting for its entire report. The host
derives the role from the existing assignment; rebinding cannot relabel a subject.
Unpublished or insufficient prerequisites remain. Host-managed candidate,
learning and other evaluation lifecycles retain their existing transitions.

The reviewer, provider/model selection, assignment, task identity, dependency
success policy and original acceptance criteria do not change. An amendment
does not remove, cancel or complete the producer. The review is explicitly
scoped to pinned versions, not future revisions or the whole producer task.
Missing inputs must still be reported, not treated as a successful check.

For newly scheduled version-based work, `uses_milestones` contains all required
versions. Optional `review_milestones` selects the review subjects from that
set; all tokens remain subjects when the field is absent. This mirrors the
existing distinction between `depends_on` and `review_targets`. A review must
retain at least one known, differently authored subject. Supporting data do
not bypass grants, hash/version binding, or later acceptance checks. Explicit
input roles survive serialization and appear in the reviewer's scoped context.

Coordinator inventory shows each unfinished dependency's role and available
published tokens. Publication is not a semantic readiness verdict. The model
must still decide whether those versions suffice; the host does not auto-release
waits or assert scientific independence. Final delivery still waits for the
original producer assignments and reviews. No concurrency limit is increased.

## Scheduler And Persistence

For expandable research graphs, dependency-waiting nodes no longer create
execution jobs before their dependencies settle. Before launching an eligible
job, the runtime persists a `subagent.child.admitted` marker, including jobs
that may then wait for an execution permit. The public state remains queued
until execution starts; no new UI is introduced.

The serial expansion callback receives the scheduler's admitted/completed
IDs. The durable store also checks admission, running and terminal events.
Both must establish that a target has not been admitted. A missing admission
snapshot fails closed. An admission marker is retained per child through
event-tail compaction and process restoration.

The low-level runtime permits only a one-version increment with dependency
removal for unadmitted work. It rejects changes to context, provenance,
execution lane, policy, identity, or admitted children. The App supplies the
exact-version grants replacing those dependencies. Persistence precedes
dispatch; a persistence failure interrupts rather than starting a partially
updated review. No late result from an already admitted task can be rebound
to a different input version.

User pause defers the amendment without consuming its coordinator result.
Running work is not preempted. Existing cancellation, terminal-dependency,
completion-barrier and recovery semantics remain covered by regressions.

## Verification Scope

Unit fixtures cover exact-version access, preservation of independent probe
dependencies, rejection of self-review/unknown producer/stale revision,
atomic rejection, pause, codec restoration, admitted permit waiters and
failed admission persistence. An admission remains protected after more than
1,000 subsequent queued observations compact the event tail. Existing expansion, ordered-admission,
cancellation and team integration suites are included.

`CollaborationReviewRebindingDeviceTest` uses dedicated local encrypted
fixtures, no model requests or external actions. It verifies that a review
starts before the producer ends, cannot read a later version and runs once.
Its `reviewBindingPhase=seed|recover|cleanup` case supports a real process
boundary between persistence and dispatch. Production conversations are not
used as fixture storage.

### Recorded validation (2026-10-08)

- Android `1.4.97` / `1182`: debug APK and instrumentation APK compiled.
- Selected JVM regressions: 250 tests in 22 classes, zero failures or skips.
- Galaxy S20 Ultra (`SM-G9880`): five local device cases passed, including
  exact-version early review, existing live expansion, encrypted recovery,
  pause/stop retention and dispatch-boundary retention.
- Separate-process seed and recovery both passed with different process IDs,
  with an explicit App force-stop between phases. Pinned inputs and history
  survived, and each remaining fixture assignment executed exactly once.
- Repository checks and whitespace checks passed.

The first new device fixture omitted its persisted group membership and was
correctly denied by the workspace authorization check. The fixture now creates
and cleans up its own group and members; production authorization was not
relaxed. These are local synthetic checks, not a real-model trial.

These checks establish host behavior, not model uptake or collaborative
intelligence. A fresh real-model trial is still required to establish whether
the coordinator actually selects useful bindings and whether independent
review improves, confirms or rejects a candidate. Equal-budget team gain,
transfer and retention require their own experiments. Private research data
and manuscript material are not included in this repository.

### Frozen prerequisite validation (Android 1.4.98 / 1183)

- Final JVM run: 246 tests in 18 classes, zero failures, errors or skips.
  Coverage includes review input roles, sequential milestone arrival, retained
  whole-assignment prerequisites, self-review rejection, typed token validation,
  deduplication signatures, admission, pause, and scheduler expansion.
- Debug APK and instrumentation APK built and replacement-installed on a
  Galaxy S20 Ultra (`SM-G9880`); installed version confirmed as 1.4.98 / 1183.
- Two local scheduler cases passed: retain an unpublished probe prerequisite;
  and start the same review from both frozen inputs while both producers continue.
  Later candidate and dataset versions were actually published before the read
  assertions and remained inaccessible to the pinned review. Final delivery
  remained behind the original producers, and each fixture task ran once.
- Separate-process seed and recovery passed with `reviewBindingFrozenProbe=true`
  and an explicit App force-stop between phases. Process IDs differed; both
  pinned versions and their subject/prerequisite roles survived. Fixture data
  were cleaned up after recovery. This is process recovery, not a device reboot
  or a Doze/network test.
- Repository structure, source-size, i18n and whitespace checks passed.

These device tests use synthetic local workers, not model-generated plans.
They do not establish autonomous model uptake, independent scientific validity,
team superiority, transfer, or long-term retention. No real research task was
resumed, and this change does not alter UI, model selection, runtime concurrency,
Desktop code, or goal acceptance requirements.
