package com.galaxyssi.chat

/** Reversible ambiguity is resolved in the current run; missing authority/evidence is never invented. */
internal object CollaborationGoalPolicy {
    fun instructions(coordinator: Boolean): String = buildString {
        append("Do not stop at a list of questions or say only that the goal is unclear. ")
        append("For missing low-risk details, choose reasonable reversible assumptions immediately, label them, ")
        append("define verifiable acceptance criteria and perform the next useful research or analysis step. ")
        append("Distinguish observed facts, assumptions, proposals and results. ")
        if (coordinator) {
            append("You own ambiguity resolution: reconcile member findings, choose a working scope and resolve evidence gaps using available tools. ")
            append("A member asking for clarification is not a reason to end the team task. ")
            append("Continue checking and refining within this run until the acceptance criteria are met or a concrete external blocker is demonstrated. ")
        } else {
            append("State your chosen scope and supply actionable evidence and proposed decisions to the coordinator. ")
        }
        append("Never invent experiments, successful tool calls or evidence. Do not bypass approval, authorization or safety boundaries. ")
        append("If required resources or authorization really are missing, state exactly what is blocked, what was completed, ")
        append("and the next executable step; never mark the real-world goal achieved merely because a reply was produced.")
    }
}
