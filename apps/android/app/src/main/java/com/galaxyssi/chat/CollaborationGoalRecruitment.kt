package com.galaxyssi.chat

import java.util.Locale
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Recruitment changes identities and assignments, never provider authority or execution concurrency. */
internal object CollaborationGoalRecruitment {
    const val VACANCY = "collaboration_research_vacancy"
    const val SIGNATURE = "collaboration_research_vacancy_signature"
    const val TEMPLATE = "collaboration_research_recruit_template"
    const val PUBLISHED = "collaboration_research_recruit_published"
    const val FEEDBACK = "collaboration_research_recruit_feedback"
    data class Plan(val people: List<AgentTeamMember>, val aliases: Map<String, String>, val error: String = "")

    fun plan(people: List<AgentTeamMember>, requests: JSONArray?, work: JSONArray, names: List<String>): Plan {
        if (requests == null || requests.length() == 0) return Plan(people, emptyMap())
        return runCatching {
            val roster = people.toMutableList()
            val templates = people.associateBy { it.context.getValue(CollaborationResearchWorkflow.PERSON) }
            val aliases = linkedMapOf<String, String>()
            repeat(requests.length()) { index ->
                val item = requests.getJSONObject(index)
                val id = item.getString("id").trim()
                require(id.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { "Recruitment needs a stable vacancy ID" }
                require("recruit:$id" !in aliases) { "Duplicate vacancy ID" }
                require((0 until work.length()).any { work.optJSONObject(it)?.optString("member") == "recruit:$id" }) {
                    "A recruit must have concrete assigned work in this batch"
                }
                val template = requireNotNull(templates[item.getString("template_member")]) { "Use an existing authorized member as template" }
                val role = item.getString("role").trim()
                val scope = item.getString("scope").trim()
                require(role.isNotBlank() && role.length <= 240 && scope.isNotBlank() && scope.length <= 2000 &&
                    item.getString("reason").isNotBlank()) { "Recruitment needs a role, distinct scope and reason" }
                val signature = fingerprint(listOf(template.agentId, template.context["collaboration_model_id"].orEmpty(), role, scope))
                val personId = UUID.nameUUIDFromBytes(
                    "${template.context["collaboration_group_id"]}:recruit:$signature".toByteArray()).toString()
                val sameId = roster.firstOrNull { it.context[VACANCY] == id }
                require(sameId == null || sameId.context[SIGNATURE] == signature) { "A vacancy ID cannot be reused for a different role or scope" }
                val existing = sameId ?: roster.firstOrNull { it.context[SIGNATURE] == signature ||
                    it.context[CollaborationResearchWorkflow.PERSON] == personId }
                require(existing == null || existing.agentId == template.agentId && existing.role.equals(role, true) &&
                    existing.context["collaboration_model_id"].orEmpty() == template.context["collaboration_model_id"].orEmpty()) {
                    "Existing member was edited; reuse its current role or choose a distinct scope"
                }
                val person = existing ?: run {
                    require(roster.size < CollaborationGroup.MAX_MEMBERS) { "Group directory is full; reassign existing members instead" }
                    template.copy(instanceId = personId, deliveryMode = AgentDeliveryMode.IGNORE,
                        role = role, objective = scope, dependsOnAgentIds = emptySet(),
                        context = (template.context - CollaborationGoalLoop.WORK_ID) + mapOf(
                            CollaborationGoalLoop.ROSTER to "true", CollaborationResearchWorkflow.PERSON to personId,
                            "collaboration_name" to CollaborationNamePolicy.allocate(names, roster.map { it.context["collaboration_name"].orEmpty() }),
                            "_galaxyssi_role_hint" to role, "collaboration_receive_results" to "false",
                            VACANCY to id, SIGNATURE to signature, TEMPLATE to template.context.getValue(CollaborationResearchWorkflow.PERSON),
                            PUBLISHED to "false"
                        )).also(roster::add)
                }
                aliases["recruit:$id"] = person.context.getValue(CollaborationResearchWorkflow.PERSON)
            }
            val identities = roster.mapTo(hashSetOf()) { it.context.getValue(CollaborationResearchWorkflow.PERSON) }
            require((0 until work.length()).all { index -> work.getJSONObject(index).let {
                (aliases[it.optString("member")] ?: it.optString("member")) in identities &&
                    it.optString("assignment").isNotBlank() &&
                    !CollaborationResourceRecovery.isReservedWorkId(it.optString("id")) &&
                    it.optString("stage") in setOf("EXECUTE", "EXPLORE", "CHALLENGE", "VERIFY", "REVISE")
            } }) { "Recruitment and all assignments must form a valid plan" }
            Plan(roster, aliases)
        }.getOrElse { Plan(people, emptyMap(), it.message ?: "Invalid recruitment request") }
    }

    private fun fingerprint(parts: List<String>) = UUID.nameUUIDFromBytes(parts.joinToString("\u001f") {
        it.trim().lowercase(Locale.ROOT).replace(Regex("\\s+"), " ")
    }.toByteArray()).toString()

    /** Idempotent projection into the editable group directory; never overwrite user changes. */
    fun project(group: CollaborationGroup, recruits: List<AgentTeamMember>, names: List<String>): Pair<CollaborationGroup, Map<String, String>> {
        val members = group.members.toMutableList()
        val admitted = linkedMapOf<String, String>()
        recruits.forEach { person ->
            val id = person.context.getValue(CollaborationResearchWorkflow.PERSON)
            val template = members.firstOrNull { it.id == person.context[TEMPLATE] } ?: return@forEach
            if (template.agentId != person.agentId || template.modelId != person.context["collaboration_model_id"].orEmpty() ||
                !template.observeMessages || template.participation == CollaborationParticipation.MENTION_ONLY) return@forEach
            val existing = members.firstOrNull { it.id == id }
            if (existing != null) {
                if (existing.agentId == person.agentId && existing.modelId == template.modelId && existing.role == person.role && existing.observeMessages &&
                    existing.participation != CollaborationParticipation.MENTION_ONLY) admitted[id] = existing.name
                return@forEach
            }
            if (members.size >= CollaborationGroup.MAX_MEMBERS) return@forEach
            val proposed = person.context.getValue("collaboration_name")
            val name = if (members.none { it.name.equals(proposed, true) }) proposed else
                CollaborationNamePolicy.allocate(names, members.map { it.name })
            members += CollaborationMember(id = id, name = name, agentId = person.agentId,
                providerLabel = person.context["collaboration_provider"].orEmpty(), role = person.role,
                modelId = template.modelId, receiveResults = false, independentReview = true)
            admitted[id] = name
        }
        return group.copy(members = members).validate() to admitted
    }

    fun applyProjection(record: AgentTeamExecutionRecord, names: Map<String, String>): AgentTeamExecutionRecord {
        val pending = record.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" && it.context[PUBLISHED] == "false" }
        val pendingIds = pending.mapTo(hashSetOf()) { it.context.getValue(CollaborationResearchWorkflow.PERSON) }
        val rejected = pendingIds - names.keys
        val removedNodes = record.definition.members.filter { it.context[CollaborationResearchWorkflow.PERSON] in rejected }
            .mapTo(hashSetOf()) { it.memberId }
        // Never run a dependent assignment after deleting the producer it requires.
        do {
            val size = removedNodes.size
            record.definition.members.filter { it.memberId != record.definition.primaryMemberId &&
                it.dependsOnAgentIds.any(removedNodes::contains) }.mapTo(removedNodes) { it.memberId }
        } while (removedNodes.size != size)
        val members = record.definition.members.filterNot { it.memberId in removedNodes }.map { member ->
            val id = member.context[CollaborationResearchWorkflow.PERSON]
            member.copy(dependsOnAgentIds = member.dependsOnAgentIds - removedNodes,
                context = if (id in pendingIds && id in names) member.context + mapOf(
                    "collaboration_name" to names.getValue(id!!), PUBLISHED to "true") else member.context)
        }
        return record.copy(definition = record.definition.copy(members = members), request = record.request.copy(
            context = record.request.context + (FEEDBACK to if (rejected.isEmpty()) "" else
                "Recruitment was not admitted for $rejected: template was removed/changed or directory capacity exhausted. Reassign authorized existing members or state the missing permission; do not bypass it.")))
    }
}
