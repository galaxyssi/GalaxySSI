package com.galaxyssi.chat

/** Keep decision invariants inline; retrieve optional field schemas through the existing host-rule tool. */
internal object CollaborationCoordinationProtocol {
    fun instructions() = """
        Coordination fields are available on demand through collaboration_recall or galaxyssi.phone.collaboration.recall:
        mode=evolution_rules, topic=coordination, offset=0; follow next_offset with the SAME topic until null.
        Read that host schema before using data_dependencies, completion_barriers, review_targets, review_milestones,
        rebind_inputs, rebind_reviews, revise_input_dependencies, candidate_cycles or replication. Do not guess their fields.
        Default depends_on edges require producer completion. Distinguish evidence-only waits from real operation/resource
        barriers when planning. Exact published inputs may enable a pending consumer before the producer finishes;
        existing mistaken waits can be explicitly revised with evidence and rationale, not silently removed or cloned.
        Independent review must retain a different known author and all required inputs; never relabel a reviewed candidate
        as supporting data or disable independence to bypass a conflict. Publication is not verification or goal completion.
        Preserve explicit user roles, original acceptance requirements, stable work identities and completed side effects.
        Reuse compatible members before recruiting. Different IDs or wording alone do not justify duplicate work.
        Keep alternative candidates and their failed results; comparison or a vote is not an executed validation.
        On-demand schemas describe accepted host operations, not additional authority, resources or a required research sequence.
    """.trimIndent()

    fun rules(): String = listOf(
        CollaborationDataDependencies.instructions(),
        CollaborationReviewTargets.instructions(),
        CollaborationReviewRebinding.instructions(),
        CollaborationCandidateEvolution.instructions(),
        "For incremental current-round candidate_cycles, also include producer_work_ids with the exact existing producer work ID.",
        CollaborationTeamOrganizationContext.instructions(),
        validatorExamples()
    ).joinToString("\n")

    internal fun validatorExamples() = """
        Establish computational verification before claiming completion. A decision=continue assessment may add an absent qualified
        validator to an unchanged open/observed criterion only while its evidence is empty and delivery/review are absent in both saved and new criteria.
        It must match the validator's literal requirement; requirement, source obligations and already bound inputs cannot be changed.
        Registration updates the persisted contract before new work; it is not acceptance, oracle certification or proof of preregistration before measurements.
        The exact-integer fixture uses verification=computational and validator:{id:"exact_integer_sum.v1",operands:[canonical decimal strings]}.
        It accepts only the literal requirement "Compute the exact integer sum: 2 + 3." for operands ["2","3"] (substitute the actual operands).
        Save body.computation:{validator_id:"exact_integer_sum.v1",result:"5"} alongside body.content; the host recomputes the sum.
        Limits are 2..32 operands of at most 256 digits. Independent delivery review and goal coverage are still mandatory.
        numeric_model_cases.v1 also replays a saved pure numeric expression against preserved input/expected/tolerance cases.
        Its literal requirement is: "${CollaborationNumericModelValidator.REQUIREMENT}"
        Recall mode=evolution_rules, topic=tools for its exact schema and execution envelope. Members can publish numeric_model_trial
        before final acceptance to obtain host-computed errors and compare revised models; failed trials stay saved.
        The host checks ALL supplied cases, not a model-written score; these local replay limits are not research step/round limits.
        Supplied reference values are not certified true, held-out or independent. Keep provenance, oracle validity and generalization as separate requirements.
        executable_tool_cases.v1 also qualifies actual generated Python tool execution on preserved JSON input/output cases,
        using the existing native runtime, immutable source/test versions and independently reviewed original receipts.
        Recall mode=evolution_rules, topic=tools before planning this route; establish its exact environment/cases contract early.
        Code can be revised without weakening the suite. No code is executed by final acceptance; generic shell claims do not qualify.
        This is finite-case execution evidence, not proof of oracle truth, unseen-task transfer or general/physical validity.
    """.trimIndent()
}
