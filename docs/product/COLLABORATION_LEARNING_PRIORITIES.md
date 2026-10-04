# Evidence-bound learning priorities

This implements the second collaborative-evolution increment: choosing useful learning work under finite execution resources. It does not prove that a model learns, improves its weights, or consistently makes optimal choices.

## Decision and execution

1. A member publishes a capability gap and concrete alternative learning actions.
2. The team compares current-goal benefit, future transfer, information gain, uncertainty and estimated cost in an immutable `learning_agenda`. Every choice binds an exact gap revision and actual option ID. Selected and deferred alternatives remain available through scoped evolution/workspace recall.
3. The coordinator assigns selected options using ordinary DAG work with `learning:{agenda:{object_id,revision,sha256},option_id}`. The host checks the saved member, stage and assignment, current gap, group/round visibility, and exact hashes.
4. The selection claim and graph are committed together by the existing team store, for both next-round and live graph expansion. Renaming a work item cannot repeat an admitted option. Recovery keeps the original work identity. A changed strategy needs a new linked agenda.
5. Within one agenda, learning nodes are offered to the existing scheduler in priority order. A host-only plan flag preserves that order through runtime normalization. Unrelated nodes retain their positions in the previous ID-sorted projection; plans without learning keep the existing default ID sort. Dependency readiness and existing semaphore/capacity policies still govern actual starts. This is not preemptive scheduling, a new executor, or a guarantee of wall-clock start order under concurrent dispatch.
6. Terminal outcomes and measured elapsed time are checkpointed before the old round is replaced. The next coordinator receives actual outcomes, estimate error, output digest and original node references, together with the host's configured concurrency and unfinished-work count. It can inspect original task output, probes and experiments before choosing the next curriculum.

An agenda is a model-authored proposal, not spending authority. Resource values are explicitly `estimated` or `unknown`; unknown is never converted to zero. The current common result contract measures elapsed time but does not provide reliable cross-provider token/monetary totals, so those fields remain null. Existing task budget counters remain telemetry. No new lifetime step, round, retry or money cutoff is introduced.

## Reconsideration and safety

- All-deferred is valid and does not terminate the user goal.
- Failed, cancelled, partial and successful execution receipts do not establish learning gains.
- Capability retention still requires the independent experiment/regression contract; an agenda does not install tools or Skills.
- A changed gap invalidates new admission based on an older gap. Already dispatched work keeps its pinned contract and ordinary pause/stop/recovery semantics.
- Read and publication policies preserve blind rounds and group isolation. Independent workers receive only their assignment's learning binding, not the coordinator's full outcome history.
- Invalid batches are rejected atomically. No valid sibling is silently dispatched alongside a bad learning binding.
- No learning tasks means no extra workspace reads. Histories remain durable; prompt paging keeps full originals available rather than silently truncating them.
- Resource snapshots describe this team, not global free capacity or account credit. Authorization and runtime resource controls remain authoritative.

## Design references

The automatic curriculum in [Voyager](https://arxiv.org/abs/2305.16291) motivates choosing the next useful objective from environment feedback rather than a fixed lesson list. Its results concern Minecraft, not general scientific improvement. [Anthropic's multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) motivates explicit division of work and scaling effort to task complexity. These are design references, not benchmark evidence for GalaxySSI.

## Remaining validation

Synthetic tests validate integrity, persistence, admission and feedback. Real-model tests must still measure whether the selected curriculum improves held-out task success, reduces repeat failures, and outperforms a fixed or single-agent curriculum at equal measured budget. No such quality result is claimed by this increment.
