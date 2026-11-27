# Conversational Agent Teams

An ordinary Agent chat can use temporary text-only workers for one requested
turn. The user stays in the same chat and receives one answer from the Agent.
This is a product contract, not a claim of implementation or scientific
validation. Unlike a [persistent Agent team](MULTI_AGENT_COLLABORATION_ARCHITECTURE.md),
the turn creates no team conversation, saved roster, or reusable worker.

As in [Codex subagent orchestration](https://developers.openai.com/codex/subagents/),
the coordinator delegates distinct assignments, waits for their results and
returns a consolidated answer. The ten-role cap and per-turn cloud approval
are GalaxySSI policies, not Codex defaults.

## When to use workers

"Have a team compare these two arguments and have someone challenge the
conclusion" and `/team Compare these two arguments` are equivalent explicit
requests. "Compare these two arguments" alone follows ordinary chat routing.
A mention of a team in quoted text, a question about how teams work, or
a request *not* to delegate does not start one. A bare `/team` without a task
asks for the task; it does not dispatch workers.

On Android, when an ordinary typed Agent turn is answered by the **on-device
model** (`local-llm`), its first answer can also suggest a temporary team. For
example, "Compare the two transit plans below, find assumptions that could
reverse the ranking, and recommend one" needs no teamwork wording. The model
returns its normal answer and an optional review signal together. The app does
not make a separate call to decide whether to offer review.

A manually selected OpenAI-compatible direct-cloud model can also offer
review as part of its ordinary first answer. A native final-answer function
returns the answer and invitation together. It is not an executable tool.
Plain text, quoted instructions, a failed or replayed attempt, and a response
from a different model cannot authorize a team. The user can decline and
keep the original answer without incurring any team calls. If confirmed,
only the current typed request goes to workers, not earlier messages. The
phone rechecks the selected contact, endpoint, model and disclosure settings
before dispatch. In the ordinary phone planning loop the native answer is
passed back as a response, not as proof of task completion. An invitation is
eligible only when the phone has accepted and recorded that same final answer
in the originating turn, never while evaluating a plan or following a tool step.
A private or restricted budget is not overridden. Desktop
and peer replies do not initiate these invitations.

The suggestion is available only in the originating, unlocked, active chat,
not for private or tracking-paused chats, health discussions or recognized
personal health requests, groups, member mentions, voice turns or attachments.
Editing the composer or leaving the window invalidates the pending review.
Where an eligible destination exists, the phone shows the exact typed objective,
the model and host (or this device), and the limit of twelve model requests.
An invitation from a pinned cloud provider has only that destination. For an
explicit team request with multiple eligible routes, choose one before confirming. A manual
model selection is never replaced. **Cancel** keeps the ordinary answer and
starts nothing; only **Confirm and run** authorizes the pinned team run.

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

In numbered plans, the last reviewer whose output is not needed by a later
role reads the actual synthesized draft, its assigned sources and the original
objective. This is one of the roles the model selected, not an extra call.
If another contributor raised an explicit reservation, the final editor sees
its role ID and public objection even without a dependency on that role.
No other part of a non-parent report is forwarded. The originating chat
retains these objections even when the editor withholds the draft or does
not confirm the source-table result. They are not presented as verified facts.
Intermediate reviewers still work before their consumers. The final editor can
accept, revise with a public correction, or withhold with a reason. A cancelled
or malformed audit does not release the draft.

An explicit Markdown comparison table can also be checked without model
arithmetic. Its first two headers must be `input | gate` or `输入 | 门槛`, with
named alternatives in the remaining columns. Each row supplies decimal values
in comparable units and one explicit `<`, `>`, `<=` or `>=` threshold, or
`-` for a row without a gate. Blank values, duplicate labels and ambiguous
table shapes do not enable this mode. The host compares the printed decimals,
not hypothetical higher-precision inputs. The reviewer receives those checks
and the draft. On agreement the app renders the source table and passing
alternatives itself, separately from the reviewer's explanation and limitation.
On a structured verdict mismatch it shows the recalculation as partial, not
the disputed narrative. The table cannot verify claims outside its data.

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

## Opt-in live model check

`tools/testing/LocalTeamAcceptance.java` runs the production Kotlin coordinator
on a host JVM against an already-running localhost chat-completions model. It
accepts only a numeric loopback port and model ID, never patient data, an API
key, or a remote endpoint. It does not install or exercise the Android UI.
Build the Android debug Kotlin classes first. With Java 17+, put
`app/build/tmp/kotlin-classes/debug` from the Android project, Kotlin stdlib,
kotlinx-coroutines-core-jvm and the JVM org.json jar on the classpath. From
the repository root run:

```text
java -cp <classpath> tools/testing/LocalTeamAcceptance.java <localhost-port> <local-model-id>
```

Repeat with `--swap` as a third argument to reverse the alternatives and their
definitions. The runner checks the labeled source rows, the changed expected
winner, a separate review call *after* synthesis, and a limitation on clinical
inference. A loopback OpenAI-compatible table audit requests a JSON schema for
the review envelope; the schema constrains types but contains neither the
series names nor the correct answer. Other routes do not request that schema.

The model chooses role count, assignments, dependencies, findings and synthesis.
Role numbers belong to the host. Check that there was a real downstream review,
that reported reservations reached the final answer, and that the final values
match their labeled inputs and curves. The program checks transport and the
presence of the numerical values separately; a human still checks attribution
and interpretation. The rubric also rejects the known contradictory English
verdict that both A and B pass, and flags a missing limitation on clinical
inference. It is a smoke test, not a general scientific fact checker. Run with
`--check-rubric` instead of the port and model to exercise those guards offline.
An incomplete plan or an incomplete answer fails the run.

The Custom/OpenAI preset at a numeric loopback host and the canonical
`/v1/chat/completions` path requests a compact JSON plan. It does not assume
the server supports schema-constrained decoding. For a known llama.cpp server
only, add `--schema-plan` to exercise native schema constraints. Both paths
validate role count, dependency order, assignments and the synthesis brief
before dispatch. Neither repairs a broken plan by inventing missing work.
For an explicit independent final review, the planner writes a separate
`final_review` brief as well as the contributor assignments and synthesis brief.
The brief commissions one real reviewer within the ten-role budget. It receives
the completed draft, not a placeholder or a prediction of what the author will
say. An independent work item can be a single assignment string; typed items
retain explicit kinds and dependencies. The app doesn't supply missing briefs,
invent graph edges, or count synthesis as review. A plan without a final editor
stops before workers; no unaudited draft is published. Outside this explicit
review mode, remote endpoints keep the existing planning protocol.

For an open-ended concept instead of a table comparison, use `--concept` as
an option. This fixed Chinese turn goes through the same team-command
parser as typed chat. The only disease background is that blood phenylalanine
can be elevated in PKU ([MedlinePlus Genetics](https://medlineplus.gov/genetics/condition/phenylketonuria/)).
It asks for a **research-only, in-vitro readout concept** without specifying a
candidate, mechanism or answer. The harness checks admission, independent
calls, handoff and final review. Inspect the public answer separately: does
it propose a readout, name an observation that would undermine its interpretation,
and distinguish desired behavior from actual measurements? The host replay
does not exercise Android UI, establish scientific novelty or validate a protein.
Add `--review-concept` alongside `--concept` to run a second, explicit
conversational review using only the first run's actual public answer. The
review asks whether the proposed falsifier really contradicts the prediction;
it does not supply a candidate or a correct answer. Each turn has separate
role and call accounting. Do not count a transport pass as a scientific pass:
report a correction as a second-turn result, not a first-turn success.
Use `--falsifiable-concept` instead to test a fresh, concise conversational
request for a prediction, a mutually incompatible observation under the same
conditions, and an evidence gap. No candidate, measurement or answer is supplied.
This single-turn result does not replace the longer follow-up test.
If the final editor requests changes with a specific objection and no replacement, or returns the same draft, the original synthesis
role can rewrite once. It receives the objection and its original public reports.
The same editor must explicitly approve the replacement; it sees only its
original review context plus the rejected draft and revised text. A veto or
unchanged rewrite withholds the answer. If fewer than two calls remain out of
twelve, neither extra call starts. Neither turn adds a role to the receipt.
For a falsifiable claim, contributors, the writer and the editor distinguish a
contrary observation made with a working readout from an invalid measurement.
Neither a broken readout nor an assumed outcome tests the prediction.
This is a reasoning instruction, not a guarantee of scientific accuracy.
When an independently reviewed task explicitly asks for a contrary observation,
the writer can express a directional claim as two named quantities and two
directions, together with its proposed purpose, competing explanation and
missing evidence. The coordinator renders the prediction and its opposite
using exactly the same input change and an interpretable readout. It supplies
no domain variable or measured result. Qualitative answers remain available
where this comparison does not fit. The independent editor sees the exact
rendered text; a disputed structured claim cannot be replaced by unaudited
prose. None of this validates the physical hypothesis.

For the Custom/OpenAI loopback route, a successfully decoded plan from a
server identifying itself as llama.cpp enables constrained writer output for
that endpoint and run only. No extra request is needed. The schema allows
both directions and does not prescribe any quantity or mechanism. Synthesis
can still choose prose; revision of a structured claim cannot. Other servers,
remote routes and tools do not receive the writer schema.

Even a perfect numerical result identifies only a mathematical response profile.
It says nothing about whether a physical protein can exhibit that profile.

## Synthetic acceptance rubric

Use only the public notes above, invented task text, and in-memory synthetic
dispatch records. These are pass conditions for the product, not test results
or proof of scientific feasibility.

| Gate | Pass condition |
| --- | --- |
| Intent and sizing | An explicit collaboration request and its `/team` equivalent admit the same task for confirmation. An eligible ordinary on-device answer may offer review but dispatches no workers without confirmation. A request not to delegate does not offer a team. A zero-worker plan reports no independent review. |
| Real roles | For the multi-perspective fixture, each role claimed in the answer maps to a distinct assignment, call ID, and returned finding. Workers get no peer drafts. One call returning three role-labeled paragraphs fails. |
| Disagreement | Seed the synthetic returns with "Phe reduction is sufficient" and "Phe reduction is relevant but insufficient." The final answer names the point of disagreement and explains its resolution; a vote or an invented consensus fails. For compatible returns, do not fabricate dissent. |
| Synthesis | One answer in the original chat retains the endpoint, limits it to the studied population, and explains why it is only a criterion for the hypothetical candidate. Concatenating the returns or crediting a failed worker fails. |
| Unverified feasibility | The answer explicitly says feasibility is unverified and identifies the missing candidate-specific evidence. Agreement among workers cannot validate a prediction. No design, procedure, or treatment recommendation is offered. |
| Bounds and isolation | At ten workers, count one plan, ten worker calls, and one synthesis, with at most three calls in flight and one approved provider throughout. Reject a thirteenth call. An unavailable route, a link requiring retrieval, or a synthetic placeholder for a private health record cannot trigger fallback, tool use, or disclosure. |
| Lifecycle | A cancelled run starts no queued assignments and publishes no late worker reply. A subsequent plain chat turn has no worker context or standing team authorization. |
