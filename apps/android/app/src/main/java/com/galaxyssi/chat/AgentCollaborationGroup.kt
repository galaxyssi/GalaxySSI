package com.galaxyssi.chat

import java.util.Locale
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal enum class CollaborationParticipation { MENTION_ONLY, BY_ROLE, PROACTIVE }

internal data class CollaborationMember(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val agentId: String,
    val providerLabel: String,
    val role: String = "",
    val participation: CollaborationParticipation = CollaborationParticipation.BY_ROLE,
    val observeMessages: Boolean = true,
    val receiveResults: Boolean = true,
    val independentReview: Boolean = false,
    val modelId: String = ""
) {
    fun requested(groupId: String, roleOverride: String = "") = AgentRequestedMember(
        agentId = agentId,
        displayName = name,
        roleHint = listOf(role, roleOverride).filter(String::isNotBlank).joinToString(". "),
        persistentInstanceId = id,
        collaborationGroupId = groupId,
        providerLabel = providerLabel,
        receivePeerResults = receiveResults && observeMessages && !independentReview,
        modelId = modelId
    )
}

internal data class CollaborationGroup(
    val conversationId: String,
    val members: List<CollaborationMember> = emptyList(),
    val coordinatorId: String = members.firstOrNull()?.id.orEmpty(),
    val revision: Long = 0,
    val workflow: CollaborationWorkflow = CollaborationWorkflow.AUTO
) {
    fun validate(): CollaborationGroup {
        require(conversationId.isNotBlank())
        require(members.size <= MAX_MEMBERS)
        require(members.map { it.id }.toSet().size == members.size)
        require(members.map { it.name.lowercase(Locale.ROOT) }.toSet().size == members.size)
        require(members.all { it.id.isNotBlank() && it.agentId.isNotBlank() &&
            it.name.isNotBlank() && it.name.length <= 48 && it.role.length <= 240 })
        require(members.isEmpty() || members.any { it.id == coordinatorId })
        return this
    }

    fun requested(explicit: List<AgentRequestedMember>): List<AgentRequestedMember> {
        if (explicit.isNotEmpty()) return explicit.map { it.copy(collaborationWorkflow = workflow.name) }
        return members.filter { it.observeMessages && it.participation != CollaborationParticipation.MENTION_ONLY }
            .sortedBy { if (it.id == coordinatorId) 0 else 1 }
            .map { it.requested(conversationId).copy(collaborationWorkflow = workflow.name) }
    }

    companion object { const val MAX_MEMBERS = 1024 }
}

internal object CollaborationNamePolicy {
    fun allocate(names: List<String>, used: Collection<String>): String {
        val occupied = used.mapTo(hashSetOf()) { it.lowercase(Locale.ROOT) }
        return names.firstOrNull { it.lowercase(Locale.ROOT) !in occupied }
            ?: error("No unused collaboration names remain")
    }

    fun validate(names: List<String>): List<String> {
        require(names.size >= CollaborationGroup.MAX_MEMBERS)
        require(names.all { it.matches(Regex("[A-Za-z]+(?: [A-Za-z]+)*")) })
        require(names.map { it.lowercase(Locale.ROOT) }.toSet().size == names.size)
        return names
    }
}

internal object CollaborationMentionPolicy {
    fun resolve(text: String, members: List<CollaborationMember>): List<CollaborationMember> {
        if ('@' !in text) return emptyList()
        val names = members.sortedByDescending { it.name.length }
        val selected = linkedMapOf<String, CollaborationMember>()
        var index = 0
        while (index < text.length) {
            if (text[index] == '@' && (index == 0 || !text[index - 1].isLetterOrDigit())) {
                val member = names.firstOrNull { candidate ->
                    text.regionMatches(index + 1, candidate.name, 0, candidate.name.length, true) &&
                        (index + 1 + candidate.name.length == text.length ||
                            !text[index + 1 + candidate.name.length].isLetterOrDigit())
                }
                if (member != null) {
                    selected[member.id] = member
                    index += member.name.length
                }
            }
            index++
        }
        return selected.values.toList()
    }
}

internal object CollaborationGroupCodec {
    fun encode(group: CollaborationGroup): String = JSONObject()
        .put("conversation_id", group.validate().conversationId)
        .put("coordinator_id", group.coordinatorId)
        .put("revision", group.revision)
        .put("workflow", group.workflow.name)
        .put("members", JSONArray().apply {
            group.members.forEach { member -> put(JSONObject()
                .put("id", member.id).put("name", member.name).put("agent_id", member.agentId)
                .put("provider_label", member.providerLabel).put("role", member.role)
                .put("participation", member.participation.name)
                .put("observe", member.observeMessages).put("results", member.receiveResults)
                .put("independent_review", member.independentReview).put("model_id", member.modelId)) }
        }).toString()

    fun decode(raw: String): CollaborationGroup? = runCatching {
        val json = JSONObject(raw)
        val array = json.getJSONArray("members")
        require(array.length() <= CollaborationGroup.MAX_MEMBERS)
        CollaborationGroup(
            conversationId = json.getString("conversation_id"),
            coordinatorId = json.getString("coordinator_id"),
            revision = json.optLong("revision"),
            workflow = runCatching { CollaborationWorkflow.valueOf(json.optString("workflow")) }.getOrDefault(CollaborationWorkflow.AUTO),
            members = (0 until array.length()).map { index ->
                val member = array.getJSONObject(index)
                CollaborationMember(
                    id = member.getString("id"), name = member.getString("name"),
                    agentId = member.getString("agent_id"), providerLabel = member.getString("provider_label"),
                    role = member.optString("role"),
                    participation = CollaborationParticipation.valueOf(member.getString("participation")),
                    observeMessages = member.optBoolean("observe", true),
                    receiveResults = member.optBoolean("results", true),
                    independentReview = member.optBoolean("independent_review"),
                    modelId = member.optString("model_id")
                )
            }
        ).validate()
    }.getOrNull()
}
