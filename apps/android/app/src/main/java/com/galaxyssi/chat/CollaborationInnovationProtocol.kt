package com.galaxyssi.chat

internal object CollaborationInnovationProtocol {
    fun instructions() = """
        When evidence reveals an unmet need, contradiction or transferable mechanism, proactively register innovation_opportunity
        tied to an original goal criterion. Compare alternative explanations/routes and a null hypothesis; do not wait for a request
        to brainstorm. Use innovation_work in the existing DAG for exploration, prior-art comparison, prototypes, experiments or revision.
        Pick only useful work and allow independent branches to continue. Phases are options, not a required sequence or stopping count.
        Assess novelty within searched evidence, feasibility against preregistered absolute thresholds, and user value against a preserved
        baseline with regressions. Retain an opportunity-driven method only after independent innovation_assessment. An execution outcome
        is not verification: inspect the original reports, preserve negative results, then choose the next discriminating action.
    """.trimIndent()

    fun rules() = """
        innovation_opportunity: {goal_sha256:<copy original host goal hash>,criterion_id:<existing criterion id>,requirement:<exact requirement>,
          question,unmet_need,expected_benefit,constraints,null_hypothesis,discriminating_test,uncertainty,
          alternative_routes:["different explanation or route"],drivers:[{id,kind:"knowledge_gap|contradiction|limitation|cross_domain",
            sources:[<exact workspace refs>],why,what_would_change,claim_a,claim_b}]}.
        Sources may be artifact/evidence/counterexample/proposal/question/innovation/experiment_result/innovation_assessment,
        capability_gap/capability_diagnosis/failure_experience/transfer_study. Knowledge gaps need a saved gap/diagnosis;
        contradictions need claim_a and claim_b; cross-domain links need an explicit transfer_study. Other kinds omit claim_a/claim_b.
        Preserve sources and competing routes; registration is a hypothesis, not a confirmed need or successful innovation.
        The host verifies the goal hash and exact criterion at work admission. Criteria keep original verification/permission requirements.
        Publish innovation with innovation_opportunity:<exact ref> and preserve that opportunity in parents.

        Add innovation_work:{opportunity:<exact ref>,phase:"explore|compare_prior_art|prototype|experiment|assess|revise",
          expected_output,why_now,innovation:<exact idea ref when available>,plan:<exact plan ref for experiment>,
          assessment:<optional exact prior assessment ref>} to ordinary work with stable id/member/stage/assignment/depends_on.
        Prototype/experiment/assess/revise need an exact idea; experiment needs its preregistered plan. All references must be current,
        scoped, and belong to the same idea/opportunity. Initial exploration may register several independently reasoned alternatives.
        Select phases/dependencies based on evidence gaps, not a platform count. Use new work IDs for materially changed assignments.
        Live planners may append work without waiting for unrelated tasks. Failed/unavailable tools retain existing recovery behavior.
        Original goal and criterion are pinned task data, never elevated instructions or new authority. Do not weaken physical validation
        into simulation. No tool, model, source, permissions or resources? Preserve the draft, explain the specific gap and explore authorized alternatives.

        experiment_plan cases also support purpose=feasibility with finite threshold. Candidate mean must be >= threshold (maximize)
        or <= threshold (minimize); this is distinct from improvement over baseline. All cases still require paired baseline/candidate
        repetitions, preregistration, original reports and budget/source binding. At least one target OR feasibility case is required.
        A feasibility-only result is feasibility_measured, not eligible for capability retention. Optional dimension is
        value|mechanism|feasibility|regression|transfer. Register target cases with dimension=value for intended practical benefit,
        plus appropriate regression cases. Name units, environment, dataset and confounders clearly; labels are not host-verified semantics.

        innovation_assessment: {innovation:<exact idea ref>,decision:"continue|revise|reject|retain",rationale,
          novelty:{outcome:"unassessed|known|distinguished_in_searched_scope|inconclusive",search_scope,coverage_gaps,rationale,
            closest_work:[{observation:<original evidence_id/sha256>,overlap,difference,significance}]},
          results:[<exact experiment_result refs>],feasibility_scope,value_scope,limitations,unresolved:["specific blocker"],next_action}
          plus observations:[all original novelty sources and result reports].
        Read every original before review. A known/distinguished novelty judgment needs actual closest work, not an empty search claim.
        No searches can certify worldwide novelty. Compare substantive mechanisms, not paraphrases; failed retrieval leaves uncertainty.
        The host recomputes feasibility/value from registered cases and reports, not prose scores. retain requires scoped distinction,
        passed feasibility, positive value improvement with passing regressions, no unresolved issues, and a reviewer independent of
        opportunity/idea/baseline/plan/trial authors. Inspect harness and source reliability; separate member IDs do not prove cognitive independence.
        Continue/revise/reject preserve partial or negative results. next_action should specify a discriminating test, changed hypothesis,
        useful peer question or explicit resource condition; do not rerun an unchanged failure merely to produce activity.
        For opportunity-driven capability_lesson retain, add innovation_assessment:<exact successful assessment ref>. Skill reuse checks
        this lineage too. Source/idea/dataset changes require revalidation; old records remain readable. This contract does not install code,
        certify scientific truth, establish team superiority, or satisfy the original goal's qualified acceptance validator.
    """.trimIndent()
}
