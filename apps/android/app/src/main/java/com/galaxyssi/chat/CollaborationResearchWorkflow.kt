package com.galaxyssi.chat

import java.util.UUID

internal enum class CollaborationWorkflow { AUTO, PARALLEL, RESEARCH }

internal enum class CollaborationResearchStage {
    BRIEF, EXPLORE, CHALLENGE, REVISE, COMBINE, VERIFY, REPAIR, RECHECK, DELIVER
}

/** Host-owned graph: independent contexts first, then explicit evidence dependencies. */
internal object CollaborationResearchWorkflow {
    const val MAX_NODES = 64
    const val STAGE = "collaboration_research_stage"
    const val PERSON = "collaboration_research_person"
    const val CANDIDATE = "collaboration_research_candidate"
    private val researchIntent = Regex(
        "研究|調研|调研|调查|調查|设计|設計|方案|创新|創新|探索|改进|改進|脑洞|腦洞|" +
            "\\b(research|investigat\\w*|design|propos\\w*|innovate|brainstorm|improv\\w*)\\b", RegexOption.IGNORE_CASE)

    fun enabled(goal: String, requested: List<AgentRequestedMember>): Boolean {
        if (requested.size < 3 || requested.any { it.collaborationGroupId.isBlank() }) return false
        return when (requested.first().collaborationWorkflow) {
            CollaborationWorkflow.PARALLEL.name -> false
            CollaborationWorkflow.RESEARCH.name -> true
            else -> researchIntent.containsMatchIn(goal)
        }
    }

    fun stage(member: AgentTeamMember): CollaborationResearchStage? =
        member.context[STAGE]?.let { runCatching { CollaborationResearchStage.valueOf(it) }.getOrNull() }

    fun isResearch(members: List<AgentTeamMember>): Boolean = members.isNotEmpty() &&
        members.all { stage(it) != null && !it.context["collaboration_group_id"].isNullOrBlank() }

    fun expand(members: List<AgentTeamMember>, goal: String): List<AgentTeamMember> {
        require(members.size in 3..12)
        val coordinator = members.first { it.deliveryMode == AgentDeliveryMode.RESPOND }
        val researchers = members.filter { it.memberId != coordinator.memberId }
        val candidates = minOf(3, researchers.size)
        fun id(person: AgentTeamMember, stage: CollaborationResearchStage): String =
            if (stage == CollaborationResearchStage.DELIVER) person.memberId else UUID.nameUUIDFromBytes(
                "${person.memberId}:research:${stage.name}".toByteArray()).toString()
        fun node(person: AgentTeamMember, stage: CollaborationResearchStage, dependencies: Set<String>,
            assignment: String, candidate: String = ""): AgentTeamMember = person.copy(
            instanceId = id(person, stage),
            deliveryMode = if (stage == CollaborationResearchStage.DELIVER) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            dependsOnAgentIds = dependencies,
            objective = "$assignment\nUser goal: $goal".take(4_000),
            context = person.context + mapOf(STAGE to stage.name, PERSON to person.memberId,
                CANDIDATE to candidate, "collaboration_receive_results" to "false"))
        val brief = id(coordinator, CollaborationResearchStage.BRIEF)
        val explore = researchers.map { id(it, CollaborationResearchStage.EXPLORE) }
        val challenge = researchers.map { id(it, CollaborationResearchStage.CHALLENGE) }
        val revised = researchers.map { id(it, CollaborationResearchStage.REVISE) }
        val combined = id(coordinator, CollaborationResearchStage.COMBINE)
        val verified = researchers.map { id(it, CollaborationResearchStage.VERIFY) }
        val repair = id(coordinator, CollaborationResearchStage.REPAIR)
        val rechecked = researchers.map { id(it, CollaborationResearchStage.RECHECK) }
        return buildList {
            add(node(coordinator, CollaborationResearchStage.BRIEF, emptySet(),
                "Define the goal, constraints, measurable acceptance criteria and reversible defaults. " +
                    "Do not solve the problem or anchor the researchers to one favored answer. Identify missing authority or resources."))
            researchers.forEachIndexed { index, person ->
                add(node(person, CollaborationResearchStage.EXPLORE, setOf(brief),
                    "Independently explore this path: ${paths[index % paths.size]}. " +
                        "Your professional role: ${person.role}. You cannot see other researchers' answers yet. " +
                        "Produce a distinctive testable proposal, evidence, assumptions, strongest weakness and open question."))
            }
            researchers.forEachIndexed { index, person ->
                val target = (index + 1) % researchers.size
                add(node(person, CollaborationResearchStage.CHALLENGE, setOf(brief, explore[target], explore[index]),
                    "Critically review ${researchers[target].context["collaboration_name"]}'s supplied proposal, not your own. " +
                        "Find concrete counterexamples, failure conditions or alternative explanations. Every objection must " +
                        "include evidence, a proposed repair and a discriminating check. Agreement is allowed when justified; do not invent disagreement."))
            }
            researchers.forEachIndexed { index, person ->
                val reviewer = (index + researchers.size - 1) % researchers.size
                add(node(person, CollaborationResearchStage.REVISE, setOf(brief, explore[index], challenge[reviewer], challenge[index]),
                    "Respond to each critique of your original proposal. Accept, rebut with evidence, or mark unresolved. " +
                        "Revise the actual proposal and specify what changed, rather than merely acknowledging the reviewer."))
            }
            add(node(coordinator, CollaborationResearchStage.COMBINE, revised.toSet() + brief,
                "Combine useful mechanisms across proposals into $candidates distinct alternatives, C1 through C$candidates. " +
                    "Keep trade-offs and dissent, not an average or majority vote. Each candidate needs an actionable artifact/plan, " +
                    "parent proposal references, success criteria, failure conditions and a falsifiable check. Do not choose a winner yet."))
            researchers.forEachIndexed { index, person ->
                val candidate = "C${index % candidates + 1}"
                add(node(person, CollaborationResearchStage.VERIFY, setOf(brief, combined),
                    "Independently validate candidate $candidate against the brief and failure conditions. " +
                        "Use available code, data, original literature or authorized tools. Preserve the observation and evidence. " +
                        "A proposed experiment is not an executed experiment. Mark unsupported or unrun checks not_tested.", candidate))
            }
            add(node(coordinator, CollaborationResearchStage.REPAIR, verified.toSet() + combined + brief,
                "Use all verification results to repair the candidate artifacts. Preserve C1..C$candidates identities. " +
                    "For each substantive failed check, modify its cause or explain the unresolved blocker. " +
                    "If checks passed, retain that candidate unchanged and explain why. Preserve competing valid alternatives."))
            researchers.forEachIndexed { index, person ->
                val candidate = "C${index % candidates + 1}"
                add(node(person, CollaborationResearchStage.RECHECK, setOf(brief, repair, verified[index]),
                    "Recheck $candidate after the revision. Compare the new artifact with your earlier observed failure or uncertainty. " +
                        "Run a fresh check if it changed; otherwise reuse only still-applicable evidence and label it. " +
                        "Do not upgrade a proposed or unperformed test to success.", candidate))
            }
            add(node(coordinator, CollaborationResearchStage.DELIVER, rechecked.toSet() + repair + brief,
                "Deliver a concise evidence-grounded comparison of all candidate alternatives. Identify what was newly combined, " +
                    "which critiques changed the artifacts, observed validation results, remaining disagreements and blockers. " +
                    "Recommend by scenario; multiple alternatives may remain valid. Do not force one winner. " +
                    "Distinguish a completed research cycle from a real-world goal achieved. Never claim physical validation without records."))
        }.also { require(it.size <= MAX_NODES) }
    }

    private val paths = listOf(
        "successful precedents and primary evidence; improve an established mechanism",
        "failure cases, contradictions and boundary conditions; test a competing explanation",
        "first-principles reconstruction under severe resource constraints",
        "transfer a mechanism from another discipline; identify where the analogy breaks",
        "combine two normally separate approaches into a novel, falsifiable hypothesis",
        "design measurements or experiments that distinguish rival explanations")
}
