package com.galaxyssi.chat

import org.json.JSONObject

/** The compact policy is universal; full schemas are recalled only by members doing evolution work. */
internal object CollaborationEvolutionProtocol {
    fun instructions() = """
        Collaborative evolution: diagnose capability gaps (knowledge/tool/method/verification/coordination), then choose learning by
        goal relevance, expected gain, information gain and resource cost. Improvement work must serve the authorized goal.
        Proactively propose testable innovations from missing knowledge, contradictory evidence, limitations and cross-domain links.
        Describe a mechanism, difference from prior art, falsifier and concrete predictions, not merely another phrasing of a proposal.
        Begin with independent alternatives; let peers challenge weaknesses and combine useful parts with exact parent references.
        Compare predictions before acting, preregister discriminating experiments, execute only authorized tools, and revise from outcomes.
        Use mode=evolution_rules with offset=0 on collaboration_recall (or galaxyssi.phone.collaboration.recall) for typed schemas;
        follow next_offset. Use mode=evolution with cursor="" to browse scoped gaps/ideas/plans/results/lessons, then workspace recall
        for full originals. These records survive future tasks in this group; they grant no cross-group/private-memory access.
        Plan actual work in the existing work DAG. Do not wait for unrelated branches or create a second autonomous execution loop.
        A useful missing tool may be implemented/tested in an authorized sandbox; record its exact artifact as a baseline/candidate.
        Before reusing a retained lesson check applicability, negative results and versions; test transfer in a new domain explicitly.
        Compare single-agent versus team methods at the same budget, test regressions, and retain the previous version for rollback.
        Numerical improvement is not scientific truth or global novelty. Text review, simulation and physical validation stay distinct.
        Keep full failures, null results and untested ideas. Do not rerun completed side effects just to collect evidence.
        When progress stalls, change the hypothesis/test or seek relevant peers; no fixed research-round count determines success.
        No lesson installs a Skill, changes app code, expands permissions or spends resources by itself. Existing approval and pause rules apply.
    """.trimIndent()

    fun rules(): JSONObject = JSONObject().put("format", "galaxyssi.collaborative-evolution.v1").put("contract", """
        Publish each typed record as an ordinary workspace item: {id,kind,title,body:{content,<kind>:{...}},parents:[],observations:[]}.
        Exact refs always contain object_id, integer revision and sha256 from host receipts. Never invent them.
        Each publication is atomic and idempotent. Read originals first. Use distinct work IDs and dependent tasks for later records.
        New records use id; revisions use object_id/base_revision. Only capability_gap and innovation may be revised by their author.
        Other members create linked alternatives. Plans/results/lessons are immutable. Invalid fields get precise publication feedback.

        capability_gap: {category:"knowledge|tool|method|verification|coordination",symptom,needed_capability,
          learning_options:[{id,action,expected_gain,cost,goal_relevance,verification}],chosen_option:"one option id",rationale}.
        Include the actual error or conflicting evidence. Distinguish an observed symptom from a proposed diagnosis.

        innovation: {origin:"gap|contradiction|limitation|transfer|combination",hypothesis,mechanism,difference,prior_art,
          novelty_scope:"not_checked|searched_scope_only",falsifier,domain,applies_when,risks,alternatives:["alternative explanation"],
          predictions:[{id,statement,test}],transfer_conditions:"required for transfer/combination"}.
        State search coverage and limitations in prior_art. searched_scope_only needs cited original observations read in full.
        transfer needs a preserved parent; combination needs at least two distinct parents. This is not certification of novelty.
        Existing candidate/candidate_event objects remain available for documentary comparison/challenge/repair; use linked parents.

        experiment_plan: {innovation:<exact innovation ref>,baseline:<exact proposal/artifact/innovation ref>,prediction_id,
          method,environment,budget_unit,budget_limit:<positive decimal>,source:{origin,tool},report_pointer:"JSON pointer, empty=root",
          cases:[{id,purpose:"target|regression|transfer",prediction,metric,direction:"maximize|minimize",
            minimum_gain:<nonnegative decimal>,tolerance:<nonnegative decimal>,repetitions:<positive integer>}]}.
        Save the exact baseline implementation/control in a workspace artifact first. At least one target case is needed.
        Choose useful case coverage/repetitions for the domain, not a fixed platform step count. Retention needs regression cases too.
        One budget ceiling and environment apply equally to baseline and candidate trials. Trial budgets are not new spending authority.
        Register BEFORE executing trials. Copy the returned plan sha256 into your test harness output. Do not post-select trials.
        Valid source origins: android_cloud_tool, android_native_tool, desktop_codex_tool. Copy the exact real source tool name.
        For Desktop this may be codex.commandExecution; inspect evidence before choosing a report_pointer into its original payload.
        A pointer may select a JSON object or a string containing exactly JSON (no log prefix/fences). No parsing by a model is accepted.
        Make a sandboxed test harness emit:
          {"format":"galaxyssi.experiment-measurements.v1","plan_sha256":"exact saved plan hash",
           "environment":"exact plan environment","budget_unit":"exact plan unit","measurements":[
             {"case_id":"exact case id","variant":"baseline|candidate","variant_sha256":"exact workspace revision hash",
              "metric":"exact metric","repetition":1,"value":0.5,"budget_used":1}]}.
        Reports may be split across several real tool calls. Each case/variant/repetition appears exactly once in a result.
        The host checks source/time/version/budget bindings and computes means and signed gains itself. It does NOT certify
        that a self-written harness measures reality correctly. Independently inspect the harness, dataset and confounders.
        Without an appropriate executable tool keep the plan untested and explore authorized alternatives; never fabricate reports.

        experiment_result: {plan:<exact plan ref>,interpretation,limitations} plus observations:[actual receipt refs].
        Read all original observation pages first. Partial results are stored as incomplete, never discarded or called success.
        A target/transfer case passes only with positive gain >= minimum_gain. A regression passes if gain >= -tolerance.
        All planned repetitions must be present. Missing measurements, a failed target or regression prevent retention.
        Failed transfer does not imply failure in the original domain; inspect per-case state and narrow applicability accordingly.
        A new case/design/target revision needs a new plan. Reuse stored observations after reconnect; do not repeat tools for a lost receipt.
        Late results for old target versions remain historical measurements; they cannot authorize retention of a newer version.

        capability_lesson: {result:<exact experiment_result ref>,decision:"retain|reject|revise",rationale,
          applies_when,avoid_when,procedure,transfer_test,rollback:<exact baseline ref>} plus observations:[all result receipt refs].
        retain requires measured improvement, a passing regression suite and an independent reviewer who authored neither the
        idea/baseline/plan nor trial tools. That reviewer must read every original report. reject/revise preserve negative experience.
        A retained lesson is eligible for scoped reuse, NOT an installed Skill/tool, code deployment or proof of goal completion.
        Keep applicability narrow, especially when transfer cases are not met. Existing skill/package/tool execution gates still apply.
        Recall prior lessons to improve planning/search/tooling/collaboration/checking. Reevaluate after context or model changes.
        No record here satisfies physical/scientific goal acceptance; the original goal's qualified validator remains authoritative.
    """.trimIndent())
}
