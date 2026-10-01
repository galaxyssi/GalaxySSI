package com.galaxyssi.chat

import java.util.UUID

/** Targeted questions are read at later checkpoints; they never spawn an uncontrolled reply loop. */
internal object CollaborationDirectedDiscussion {
    fun messages(definition: AgentTeamDefinition, request: AgentRunRequest,
        sender: AgentTeamMember, output: String): List<AgentTeamMessageEnvelope> {
        val stage = CollaborationResearchWorkflow.stage(sender) ?: return emptyList()
        if (stage == CollaborationResearchStage.DELIVER) return emptyList()
        val people = definition.members.mapNotNull { it.context[CollaborationResearchWorkflow.PERSON] }.toSet()
        val from = sender.context[CollaborationResearchWorkflow.PERSON] ?: return emptyList()
        val requests = CollaborationResearchArtifact.decode(output)?.optJSONArray("requests") ?: return emptyList()
        return buildList {
            repeat(minOf(3, requests.length())) { index ->
                val item = requests.optJSONObject(index) ?: return@repeat
                val question = item.optString("question").trim().take(1200)
                if (question.isBlank()) return@repeat
                val targets = item.optJSONArray("to") ?: return@repeat
                val to = (0 until minOf(3, targets.length())).map { targets.optString(it) }
                    .distinct().filter { it in people && it != from }
                to.forEach { recipient ->
                    add(AgentTeamMessageEnvelope(
                        messageId = UUID.nameUUIDFromBytes(
                            "${request.runId}:${sender.memberId}:$recipient:$question".toByteArray()).toString(),
                        teamId = definition.teamId, conversationId = request.conversationId,
                        supervisorRunId = request.runId, fromInstanceId = from, toInstanceId = recipient,
                        kind = AgentTeamMessageKind.REVIEW, text = question,
                        metadata = mapOf("candidate_id" to item.optString("candidate_id").take(80),
                            "stage" to stage.name, "sender_name" to sender.context["collaboration_name"].orEmpty())))
                }
            }
        }
    }
}
