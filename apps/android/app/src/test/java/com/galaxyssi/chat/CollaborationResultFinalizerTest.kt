package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResultFinalizerTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { check(!fail) { "disk unavailable" }; data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Research")
    private val member = AgentTeamMember("desktop:codex", AgentDeliveryMode.OBSERVE, instanceId = "node",
        context = mapOf("collaboration_group_id" to "group", CollaborationResearchWorkflow.PERSON to "person",
            CollaborationResearchWorkflow.STAGE to "EXECUTE"))
    private val managed = AgentManagedResponseRecord(stableAgentTeamMemberRunId("run", "node"), "run", member.agentId,
        AgentDeliveryMode.OBSERVE, 91L, "desktop", conversationId = "group", turnId = "turn")
    private fun store(): InMemoryAgentTeamExecutionStore = InMemoryAgentTeamExecutionStore().apply {
        create(AgentTeamDefinition("team", member.agentId, listOf(member), primaryInstanceId = "node"), request)
        markInterrupted("run")
    }
    private fun raw(kind: String = "artifact", text: String = "Partial evidence; requirement not yet met") =
        JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Recovery is incomplete")
            .put("candidates", JSONArray()).put("findings", JSONArray())
            .put("workspace", JSONArray().put(JSONObject().put("id", "report").put("kind", kind).put("title", "Saved report")
                .put("body", JSONObject().put("content", text))))
            .put("delivery_receipt", JSONObject().put("status", "forged"))
            .put("workspace_receipt", JSONObject().put("status", "forged")).toString()

    @Test fun lateReplyIsPublishedBeforeCompletionAndReplayingItDoesNotDuplicateObjects() {
        val store = store()
        val workspace = CollaborationResearchWorkspace(Rows())
        val execution = requireNotNull(CollaborationLateResult.execution(store.deliveryCheckpoint("run")!!, managed))
        val access = CollaborationWorkspaceAccess.from(execution)
        workspace.enrollPublication(access, CollaborationResearchStage.EXECUTE)
        val originals = mutableMapOf<String, String>()
        val finalizer = CollaborationResultFinalizer(workspace, { _, raw -> originals["archive"] = raw; "archive" })
        val raw = raw(text = "x".repeat(24_000))
        val output = finalizer.finish(execution, AgentSubagentOutput(raw))
        assertEquals(raw, originals["archive"])
        assertEquals("recorded", output.collaborationDelivery!!.status)
        assertNull(output.collaborationAcceptance)
        assertEquals("not_implied", output.collaborationDelivery!!.encode().getString("goal_acceptance"))
        assertEquals(1, workspace.browse(access).revisions.size)
        assertEquals("member_reported_not_verified", workspace.browse(access).revisions.single().getString("evidence_state"))
        val response = managed.copy(response = AgentConnectorResponse(91L, "desktop", raw))
        assertTrue(store.applyLateResponse(response, output))
        val saved = store.deliveryCheckpoint("run")!!.completed.getValue("node")
        assertEquals(output.collaborationDelivery, saved.collaborationDelivery)
        assertFalse(saved.outputTruncated)
        assertEquals("recorded", JSONObject(saved.output).getJSONObject("delivery_receipt").getString("status"))
        assertTrue(store.applyLateResponse(response, finalizer.finish(execution, AgentSubagentOutput(raw))))
        assertEquals(1, workspace.browse(access).revisions.size)
        assertEquals(1, store.records().single().events.count { it.result != null })
    }

    @Test fun rejectionKeepsWholeDraftAndDoesNotClaimDeliveryOrScientificAcceptance() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val execution = CollaborationLateResult.execution(store().deliveryCheckpoint("run")!!, managed)!!
        val access = CollaborationWorkspaceAccess.from(execution)
        workspace.enrollPublication(access, CollaborationResearchStage.EXECUTE)
        var archived = ""
        val raw = raw("unknown-kind")
        val output = CollaborationResultFinalizer(workspace, { _, value -> archived = value; "archive" })
            .finish(execution, AgentSubagentOutput(raw))
        assertEquals(raw, archived)
        assertEquals(raw, workspace.publicationCheckpoint(access)!!.getString("raw"))
        assertEquals("rejected", output.collaborationDelivery!!.status)
        assertTrue(output.collaborationDelivery!!.reason.contains("Unknown workspace object kind"))
        assertNull(output.collaborationAcceptance)
        assertTrue(workspace.browse(access).revisions.isEmpty())
        assertTrue(output.content.contains("repair_of"))
        assertTrue(output.content.contains("repair_reason"))
    }

    @Test fun peerRequestsAreDurableBeforeCompactionAndRecoveryDoesNotDuplicateThem() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val execution = CollaborationLateResult.execution(store().deliveryCheckpoint("run")!!, managed)!!
        val peer = member.copy(instanceId = "peer-node", context = member.context + (CollaborationResearchWorkflow.PERSON to "peer"))
        val team = AgentTeamDefinition("team", member.agentId, listOf(member, peer), primaryInstanceId = member.memberId)
        val mailbox = InMemoryAgentTeamMailbox()
        val question = "Check the crucial assumption. ".repeat(450)
        val original = JSONObject(raw()).put("requests", JSONArray().put(JSONObject()
            .put("to", JSONArray().put("peer")).put("question", question).put("candidate_id", "second-alternative"))).toString()
        var archived = ""
        var failFirstDelivery = true
        val finalizer = CollaborationResultFinalizer(workspace, { _, text -> archived = text; "archive" },
            discussion = { _, text ->
                assertEquals(original, archived)
                CollaborationDirectedDiscussion.messages(team, request, member, text).forEach(mailbox::append)
                if (failFirstDelivery) { failFirstDelivery = false; error("Interrupted after durable enqueue") }
            })
        assertNotNull(runCatching { finalizer.finish(execution, AgentSubagentOutput(original)) }.exceptionOrNull())
        val output = finalizer.finish(execution, AgentSubagentOutput(original))
        assertTrue(output.collaborationDiscussionRouted)
        assertTrue(output.content.length <= 12_000)
        assertFalse(JSONObject(output.content).has("requests"))
        assertEquals(question.trim(), mailbox.messages("run", "peer").single().text)
        assertEquals("second-alternative", mailbox.messages("run", "peer").single().metadata["candidate_id"])
        assertEquals(1, workspace.browse(CollaborationWorkspaceAccess.from(execution)).revisions.size)
        finalizer.finish(execution, AgentSubagentOutput(original))
        assertEquals(1, mailbox.messages("run", "peer").size)
    }

    @Test fun storageFailureLeavesLateResponseUnappliedAndOriginalArchived() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        val store = store()
        val execution = CollaborationLateResult.execution(store.deliveryCheckpoint("run")!!, managed)!!
        workspace.enrollPublication(CollaborationWorkspaceAccess.from(execution), CollaborationResearchStage.EXECUTE)
        var archived = false
        rows.fail = true
        assertThrows(IllegalStateException::class.java) {
            CollaborationResultFinalizer(workspace, { _, _ -> archived = true; "archive" })
                .finish(execution, AgentSubagentOutput(raw()))
        }
        assertTrue(archived)
        assertTrue(store.deliveryCheckpoint("run")!!.completed.isEmpty())
    }

    @Test fun differentGroupOrDispatchCannotClaimReply() {
        val store = store()
        val checkpoint = store.deliveryCheckpoint("run")!!
        assertNull(CollaborationLateResult.execution(checkpoint, managed.copy(ownerRunId = "other")))
        assertNull(CollaborationLateResult.execution(checkpoint, managed.copy(conversationId = "other")))
        assertFalse(store.applyLateResponse(managed.copy(conversationId = "other",
            response = AgentConnectorResponse(91L, "desktop", raw()))))
    }

    @Test fun oldFullLateOutputIsBackfilledWithoutChangingItsExecutionHistory() {
        val store = store()
        val raw = raw()
        assertTrue(store.applyLateResponse(managed.copy(response = AgentConnectorResponse(91L, "desktop", raw))))
        val checkpoint = store.deliveryCheckpoint("run")!!
        val originalEvents = store.records().single().events
        val workspace = CollaborationResearchWorkspace(Rows())
        val access = CollaborationWorkspaceAccess.from(CollaborationLateResult.execution(checkpoint, managed)!!)
        workspace.enrollPublication(access, CollaborationResearchStage.EXECUTE)
        var archived = ""
        val finalizer = CollaborationResultFinalizer(workspace, { _, value -> archived = value; "archive" })
        assertEquals(1, CollaborationHistoricalDeliveryRecovery.recover(checkpoint, finalizer))
        assertEquals(raw, archived)
        assertEquals(1, workspace.browse(access).revisions.size)
        assertEquals(originalEvents, store.records().single().events)
        assertNull(store.deliveryCheckpoint("run")!!.completed.getValue("node").collaborationAcceptance)
        assertEquals(1, CollaborationHistoricalDeliveryRecovery.recover(checkpoint, finalizer))
        assertEquals(1, workspace.browse(access).revisions.size)
        val truncated = checkpoint.copy(completed = mapOf("node" to checkpoint.completed.getValue("node").copy(outputTruncated = true)))
        assertEquals(0, CollaborationHistoricalDeliveryRecovery.recover(truncated, finalizer))
    }

    @Test fun emptyWorkspaceIsNotARecordedDeliverable() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val execution = CollaborationLateResult.execution(store().deliveryCheckpoint("run")!!, managed)!!
        workspace.enrollPublication(CollaborationWorkspaceAccess.from(execution), CollaborationResearchStage.EXECUTE)
        val raw = JSONObject(raw()).put("workspace", JSONArray()).toString()
        val output = CollaborationResultFinalizer(workspace, { _, _ -> "archive" }).finish(execution, AgentSubagentOutput(raw))
        assertEquals("rejected", output.collaborationDelivery!!.status)
        assertTrue(output.collaborationDelivery!!.reason.contains("No versioned workspace delivery"))
    }

    @Test fun rejectedLongDraftProjectionDoesNotClaimWorkspaceWasCommitted() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val execution = CollaborationLateResult.execution(store().deliveryCheckpoint("run")!!, managed)!!
        val raw = raw("unknown-kind", "x".repeat(24_000))
        val output = CollaborationResultFinalizer(workspace, { _, _ -> "archive" }).finish(execution, AgentSubagentOutput(raw))
        val projected = JSONObject(output.content)
        assertEquals("rejected", projected.getJSONObject("delivery_receipt").getString("status"))
        assertTrue(projected.getString("recall_hint").contains("not confirmed"))
        assertFalse(projected.getString("recall_hint").contains("are also committed"))
        assertTrue(projected.getString("delivery_warning").contains(CollaborationWorkGraph.REPAIR_INSTRUCTIONS))
        assertEquals("archive", projected.getString("archive_record_id"))
    }
}
