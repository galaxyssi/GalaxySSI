# Capability Retention And Version Selection

This is goal 10 of collaborative evolution. It protects previously demonstrated behavior while
agents improve procedures, workflow graphs and executable tools. It does not train model weights,
claim general intelligence, deploy app code or bypass existing runtime permissions.

## Why A Separate Retention Bank

A passing comparison against the last version is insufficient: small tolerated regressions can
accumulate, and an agent can accidentally omit previously successful tasks from the next experiment.
The new immutable `capability_suite` freezes every case from an independently retained lesson:

- Exact dataset artifact and original result reference.
- Metric, direction, required repetitions and tolerance.
- Original measured candidate mean as a fixed anchor.
- Original feasibility thresholds, which a tolerance cannot weaken.
- Domain, environment and accounting scope, with explicit coverage limitations.

Plans referencing `retention_suite` must include the entire bank as regression cases, preserve the
dataset/metric/direction, and cannot reduce repetitions or increase tolerance. New target cases are
added separately. Original reports must bind every dataset hash. The existing evaluator checks both
the current baseline comparison and the original anchor; missing trials are not passes.

Successful follow-up lessons extend the bank. Existing anchors are retained rather than reset to a
slightly worse recent version. All newly demonstrated cases join the bank. Failed and incomplete
experiments remain available as evidence, but cannot authorize promotion.
Directory entries and publication receipts carry only the protected-case count; complete banks
remain in the workspace and are read on demand instead of duplicated in each model context.

## Selection Is An Executed Contract

`capability_channel` is a group-scoped, versioned selection record. Its author can initialize,
promote or roll back using the workspace's existing atomic `base_revision` compare-and-swap.

- Initialization selects an exact implementation tied to a retained lesson and frozen suite.
- Promotion compares against the currently selected innovation, passes its entire bank, receives
  independent retention and extends the bank. Kind and domain cannot silently change.
- Rollback names an exact earlier revision of the same channel. All revisions, failure reports and
  the newest protection bank remain. Older implementations explicitly require revalidation for
  capabilities learned since that version; rollback is not proof those capabilities still work.

Procedures and workflow steps can opt into an exact channel selection in their existing work
declarations. New admissions require the active selection and matching implementation. Already
admitted work retains the exact pinned selection across promotion, pause and checkpoint recovery.
Changing a channel neither restarts completed work nor edits another task's binding.

Executable tools can select a channel through the existing `galaxyssi.runtime.execute` input.
The same saved source, schema, independently reviewed release, runtime fingerprint and permission
gates apply. No parallel executor, background polling loop or global Skill installation is added.
Untyped/experimental work still exists, but it cannot claim the channel's retained status.

## Boundaries

The host provides factual checks; agents choose when to investigate, replan, promote or revert.
There is no failure-count rule that decides their strategy or finishes the user's goal. Approval
and side-effect boundaries remain unchanged. The system does not automatically undo external
actions, remove files or recall sent messages during rollback.

Scope remains the authorized collaboration group. Records survive task changes but are not
silently shared into private memory or other groups. Full schemas are available through existing
paginated evolution-rule recall for both Android and managed remote agents. Ordinary tasks without
these bindings retain the no-workspace-read fast path.

Synthetic arithmetic fixtures establish contract and persistence behavior, not real model quality,
complete production coverage or scientific novelty. The measurement harness/oracle still requires
independent review. Real workload trials, long-duration forgetting curves and held-out evaluation
remain necessary before claiming sustained improvement.

## Research Context

[Anthropic's agent evaluation guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
distinguishes capability growth from regression protection and recommends outcome/trace inspection
with multiple evaluation layers. This design preserves successful cases as regression obligations.

[Gradient Episodic Memory](https://arxiv.org/abs/1706.08840) motivates measuring transfer and forgetting
across tasks. GalaxySSI borrows the retention-testing concern, not GEM's model-training algorithm:
this implementation governs versioned agent methods and evidence, not neural-network optimization.
