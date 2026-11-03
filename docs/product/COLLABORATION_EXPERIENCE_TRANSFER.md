# Evidence Bound Experience Transfer

Collaborative evolution increment 4 adapts prior methods and failure experiences to another task or domain. A saved success does not automatically become a validated capability in a new domain. The existing workspace, evidence ledger, goal controller and executors remain the execution path.

## Transfer Lifecycle

1. Recall a scoped `procedure_skill` or `failure_experience` and read the originals.
2. Publish an immutable `transfer_study`: exact source, source and target domains, target task, abstract strategy, invariants, changed assumptions, adaptations, failure conditions, alternatives and calibration artifacts.
3. Publish an `innovation` with origin `transfer`, the study as an exact preserved parent, and the target domain. Proposals can remain untested; experimental promotion requires a typed study.
4. Preregister an `experiment_plan` with the same study, target comparisons, held-out transfer cases, source regressions, exact dataset versions and equal resource ceilings.
5. Run authorized tools. Original measurement reports bind each sample to its preregistered dataset hash, domain, variant, case, repetition, environment and budget.
6. Recompute the comparison on the host. A failed transfer case blocks promotion even if a narrow target improves. Incomplete, negative and superseded results remain accessible.
7. An independent reviewer reads original reports and retains the exact tested adapted method, or rejects/revises it. Publish a new target-domain `procedure_skill` only from a retained lesson.
8. New DAG work supplies `procedure_use.domain` matching that skill's stored domain, explicit inputs and applicability checks. Recovery uses the existing stable work binding.

There are no fixed transfer-round or retry ceilings. Agents choose hypotheses, alternatives, tests and next actions. The host enforces evidence identity and execution integrity, not research strategy.

## Scope And Persistence

Transfer sources, studies, datasets, lessons and procedures use existing group authorization and blind-round isolation. They are available to later authorized tasks in that group, not private conversations or other groups. Original records are immutable except existing gap/innovation and general artifact revision semantics.

Admission, retention and recall validate current source lineage and dataset versions. Source chains use iterative traversal with visited identities, not a fixed ancestry-depth limit. Changes do not erase prior results; directory entries become historical and require revalidation before new use. Already-admitted work keeps its pinned context rather than silently adopting another method.

An old-domain skill cannot simply be relabeled through `procedure_use`. The shared cloud/native/Desktop research protocol advertises the transfer workflow through existing paged recall. Ordinary work with no saved procedure keeps the existing fast path. There is no new poller, model call on idle, UI, broker channel, executable package installation or added permission.

## Evidence Boundaries

- Domains and semantic mappings are explicit member declarations, not host-proven domain taxonomies.
- Distinct calibration and evaluation artifact identities prevent direct identity reuse; they do not prove unseen contents, absence of leakage or representative sampling.
- The comparator validates arithmetic on original tool reports. A flawed test harness can still produce misleading measurements. Independent review, suitable statistical design and external replication remain necessary.
- Source regression cases constrain the new method's claimed retention. They do not prove every old capability is preserved.
- Failure explanations remain hypotheses. A failure experience is not a permanent ban or proof that its proposed remedy works.
- Synthetic device tests verify plumbing and deterministic comparisons, not generalization, scientific novelty or superiority over a single agent.

The design draws on the experiential-memory direction of [ExpeL](https://arxiv.org/abs/2308.10144) and the task-specific method-adaptation direction of [Self-Discover](https://arxiv.org/abs/2402.03620). Their reported results are not evidence for GalaxySSI's performance. Real multi-domain, equal-budget model evaluations remain separate work.

## Main Code

- `CollaborationTransferStudy`: mappings, current lineage, scoped plan and retention checks.
- `CollaborationEvolutionContract` and `CollaborationEvolutionExperiment`: typed publication, original-report comparison and independent retention.
- `CollaborationProceduralMemory` and `CollaborationProcedureWork`: current source/dataset lineage and domain-bound runtime reuse.
- `CollaborationResearchWorkspace`: persisted, paged applicability status.

Full schemas remain available in `mode=evolution_rules`; prompt summaries do not contain the entire schema or history.
