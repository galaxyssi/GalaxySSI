# Collaboration Evolution Rule Topics

## Purpose

Members can discover and read a relevant capability contract without paging through the entire evolution reference. This supports autonomous method selection; it does not choose a research strategy, mandate phases, grant permissions or certify capability growth.

The same phone-owned contracts are available to managed Android cloud assignments, the native phone recall tool, and remote Codex through the Desktop recall bridge. Desktop preserves the originating phone, member assignment, task generation and arguments; it does not maintain a separate copy of the contracts.

## Reading

Use `collaboration_recall` (or `galaxyssi.phone.collaboration.recall`) with:

```json
{"mode":"evolution_rules","topic":"catalog","offset":0}
```

The returned JSON page contains a directory with purposes and reading prerequisites. Select an applicable topic, read its prerequisites when needed, and follow `next_offset` using the **same topic** until null. Prerequisites are contract-reading dependencies, not required execution steps. The model still chooses work from the goal and evidence.

| Topic | Contract area |
| --- | --- |
| `foundation` | Gap diagnosis, ideas, paired experiments and evidence-linked lessons |
| `learning` | Learning priorities |
| `procedures` | Reusable procedures and failure experience |
| `transfer` | Cross-task applicability and transfer studies |
| `innovation` | Opportunities, work and independent novelty/value assessments |
| `team_invention` | Cross-member challenges and method combinations |
| `prediction` | Before-action predictions and measured outcomes |
| `tools` | Tool development, testing, review and reuse |
| `workflows` | Executable method graphs and comparisons |
| `retention` | Regression suites, capability channels and rollback |
| `self_research` | Evidence-linked studies of the system's own methods |

Omitting `topic`, or selecting `all`, retains the complete reference and original contract order. Topic views contain exact existing schema text, not lossy summaries. `catalog` is navigation metadata, not a plan.

Each successful transport page returns `topic`, `content`, `total_characters`, `next_offset`, and `trust=host_schema_not_execution_authority`. Content is paginated JSON text using the existing 8,000-character page size. Unknown topics return an actionable diagnostic rather than silently falling back. `topic` is rejected outside `evolution_rules`; callers cannot supply new group/member identities.

## Progress and recovery

For managed cloud loops, newly read characters of authentic host rule pages count as reading progress, so long contracts do not cause premature tool-free synthesis. This is not new scientific evidence or comprehension. Execution/checkpoint provenance and exact host content are checked before recognizing progress. Repeated receipts, equivalent omitted/explicit `all` selectors, overlapping pages already read, empty end pages and malformed outputs do not manufacture progress. Existing web evidence tracking remains separate.

Recovery reconstructs observed rule coverage from checkpointed tool results. Nothing is installed or executed by recalling a schema. Existing publication validation, independent review, scope, pause/stop, model routing and resource policies still apply.

## Verification

- JVM tests cover directory integrity, exact contract preservation, invalid topics, provider schemas, read-volume accounting, complete pagination, overlapping/repeated pages and checkpoint replay.
- Desktop tests cover selector validation and authenticated round trips with unchanged phone/task binding.
- Synthetic Android instrumentation tests reconstruct every topic through both cloud and native recall and reject revoked access. These tests make no model calls or external changes.

Read-volume differences are deterministic interface measurements, not proof of better reasoning, faster model responses, successful innovation or cross-domain capability growth. Those require subsequent real-model and independent task evaluation.
