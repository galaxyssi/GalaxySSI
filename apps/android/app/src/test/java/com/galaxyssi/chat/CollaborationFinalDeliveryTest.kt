package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationFinalDeliveryTest {
    private fun fixture(reviewer: String = "reviewer") =
        CollaborationGoalAcceptanceTest.Fixture(reviewer = reviewer, reviewKind = CollaborationReviewContract.KIND)

    private fun proposal(f: CollaborationGoalAcceptanceTest.Fixture) = f.assessment()
        .put(CollaborationFinalDelivery.FIELD, JSONObject(f.delivery.toString()))

    private fun prepare(f: CollaborationGoalAcceptanceTest.Fixture, raw: JSONObject = proposal(f)) =
        CollaborationFinalDelivery.prepare(f.workspace, f.access, raw.toString())

    @Test fun savedReviewedTextBecomesTheExactFinalReplyAndReceiptBindsThatReply() {
        val f = fixture()
        val raw = proposal(f).put("summary", "Unreviewed extra claim")
        val prepared = prepare(f, raw)
        assertEquals("Unreviewed extra claim", raw.getString("summary"))
        assertEquals("Comparison with explicit limits", CollaborationGoalLoop.publicText(prepared))
        val receipt = f.evaluate(prepared)
        assertTrue(receipt.feedback, receipt.accepted)
        val record = f.record(prepared, receipt)
        assertTrue(record.acceptanceVerified(record.events.single().result))
        assertFalse(receipt.matches(raw.toString(), f.prior, f.goal, "run", "turn", "lead"))
    }

    @Test fun directAcceptanceRejectsAnUnreviewedParaphrase() {
        val f = fixture()
        val rejected = f.evaluate(proposal(f).toString())
        assertFalse(rejected.accepted)
        assertTrue(rejected.feedback, rejected.feedback.contains("complete saved content unchanged"))
    }

    @Test fun selectionDoesNotReplaceIndependentReviewOrUnsetCriteria() {
        val self = fixture("author")
        assertFalse(self.evaluate(prepare(self)).accepted)
        val f = fixture()
        val raw = proposal(f)
        raw.getJSONArray("criteria").getJSONObject(0).put("status", "open")
        assertThrows(IllegalArgumentException::class.java) { prepare(f, raw) }
        assertFalse(f.evaluate(raw.toString()).accepted)
    }

    @Test fun unrelatedSavedArtifactCannotReplaceTheReviewedDelivery() {
        val f = fixture()
        val extra = f.publish(f.access.copy(nodeId = "extra", round = 2),
            f.item("unreviewed", "artifact", JSONObject().put("content", "Not reviewed")))
        assertThrows(IllegalArgumentException::class.java) { prepare(f, proposal(f).put(CollaborationFinalDelivery.FIELD, extra)) }
    }

    @Test fun staleWrongScopeCorruptAndUnauthorizedSourcesFailClosed() {
        val f = fixture()
        val raw = proposal(f).toString()
        listOf(f.access.copy(groupId = "other"), f.access.copy(runId = "other"), f.access.copy(turnId = "other")).forEach { scope ->
            assertThrows(IllegalArgumentException::class.java) { CollaborationFinalDelivery.prepare(f.workspace, scope, raw) }
        }
        val forged = proposal(f)
        forged.getJSONObject(CollaborationFinalDelivery.FIELD).put("sha256", "0".repeat(64))
        forged.getJSONArray("criteria").getJSONObject(0).getJSONObject("delivery").put("sha256", "0".repeat(64))
        assertThrows(IllegalArgumentException::class.java) { prepare(f, forged) }
        f.authorized = false
        assertNotNull(runCatching { prepare(f) }.exceptionOrNull())
        f.authorized = true
        f.publish(f.access.copy(nodeId = "author-update", personId = "author", round = 2),
            f.item("changed", "artifact", JSONObject().put("content", "Changed after review"))
                .put("object_id", f.delivery.getString("object_id")).put("base_revision", 1))
        assertThrows(IllegalArgumentException::class.java) { CollaborationFinalDelivery.prepare(f.workspace, f.access, raw) }
        assertFalse(f.evaluate(raw).accepted)
    }

    @Test fun invalidOptionalFieldGetsPreciseFeedbackInsteadOfSilentIgnoring() {
        val f = fixture()
        listOf(JSONObject.NULL, "not a reference", JSONObject().put("object_id", "invented"),
            JSONObject(f.delivery.toString()).put("revision", 1.5)).forEach { bad ->
            val result = CollaborationAssessmentValidation.inspect(proposal(f).put(CollaborationFinalDelivery.FIELD, bad).toString())
            assertNull(result.assessment)
            assertEquals("$.final_delivery", result.failure!!.path)
            assertTrue(result.syntaxValid)
        }
        assertNull(CollaborationGoalLoop.decode(proposal(f).put("decision", "continue").toString()))
    }

    @Test fun existingAssessmentsAreNotRewrittenOrAutoAccepted() {
        val f = fixture()
        val raw = f.assessment().toString()
        assertEquals(raw, CollaborationFinalDelivery.prepare(f.workspace, f.access, raw))
        assertEquals("not json", CollaborationFinalDelivery.prepare(f.workspace, f.access, "not json"))
        val noReview = proposal(f)
        noReview.getJSONArray("criteria").getJSONObject(0).remove("review")
        assertFalse(f.evaluate(prepare(f, noReview)).accepted)
    }

    @Test fun finalizationAndRecoveryArchiveOriginalAndDoNotRepublishOrNeedAnotherModel() {
        val f = fixture()
        val raw = proposal(f).put("summary", "Model paraphrase must not replace the reviewed report").toString()
        val member = AgentTeamMember("codex", AgentDeliveryMode.RESPOND, instanceId = "lead", context = mapOf(
            "collaboration_group_id" to "group", CollaborationResearchWorkflow.PERSON to "lead",
            CollaborationResearchWorkflow.STAGE to "DELIVER", CollaborationGoalLoop.ENABLED to "1"))
        val request = AgentRunRequest("group", "turn", "task", runId = "child", parentRunId = "run", goal = f.goal,
            context = mapOf(CollaborationGoalLoop.CRITERIA to f.prior, CollaborationGoalLoop.ROUND to "3"))
        val execution = AgentTeamMemberExecutionContext(member, request,
            AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 1, AgentSubagentProvenance(source = "fixture"))
        val originals = mutableMapOf<String, String>()
        fun finalizer() = CollaborationResultFinalizer(f.workspace, { _, original -> originals["archive"] = original; "archive" },
            acceptance = { access, value, prior, goal -> f.engine.evaluate(access, value, prior, goal, 10) })
        val before = f.rows.data.toMap()
        val output = finalizer().finish(execution, AgentSubagentOutput(raw))
        val replay = finalizer().finish(execution, AgentSubagentOutput(raw))
        assertEquals(raw, originals["archive"])
        assertEquals(AgentNativeJsonCodec.sha256(raw), output.collaborationDelivery!!.originalSha256)
        assertEquals(output.content, replay.content)
        assertEquals(output.collaborationAcceptance, replay.collaborationAcceptance)
        assertTrue(output.collaborationAcceptance!!.feedback, output.collaborationAcceptance!!.accepted)
        assertEquals("Comparison with explicit limits", CollaborationGoalLoop.publicText(output.content))
        assertEquals(before, f.rows.data)
        assertEquals("not_implied", output.collaborationDelivery!!.encode().getString("goal_acceptance"))
        val record = f.record(output.content, output.collaborationAcceptance)
        assertTrue(record.acceptanceVerified(record.events.single().result))
    }

    @Test fun untruncatedLargeArtifactIsSelectedVerbatim() {
        val f = fixture()
        val longText = "Evidence and limitations.\n".repeat(3000)
        val ref = f.publish(f.access.copy(nodeId = "long", round = 2), f.item("long", "artifact", JSONObject().put("content", longText)))
        val raw = proposal(f).put(CollaborationFinalDelivery.FIELD, ref)
        raw.getJSONArray("criteria").getJSONObject(0).put("delivery", ref)
        assertEquals(longText, JSONObject(prepare(f, raw)).getString("summary"))
        assertFalse(f.evaluate(prepare(f, raw)).accepted) // The old review still targets a different document.
    }
}
