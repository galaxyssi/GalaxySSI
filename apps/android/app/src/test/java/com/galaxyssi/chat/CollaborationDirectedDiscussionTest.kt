package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationDirectedDiscussionTest {
    private val people = (0..8).map { index -> AgentTeamMember("codex", AgentDeliveryMode.OBSERVE,
        instanceId = "node-$index", context = mapOf(CollaborationResearchWorkflow.PERSON to "person-$index",
            CollaborationResearchWorkflow.STAGE to "EXECUTE")) }
    private val team = AgentTeamDefinition("team", "codex", people, primaryInstanceId = people.first().memberId)
    private val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Compare alternatives")
    private fun question(text: String, candidate: String = "C1", recipients: List<String> = listOf("person-1")) =
        JSONObject().put("question", text).put("candidate_id", candidate).put("to", JSONArray(recipients))
    private fun artifact(requests: JSONArray) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Evidence and questions").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("requests", requests)
    private fun messages(requests: JSONArray) = CollaborationDirectedDiscussion.messages(team, request, people.first(), artifact(requests).toString())

    @Test fun everyRequestReachesEveryDistinctInGroupRecipient() {
        val recipients = (1..8).map { "person-$it" }
        val requests = JSONArray((1..7).map { question("Challenge $it", recipients = recipients) })
        val result = messages(requests)
        assertEquals(56, result.size)
        assertEquals(56, result.map { it.messageId }.distinct().size)
        recipients.forEach { target -> assertEquals(7, result.count { it.toInstanceId == target }) }
    }

    @Test fun longQuestionsAndCandidateReferencesSurviveMailboxCodecAndReplay() {
        val text = "Important premise. ".repeat(100) + "Falsify the alternative, not the original."
        val candidate = "candidate-" + "x".repeat(160)
        val requests = JSONArray().put(question(text, candidate))
        val mailbox = InMemoryAgentTeamMailbox()
        messages(requests).forEach(mailbox::append)
        val restored = InMemoryAgentTeamMailbox(AgentTeamMessageCodec.decode(AgentTeamMessageCodec.encode(mailbox.snapshot()).toString()))
        messages(requests).forEach(restored::append)
        val saved = restored.messages("run", "person-1").single()
        assertEquals(text, saved.text)
        assertEquals(candidate, saved.metadata["candidate_id"])
    }

    @Test fun differentQuestionsWithTheSameLongPrefixAreNotMerged() {
        val prefix = "x".repeat(1200)
        val result = messages(JSONArray().put(question(prefix + "first")).put(question(prefix + "second")))
        assertEquals(2, result.map { it.messageId }.distinct().size)
        assertTrue(result[0].text.endsWith("first"))
        assertTrue(result[1].text.endsWith("second"))
    }

    @Test fun distinctCandidateReviewsDoNotCollideAndExactDuplicatesRemainIdempotent() {
        val requests = JSONArray().put(question("Check this", "C1")).put(question("Check this", "C2"))
            .put(question("Check this", "C1")).put(question("Check this", "C2"))
        val result = messages(requests)
        assertEquals(2, result.size)
        assertEquals(setOf("C1", "C2"), result.map { it.metadata["candidate_id"] }.toSet())
        assertEquals(2, result.map { it.messageId }.distinct().size)
        assertEquals(result.map { it.messageId }, messages(requests).map { it.messageId })
        val legacy = UUID.nameUUIDFromBytes("run:${people.first().memberId}:person-1:Check this".toByteArray()).toString()
        assertEquals(legacy, result.first().messageId)
    }

    @Test fun routingStillExcludesSelfOutsidersAndDuplicateRecipients() {
        val result = messages(JSONArray().put(question("Review", recipients = listOf("person-0", "outsider", "person-1", "person-1", "person-8"))))
        assertEquals(listOf("person-1", "person-8"), result.map { it.toInstanceId })
        assertTrue(result.all { it.kind == AgentTeamMessageKind.REVIEW && !it.isBroadcast })
    }

    @Test fun overlargeOrMalformedRequestsProduceSpecificRepairFeedbackInsteadOfBeingTruncated() {
        val cases = listOf(
            question("x".repeat(16_001)) to "requests[0].question",
            question(" ") to "requests[0].question",
            question("Review").put("question", 42) to "requests[0].question",
            question("Review", recipients = emptyList()) to "requests[0].to",
            question("Review", recipients = listOf(" person-1")) to "requests[0].to[0]",
            question("Review").put("to", JSONArray().put(42)) to "requests[0].to[0]",
            question("Review", "x".repeat(1001)) to "requests[0].candidate_id"
        )
        cases.forEach { (item, field) ->
            val raw = artifact(JSONArray().put(item)).toString()
            assertNull(CollaborationResearchArtifact.decode(raw))
            assertTrue(CollaborationResearchArtifact.validationError(raw), CollaborationResearchArtifact.validationError(raw).contains(field))
        }
        val exact = "x".repeat(16_000)
        assertEquals(exact, messages(JSONArray().put(question(exact))).single().validated().text)
    }
}
