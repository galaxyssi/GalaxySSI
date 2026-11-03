package com.galaxyssi.chat

import android.content.Context
import java.util.UUID
import org.json.JSONArray

/** Targeted questions are read at later checkpoints; they never spawn an uncontrolled reply loop. */
internal object CollaborationDirectedDiscussion {
    fun messages(definition: AgentTeamDefinition, request: AgentRunRequest,
        sender: AgentTeamMember, output: String): List<AgentTeamMessageEnvelope> = messages(definition.teamId,
        definition.members.mapNotNull { it.context[CollaborationResearchWorkflow.PERSON] }.toSet(), request, sender, output)

    fun persist(context: Context, execution: AgentTeamMemberExecutionContext, output: String) {
        val group = CollaborationGroupStore(context).load(execution.member.context["collaboration_group_id"].orEmpty()) ?: return
        val people = group.members.map { it.id }.toSet()
        if (execution.member.context[CollaborationResearchWorkflow.PERSON] !in people) return
        val parent = execution.request.parentRunId
        val teamId = execution.request.context["team_id"] as? String ?: error("Host team identity is missing")
        require(parent.isNotBlank()) { "Host supervisor identity is missing" }
        val mailbox = EncryptedAgentTeamMailbox(context)
        mailbox.appendAll(messages(teamId, people, execution.request.copy(runId = parent), execution.member, output))
    }

    private fun messages(teamId: String, people: Set<String>, request: AgentRunRequest,
        sender: AgentTeamMember, output: String): List<AgentTeamMessageEnvelope> {
        val stage = CollaborationResearchWorkflow.stage(sender) ?: return emptyList()
        if (stage == CollaborationResearchStage.DELIVER) return emptyList()
        val from = sender.context[CollaborationResearchWorkflow.PERSON] ?: return emptyList()
        val requests = CollaborationResearchArtifact.decode(output)?.optJSONArray("requests") ?: return emptyList()
        val identities = mutableMapOf<String, MutableSet<String>>()
        return buildList {
            repeat(requests.length()) { index ->
                val item = requests.optJSONObject(index) ?: return@repeat
                val question = item.getString("question").trim()
                if (question.isBlank()) return@repeat
                val targets = item.optJSONArray("to") ?: return@repeat
                val to = (0 until targets.length()).map { targets.getString(it) }
                    .distinct().filter { it in people && it != from }
                val candidate = item.optString("candidate_id")
                to.forEach { recipient ->
                    val legacyId = UUID.nameUUIDFromBytes(
                        "${request.runId}:${sender.memberId}:$recipient:$question".toByteArray()).toString()
                    val candidates = identities.getOrPut(legacyId) { linkedSetOf() }
                    if (!candidates.add(candidate)) return@forEach
                    // Keep the original ID for ordinary requests, but do not merge different candidate reviews.
                    val id = if (candidates.size == 1) legacyId else UUID.nameUUIDFromBytes(
                        JSONArray().put(legacyId).put(candidate).toString().toByteArray(Charsets.UTF_8)).toString()
                    add(AgentTeamMessageEnvelope(
                        messageId = id,
                        teamId = teamId, conversationId = request.conversationId,
                        supervisorRunId = request.runId, fromInstanceId = from, toInstanceId = recipient,
                        kind = AgentTeamMessageKind.REVIEW, text = question,
                        metadata = mapOf("candidate_id" to candidate,
                            "stage" to stage.name, "sender_name" to sender.context["collaboration_name"].orEmpty())))
                }
            }
        }
    }
}
