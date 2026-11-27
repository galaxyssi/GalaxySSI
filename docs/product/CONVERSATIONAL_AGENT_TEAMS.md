# Conversational Agent Teams

An ordinary Agent chat can use temporary text-only workers for one requested
turn. The user stays in the same chat and receives one answer from the Agent.
This is a product contract, not a claim of implementation or scientific
validation. Unlike a [persistent Agent team](MULTI_AGENT_COLLABORATION_ARCHITECTURE.md),
the turn creates no team conversation, saved roster, or reusable worker.

## When to use workers

"Have a team compare these two arguments and have someone challenge the
conclusion" and `/team Compare these two arguments` are equivalent explicit
requests. "Compare these two arguments" alone is an ordinary single-Agent
turn. A mention of a team in quoted text, a question about how teams work, or
a request *not* to delegate does not start one. A bare `/team` without a task
asks for the task; it does not dispatch workers.

The model selects **0 to 10 workers**, excluding the coordinating Agent. It
assigns each worker a distinct question whose answer could change the result.
The count is not a quota: zero is appropriate when no independent assignment
would help. In that case the Agent answers directly and does not claim a review
took place. The next turn does not inherit permission to delegate.

## One turn, one provider

1. **Admit the request.** Before any model call for the run, the host admits
   only permitted task text and pins one already approved provider: either
   on-device or direct-cloud. Planning, workers, and synthesis all use that
   provider. A collaboration request grants no new cloud permission. If the
   approved route is unavailable, report that; never switch routes silently.
2. **Bound the work.** Allow at most three concurrent calls and twelve logical
   model calls in total per turn. Reserve one call for planning and one for
   synthesis: ten workers therefore fit as waves of 3, 3, 3, and 1. A failed
   dispatch still spends its call; a new generation, including a retry, needs
   a remaining slot. No recursive delegation or unbudgeted review pass.
3. **Collect independent contributions.** Each selected worker gets its own
   model call with the task text and its assignment. Independent roles see no peer
   drafts; dependent roles receive only the public findings of their named predecessors. The host
   tracks which assignments returned, failed, or were cancelled. Role headings
   written by a single model call do not count as workers.
4. **Synthesize once.** The Agent uses the returned findings, identifies any
   material disagreement, and explains what it kept, qualified, or left open.
   If a required role fails, report failure rather than synthesizing an apparently complete
   answer. Cancellation stops queued work and suppresses late replies. The original
   request, status receipts, final answer and stated objections belong in the originating chat;
   discard worker contexts and drafts at termination.

The only allowed exchange is task text and model responses. Neither coordinator
nor workers may browse, follow links, invoke tools or connectors, read user
files or attachments, or retrieve memory or unrelated chat history. The explicit task text
is itself shared with the model named in the confirmation. Use public or synthetic examples,
not private patient details. A public source
citation is a reference, not authority to fetch its contents.

## Illustrative research example: PKU

This synthetic example is about how to reason from evidence, not how to treat
phenylketonuria (PKU) or develop a therapy. The following source notes were
checked while authoring this document. For the example turn, supply the notes
as plain text; the team does not visit the links or use patient records.

| Source note | What it establishes |
| --- | --- |
| [NIH consensus panel statement on PKU (2000), Introduction](https://www.nichd.nih.gov/publications/pubs/pku/sub3) | The panel described deficient phenylalanine hydroxylase activity in classical PKU, elevated phenylalanine (Phe), and an established dietary treatment that limits Phe and includes medical foods. This is a historical panel statement, not current clinical guidance. |
| [FDA-approved Sephience prescribing information (2025), section 1](https://www.accessdata.fda.gov/drugsatfda_docs/label/2025/219666s000lbl.pdf) | The US approval covers sepiapterin for elevated Phe in people at least one month old with sepiapterin-responsive PKU, alongside a Phe-restricted diet. The indication is specific to this drug and population. |
| [FDA Drug Trials Snapshot, Trial 1 Part 2, Table 2](https://www.fda.gov/drugs/drug-trials-snapshots/drug-trials-snapshots-sephience) | In the subgroup that had responded in Part 1, mean blood Phe fell more with sepiapterin than with placebo at weeks 5 and 6. This comparison concerns a biochemical endpoint, not a different candidate or a long-term clinical outcome. |

**Synthetic prompt:** "Have a team use these notes to explain what function
would matter for a hypothetical PKU research candidate and what we cannot
infer. Does the published experience settle whether the idea is feasible?"

For a more concrete brief, call the hypothetical protein **Phe-Buffer** (a fictional
working name, not a molecule or a claim of novelty). Its desired behavior is to
reduce excess Phe while having little effect when Phe is already low, without
materially depleting other amino acids. These are competing acceptance criteria,
not demonstrated properties. The [FDA pegvaliase label, sections 1 and 5](https://www.accessdata.fda.gov/drugsatfda_docs/label/2026/761079s031lbl.pdf)
provides a real enzyme comparator and identifies both hypersensitivity and low
Phe as concerns. It does not establish selectivity, safety or benefit for Phe-Buffer.
The proper review outcome is **concept specified; feasibility and clinical benefit unknown**.

**Reproducible counterexample for the reviewer.** Take two purely illustrative
response functions, A = x/(1+x) and B = x²/(1+x²), in arbitrary units. At
x = 1 both give 0.50; at x = 0.25 they give 0.20 and 0.059, and at x = 4 they
give 0.80 and 0.941. Only B meets the *invented demonstration criteria* of
less than 0.10 at the low input and greater than 0.85 at the high input.
One midpoint cannot identify either curve. This tests arithmetic and the
team's handling of an objection; neither curve is fitted to an enzyme or a patient.

An evidence reader can identify the observed endpoint and its population. A
criteria editor can argue for retaining Phe reduction as a *desired function*
of an unspecified candidate. An independent skeptic can challenge whether
that criterion alone says anything about suitability: lowering elevated Phe
is a different requirement from avoiding excessive lowering, and neither
establishes clinical benefit for the candidate.

An illustrative synthesis, not a report of an executed team, is:

> **Established:** The FDA comparison supports a blood Phe effect for the
> studied drug in the specified responders. **Conceptual criteria:** Retain
> reduction of elevated Phe as a relevant function, but not as a sufficient
> definition of success; preserving adequate Phe is a separate constraint.
> **Hypothetical idea:** A candidate might address both requirements. Nothing
> in these notes shows that such a candidate exists or meets either one.
> **Feasibility is unverified.** No candidate-specific evidence of safety,
> efficacy, or clinical benefit is supplied.

The example ends at that distinction. It supplies no novel sequences,
engineering or testing procedures, predictions represented as findings, or
therapeutic advice.

## Synthetic acceptance rubric

Use only the public notes above, invented task text, and in-memory synthetic
dispatch records. These are pass conditions for the product, not test results
or proof of scientific feasibility.

| Gate | Pass condition |
| --- | --- |
| Intent and sizing | An explicit collaboration request and its `/team` equivalent admit the same task. The ordinary and negated variants dispatch no workers. A zero-worker plan reports no independent review. |
| Real roles | For the multi-perspective fixture, each role claimed in the answer maps to a distinct assignment, call ID, and returned finding. Workers get no peer drafts. One call returning three role-labeled paragraphs fails. |
| Disagreement | Seed the synthetic returns with "Phe reduction is sufficient" and "Phe reduction is relevant but insufficient." The final answer names the point of disagreement and explains its resolution; a vote or an invented consensus fails. For compatible returns, do not fabricate dissent. |
| Synthesis | One answer in the original chat retains the endpoint, limits it to the studied population, and explains why it is only a criterion for the hypothetical candidate. Concatenating the returns or crediting a failed worker fails. |
| Unverified feasibility | The answer explicitly says feasibility is unverified and identifies the missing candidate-specific evidence. Agreement among workers cannot validate a prediction. No design, procedure, or treatment recommendation is offered. |
| Bounds and isolation | At ten workers, count one plan, ten worker calls, and one synthesis, with at most three calls in flight and one approved provider throughout. Reject a thirteenth call. An unavailable route, a link requiring retrieval, or a synthetic placeholder for a private health record cannot trigger fallback, tool use, or disclosure. |
| Lifecycle | A cancelled run starts no queued assignments and publishes no late worker reply. A subsequent plain chat turn has no worker context or standing team authorization. |
