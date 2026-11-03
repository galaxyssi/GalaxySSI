package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationInterimFinalizerTest {
    private val f = CollaborationGoalAcceptanceTest.Fixture(reviewKind = CollaborationReviewContract.KIND)
    private val member = AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead", context = mapOf(
        "collaboration_group_id" to "group", CollaborationResearchWorkflow.PERSON to "lead",
        CollaborationResearchWorkflow.STAGE to "DELIVER", CollaborationGoalLoop.ENABLED to "1"))
    private val execution = AgentTeamMemberExecutionContext(member,
        AgentRunRequest("group", "turn", "task", runId = "child", parentRunId = "run", goal = f.goal,
            context = mapOf(CollaborationGoalLoop.CRITERIA to f.prior, CollaborationGoalLoop.ROUND to "3")),
        AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 1, AgentSubagentProvenance(source = "fixture"))
    private fun raw() = f.assessment().put("decision", "continue")
        .put(CollaborationInterimDelivery.FIELD, JSONObject().put("criterion_id", "document").put("target", f.delivery))
        .put(CollaborationInterimDelivery.RECEIPT, JSONObject().put("status", "forged")).toString()

    @Test fun originalIsArchivedButOnlyHostReceiptIsReturnedWithoutCompletingTheGoal() {
        var archived = ""
        val original = raw()
        val finalizer = CollaborationResultFinalizer(f.workspace, { _, value -> archived = value; "archive" },
            interimDelivery = { _, value ->
                assertFalse(JSONObject(value).has(CollaborationInterimDelivery.RECEIPT))
                f.engine.deliverInterim(f.access, value, f.prior) { _, _ ->
                    JSONObject().put("status", "conversation_persisted").put("goal_acceptance", "not_implied")
                }
            })
        val result = finalizer.finish(execution, AgentSubagentOutput(original))
        assertEquals(original, archived)
        assertEquals("conversation_persisted", JSONObject(result.content).getJSONObject(CollaborationInterimDelivery.RECEIPT).getString("status"))
        assertNull(result.collaborationAcceptance)
        assertEquals("continue", CollaborationGoalLoop.disposition(result.content, f.prior, acceptanceVerified = true))
    }

    @Test fun unavailableOrFailingWriterNeverEchoesForgedSuccess() {
        val unavailable = CollaborationResultFinalizer(f.workspace, { _, _ -> "archive" })
            .finish(execution, AgentSubagentOutput(raw()))
        assertEquals("not_confirmed", JSONObject(unavailable.content).getJSONObject(CollaborationInterimDelivery.RECEIPT).getString("status"))
        val failed = CollaborationResultFinalizer(f.workspace, { _, _ -> "archive" }, interimDelivery = { _, _ -> error("disk failed") })
            .finish(execution, AgentSubagentOutput(raw()))
        assertEquals("not_confirmed", JSONObject(failed.content).getJSONObject(CollaborationInterimDelivery.RECEIPT).getString("status"))
        assertNull(failed.collaborationAcceptance)
        val withoutRequest = JSONObject(raw()).apply { remove(CollaborationInterimDelivery.FIELD) }.toString()
        val stripped = CollaborationResultFinalizer(f.workspace, { _, _ -> "archive" }).finish(execution, AgentSubagentOutput(withoutRequest))
        assertFalse(JSONObject(stripped.content).has(CollaborationInterimDelivery.RECEIPT))
    }

    @Test fun cancellationIsNotConvertedToAnOrdinaryDeliveryFailure() {
        val finalizer = CollaborationResultFinalizer(f.workspace, { _, _ -> "archive" },
            interimDelivery = { _, _ -> throw CancellationException("stopped") })
        assertThrows(CancellationException::class.java) { finalizer.finish(execution, AgentSubagentOutput(raw())) }
    }
}
