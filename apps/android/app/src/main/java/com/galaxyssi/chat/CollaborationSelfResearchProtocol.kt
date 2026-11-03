package com.galaxyssi.chat

internal object CollaborationSelfResearchProtocol {
    fun instructions() = """
        When actual failures or measured bottlenecks justify improving how the team works, join diagnosis, learning selection,
        innovation, controlled experiments and retention into a self_research_cycle. Keep it subordinate to the authorized goal.
        Inspect mode=problems, original observations and actual learning/workflow outcomes; do not invent performance signals.
        Bind ordinary goal/live work with self_research:{cycle:<exact ref>,action_id,why_now} AND innovation_work.
        Keep stable work/action IDs through network loss and restart; reuse saved reports, not completed side effects.
        Candidate innovations carry self_research_cycle:<exact cycle ref>. Use independent paths/challenges where useful,
        register experiments before running them, retain failures and compare actual baselines, costs and regressions.
        Have an independent member publish self_research_review. Adoption needs existing measured lessons and protected
        capability channels; a successful dispatch or persuasive explanation is not an improvement. Multiple candidates may survive.
        Continue useful research with a new cycle referencing previous_review and explicit new_information. Select learning,
        transfer, new tools, workflow changes or additional evidence according to the gap, not a fixed stage/round/retry count.
        If the same strategy yields no new evidence, explain it and change strategy or ask a different member; preserve history.
        A wait review records the real resource/permission blocker and checked alternatives. It does not itself pause the goal:
        continue independent feasible work and use existing goal blockers only when nothing executable remains.
        Research adoption/rejection is NOT completion of the original user goal and grants no permissions, spending or deployment.
        Do not keep unrelated self-research alive after the user's goal ends or is stopped. Existing pause/stop always wins.
    """.trimIndent()

    fun rules() = """
        self_research_cycle: {diagnosis:<exact capability_diagnosis>,agenda:<exact learning_agenda>,option_id,
          opportunity:<exact innovation_opportunity>,question,component,scope,success_test,new_information,goal_tradeoff,
          previous_review:<optional exact self_research_review>}.
        The selected agenda option must address the diagnosed gap, and the opportunity must cite that gap/diagnosis.
        Immutable cycles are checkpoints, not repeated side effects. Link the previous review when continuing research.
        innovation optionally adds self_research_cycle:<exact ref>; its opportunity must match the cycle.
        self_research_review: {cycle:<exact ref>,decision:"adopt|reject|revise|wait",reason,limitations,next_question,
          information_gained,alternatives:["considered alternative"],evaluations:[{result:<exact experiment_result>,
          lesson:<exact capability_lesson>}],channels:[<exact capability_channel refs>],
          blocker:{reason,resume_when,checked_alternatives}}.
        blocker is required only for wait. Cite/read all original result observations. Reviewer must be independent of the
        cycle proposer and candidate/plan/trial authors. Every evaluated candidate must belong to this cycle.
        adopt requires independently retained measurements plus a current protected channel for EACH retained candidate;
        rejected alternatives remain in evaluations. reject requires actual rejected results; revise/wait may preserve an
        incomplete cycle. Non-adoption must have no channels. New cycles may branch from the same prior review.
        Originals, lessons, negative results, immutable reviews and selection history remain available after restart.
        This is scoped process/tool improvement, not autonomous global code deployment, model-weight training or scientific proof.
    """.trimIndent()
}
