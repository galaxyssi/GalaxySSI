package com.galaxyssi.chat

internal object CollaborationTeamInventionProtocol {
    fun instructions() = """
        To create a better shared method, seek different mechanisms, solicit concrete peer challenges, let contributors respond,
        then publish team_synthesis explaining what changes because of each exchange. Preserve disagreements and test-needed answers.
        Use innovation_work challenge/respond/combine in the existing DAG; append useful work as evidence arrives, not a fixed sequence.
        Combine promising parts into a linked innovation, then test against every parent and a distinct single-agent control under the same
        preregistered conditions and end-to-end budget. Team size, agreement and polished prose do not establish a gain.
        Use independent team_evaluation before retaining a team method. If it loses, preserve the result and choose a different mechanism,
        sharper test or narrower scope. Do not manufacture activity or repeat completed side effects. No new permissions are granted.
    """.trimIndent()

    fun rules() = """
        team_exchange: {operation:"challenge|response",innovation:<exact innovation ref>,issue,reasoning,discriminating_test,uncertainty,
          suggested_change:<challenge only>,challenge:<exact challenge ref for response>,decision:"adopt|adapt|reject|test_needed",
          change_or_reason:<response only>,remaining_question:<response only>}.
        A challenge is from a non-contributor; its response is from an idea contributor. The exact version must match. Attach and read
        observations when available, but an argument or answer is not verification. Respond substantively: identify a correction or
        reason to reject it and a test that distinguishes alternatives. Preserve uncertainty instead of forced agreement.
        team_synthesis: {opportunity:<exact innovation_opportunity>,mechanism,interaction_hypothesis,why_not_concatenation,
          discriminating_test,limitations,contributions:[{innovation:<exact idea>,challenge:<exact team_exchange>,response:<exact team_exchange>,
            retained,changed,response_effect}]}.
        Use at least two distinct source ideas from different members serving the same opportunity. Each source needs a preserved
        challenge and contributor response. More members/ideas are optional, not a stage count. This records proposed synergy, not proof.
        Publish a combined innovation with origin=combination, team_synthesis:<exact ref>, the same innovation_opportunity, and parents
        containing the synthesis, all source ideas and the opportunity. Explain a new interaction/mechanism, not concatenated answers.
        Consider independently generated alternatives before exchanging them; member IDs alone do not prove cognitive independence.

        innovation_work.phase also accepts challenge/respond/combine. Challenge/respond require innovation:<exact idea>; respond also
        requires exchange:<exact challenge>. Assign challenges to non-contributors and responses to contributors. combine requires
        team_synthesis:<exact ref> and may omit innovation until one is published. Other phases may pin exchange, team_synthesis or
        team_evaluation refs. All refs are scoped/current and become immutable work bindings. Run dependent publication in later tasks.
        Use precise peer tasks rather than broadcasting every message to everyone. Existing inbox, pause and recovery behavior remains.

        For measured team comparisons, preregister one experiment_plan per parent and one for a distinct single-author control. Add
        team_comparison:{single_agent:<same exact artifact/proposal/innovation ref>,accounting:"end_to_end",resource_scope:<exact scope>}.
        All plans share identical fields except baseline: exact combined innovation, cases, environment, method, source and total budget.
        Each case additionally pins dataset:<exact artifact ref>. Register ALL plans before ANY comparison trial. Retain regressions,
        quality/feasibility and a useful value target; preselect the meaningful metric, not whichever improves afterward.
        Every measurement includes dataset_sha256. In original tool reports include resource_totals once per variant across observations:
          [{variant:"baseline|candidate",preparation:0,coordination:0,execution:1}].
        Use actual reported costs in the plan's common budget_unit, including proposal creation, peer coordination, revisions and evaluation.
        Each variant's sum must fit the SAME total budget_limit; execution must cover all its trial costs. Missing accounting stays incomplete.
        Attribute shared preparation/coordination once across the campaign and include every comparison's execution cost. Retention also
        sums each method's costs across ALL controls and checks the same ceiling, so splitting experiments cannot hide overspending.
        These are source-reported costs, not independently audited billing. Never invent costs to pass. Preserve raw execution metadata.

        team_evaluation: {innovation:<exact combination>,results:[<exact experiment_result refs>],decision:"continue|revise|reject|retain",
          rationale,harness_review,limitations,unresolved:[],next_action} plus observations:[all original comparison reports read in full].
        Retain requires coverage of every source idea and the single-agent control, positive target gains plus passing regressions in each,
        complete equal-ceiling end-to-end accounting, matching preregistered conditions and an independent reviewer outside all idea,
        synthesis, challenge/response, plan, result, baseline and trial contributors. Inspect the actual harness and artifacts for validity.
        Empty/partial/negative comparisons may be saved as continue/revise/reject, never gain. Keep failed/null results and useful parents.
        No vote or prose score can substitute for measured evidence. A scoped test does not prove general team superiority or worldwide novelty.
        Team-derived innovation_assessment retain and capability_lesson retain require team_evaluation:<exact retained evaluation ref>.
        Reusable procedure skills preserve the full lineage. Changes to parents/datasets require revalidation, not inherited success.
        The original goal's qualified acceptance, scientific/physical validation and existing authorization boundaries remain unchanged.
    """.trimIndent()
}
