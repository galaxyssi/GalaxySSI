package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic model turns through the production registry; no model or external tool is called. */
@RunWith(AndroidJUnit4::class)
class CollaborationLocalToolsDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun ordinaryChatIsUnchangedAndOnlyExactBindingsExposeCollaborationTools() = fixture { access, source ->
        val ordinary = LocalModelWebToolRunner.registry(context, "ordinary", "turn", null).availableCatalog().descriptors
        val previous = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
            .subset { it.id in LocalModelWebToolProtocol.toolIds }.availableCatalog().descriptors
        assertEquals(previous.map { it.id }, ordinary.map { it.id })
        val bound = registry(access, source).availableCatalog().descriptors
        assertEquals(setOf(CollaborationRecallNativeTool.ID, CollaborationMilestoneNativeTool.ID),
            bound.mapTo(linkedSetOf()) { it.id } - ordinary.mapTo(linkedSetOf()) { it.id })
        val prompt = LocalModelWebToolProtocol.systemPrompt(bound)
        assertTrue(prompt.contains(CollaborationMilestoneTool.DESCRIPTION))
        assertTrue(prompt.contains("Keep the requested final research JSON intact"))
        assertTrue(bound.single { it.id == CollaborationMilestoneNativeTool.ID }.requiresEffectClaim)
        assertTrue(runCatching { LocalModelWebToolRunner.registry(context, access.groupId, "other-turn", source) }.isFailure)
        assertTrue(runCatching { LocalModelWebToolRunner.registry(context, "other-group", access.turnId, source) }.isFailure)
    }

    @Test fun syntheticModelCanPublishObserveAndRecallBeforeFinalDelivery() = fixture { access, source -> runBlocking {
        val registry = registry(access, source)
        var round = 0
        var objectId = ""
        val adapter = AgentModelAdapter { request ->
            when (round++) {
                0 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("publish", CollaborationMilestoneNativeTool.ID, input("m1"))))
                1 -> {
                    val result = request.messages.last().toolResult!!
                    assertEquals(false, result.output["assignment_completed"])
                    val revisions = result.output["revisions"] as List<*>
                    objectId = (revisions.single() as Map<*, *>)["object_id"] as String
                    assertNotNull(result.nativeResult?.get("galaxyssi_evidence_receipt"))
                    AgentModelResponse(toolCalls = listOf(AgentModelToolCall("recall", CollaborationRecallNativeTool.ID,
                        mapOf("mode" to "workspace", "object_id" to objectId, "revision" to 1))))
                }
                else -> {
                    assertTrue(AgentNativeJsonCodec.stringify(request.messages.last().toolResult!!.output).contains("Synthetic candidate body"))
                    AgentModelResponse(assistantText = finalArtifact())
                }
            }
        }
        val result = AgentModelToolLoop(modelAdapter = adapter, toolRegistry = registry).run(AgentModelToolLoopRequest(
            sessionId = access.groupId, conversationId = access.groupId, turnId = access.turnId,
            taskId = access.nodeId, collaborationSourceMessageId = source, workspaceId = access.groupId,
            loopId = "fixture", messages = listOf(AgentModelMessage.user("Synthetic publication fixture"))))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
        assertEquals(finalArtifact(), result.assistantText)
        assertEquals(3, round)
        assertNotNull(CollaborationResearchWorkspace(context).read(access, objectId, 1))
        assertNull(CollaborationResearchWorkspace(context).publicationCheckpoint(access))
    } }

    @Test fun retryAndReopenPreserveOneOriginalAndDoNotCompleteAssignment() = fixture { access, source ->
        val first = invoke(access, source, input("m1"))
        assertEquals(first.toString(), invoke(access, source, input("m1")).toString())
        val list = invoke(access, source, mapOf("mode" to "list"))
        assertEquals(1, list.getJSONArray("milestones").length())
        assertFalse(first.getBoolean("assignment_completed"))
        val workspace = CollaborationResearchWorkspace(context)
        assertNull(workspace.publicationCheckpoint(access))
        assertEquals(1, workspace.browse(access).revisions.size)
        val final = workspace.submitPublication(access, finalArtifact())
        assertEquals("recorded", final.getString("status"))
        assertEquals(first.getJSONArray("revisions").toString(), final.getJSONArray("revisions").toString())
    }

    @Test fun pauseStopRemovalAndWrongTurnCannotPublishNewWork() = fixture { access, source ->
        val control = AgentTeamDurableControl(context)
        listOf(AgentTeamUserControl.PAUSE, AgentTeamUserControl.STOP).forEach { state ->
            control.set(access.runId, state)
            assertFalse(invoke(access, source, input("m1"), success = false).getBoolean("success"))
        }
        control.set(access.runId, AgentTeamUserControl.RUN)
        val native = AgentNativeToolRegistry().registerAll(CollaborationMilestoneNativeTool.definitions(context))
        val wrong = native.invoke(CollaborationMilestoneNativeTool.ID, input("m1"), invocation(access.copy(turnId = "other"), source))
        assertEquals("dispatch_unavailable", wrong.error?.code)
        assertTrue(CollaborationResearchWorkspace(context).browse(access).revisions.isEmpty())
        invoke(access, source, input("m1"))
        CollaborationGroupStore(context).update(access.groupId) {
            it.copy(members = it.members.filterNot { member -> member.id == access.personId }, coordinatorId = "peer")
        }
        assertTrue(runCatching { registry(access, source) }.isFailure)
        val removed = native.invoke(CollaborationMilestoneNativeTool.ID, input("m2"), invocation(access, source))
        assertEquals("dispatch_unavailable", removed.error?.code)
    }

    @Test fun rejectedDraftKeepsDiagnosticsAndCanBeFixedWithoutReplacingAcceptedWork() = fixture { access, source ->
        val bad = invoke(access, source, input("m1") + ("artifact" to "not JSON"), success = false)
        assertTrue(bad.getString("reason").isNotBlank())
        invoke(access, source, input("m1"))
        val changed = input("m1") + ("artifact" to raw("different"))
        assertFalse(invoke(access, source, changed, success = false).getBoolean("success"))
        assertEquals(1, CollaborationResearchWorkspace(context).browse(access).revisions.size)
    }

    @Test fun finalRepairDisclosesOnlyRecallAndRejectsBypassPublication() = fixture { access, source ->
        val workspace = CollaborationResearchWorkspace(context)
        assertEquals("rejected", workspace.submitPublication(access, "not JSON").getString("status"))
        assertEquals(listOf(CollaborationRecallNativeTool.ID), registry(access, source).availableCatalog().descriptors.map { it.id })
        val direct = AgentNativeToolRegistry().registerAll(CollaborationMilestoneNativeTool.definitions(context))
            .invoke(CollaborationMilestoneNativeTool.ID, input("m1"), invocation(access, source))
        assertEquals("publication_repair_only", direct.error?.code)
        assertTrue(workspace.browse(access).revisions.isEmpty())
    }

    @Test fun independentPeerCannotReadThePublicationUntilDependencyIsGranted() = fixture { access, source ->
        val published = invoke(access, source, input("m1"))
        val ref = published.getJSONArray("revisions").getJSONObject(0)
        val peer = access.copy(nodeId = "peer-node", personId = "peer")
        val ledger = CollaborationEvidenceLedger(context)
        ledger.bind(source + 1, peer)
        val input = mapOf("mode" to "workspace", "object_id" to ref.getString("object_id"), "revision" to 1)
        val isolated = registry(peer, source + 1).invoke(CollaborationRecallNativeTool.ID, input, invocation(peer, source + 1))
        assertEquals(AgentNativeToolResultStatus.FAILED, isolated.status)
        assertFalse(AgentNativeJsonCodec.stringify(isolated.output).contains("Synthetic candidate body"))
        val dependent = peer.copy(nodeId = "dependent", dependencyNodes = setOf(access.nodeId))
        ledger.bind(source + 2, dependent)
        val read = registry(dependent, source + 2).invoke(CollaborationRecallNativeTool.ID, input, invocation(dependent, source + 2))
        assertEquals(AgentNativeToolResultStatus.SUCCEEDED, read.status)
        assertTrue(AgentNativeJsonCodec.stringify(read.output).contains("Synthetic candidate body"))
    }

    private fun registry(access: CollaborationWorkspaceAccess, source: Long) =
        LocalModelWebToolRunner.registry(context, access.groupId, access.turnId, source)

    private fun invocation(access: CollaborationWorkspaceAccess, source: Long) = AgentNativeToolInvocationContext(
        conversationId = access.groupId, turnId = access.turnId, sessionId = access.groupId,
        collaborationSourceMessageId = source)

    private fun invoke(access: CollaborationWorkspaceAccess, source: Long, input: Map<String, Any?>, success: Boolean = true): JSONObject {
        val result = registry(access, source).invoke(CollaborationMilestoneNativeTool.ID, input, invocation(access, source))
        assertEquals(result.toString(), success, result.status == AgentNativeToolResultStatus.SUCCEEDED)
        if (!success) assertEquals("publication_rejected", result.error?.code)
        return JSONObject(result.output)
    }

    private fun input(id: String): Map<String, Any?> = mapOf("mode" to "publish", "milestone_id" to id, "artifact" to raw(id))
    private fun raw(id: String) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Synthetic candidate").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", "proposal").put("title", "Fixture")
            .put("body", JSONObject().put("content", "Synthetic candidate body")))).toString()
    private fun finalArtifact() = JSONObject(raw("unused")).put("workspace", JSONArray())
        .put("milestones", JSONArray(listOf("m1"))).toString()

    private fun fixture(block: (CollaborationWorkspaceAccess, Long) -> Unit) {
        val id = "local-collaboration-test-${UUID.randomUUID()}"
        val source = (UUID.randomUUID().mostSignificantBits and Long.MAX_VALUE).coerceAtLeast(1).coerceAtMost(Long.MAX_VALUE - 2)
        val access = CollaborationWorkspaceAccess(id, id, "turn", 1, "node", "author")
        val groups = CollaborationGroupStore(context)
        groups.update(id) { it.copy(members = listOf("author", "peer").map { person ->
            CollaborationMember(person, person, "fixture", "Fixture") }, coordinatorId = "author") }
        CollaborationResearchWorkspace(context).enrollPublication(access, CollaborationResearchStage.EXPLORE)
        CollaborationEvidenceLedger(context).bind(source, access)
        try { block(access, source) } finally {
            CollaborationResearchWorkspace(context).removeGroup(id)
            CollaborationEvidenceLedger.remove(context, id)
            groups.remove(id)
            AgentTeamDurableControl(context).remove(id)
        }
    }
}
