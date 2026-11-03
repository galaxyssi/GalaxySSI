package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPublicationRecoveryTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var failWrite = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { check(!failWrite); data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) =
            data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "person")
    private fun item(id: String = "proposal") = JSONObject().put("id", id).put("kind", "proposal")
        .put("title", "Candidate design").put("body", JSONObject().put("content", "Observed source, not a scientific claim"))
    private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Test contribution").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray(items.toList())).toString()
    private fun enroll(workspace: CollaborationResearchWorkspace) =
        workspace.enrollPublication(access, CollaborationResearchStage.VERIFY)

    @Test fun interruptedPublicationCompletesWithoutRedispatchAndReleasesCoordinator() = runBlocking {
        val workspace = CollaborationResearchWorkspace(Rows())
        enroll(workspace)
        val raw = raw(item())
        assertTrue(CollaborationPublicationRecovery(workspace, access).accept(raw))
        val store = InMemoryAgentTeamExecutionStore()
        val member = AgentTeamMember("cloud:researcher", AgentDeliveryMode.OBSERVE, instanceId = "node",
            context = mapOf("collaboration_group_id" to "group", CollaborationResearchWorkflow.PERSON to "person",
                CollaborationResearchWorkflow.STAGE to "VERIFY"))
        val coordinator = AgentTeamMember("desktop:coordinator", AgentDeliveryMode.RESPOND, dependsOnAgentIds = setOf("node"))
        store.create(AgentTeamDefinition(primaryAgentId = coordinator.agentId, members = listOf(member, coordinator)),
            AgentRunRequest("group", "turn", "task", runId = "run", goal = "Test", context = mapOf(CollaborationGoalLoop.ROUND to 1)))
        store.append(AgentSubagentEvent(1, "run", "node", AgentSubagentEventKinds.CHILD_RUNNING, childStatus = AgentSubagentStatus.RUNNING))
        store.markInterrupted("run")
        assertNull(store.resumeCheckpoint("run"))
        assertEquals(0, CollaborationPublicationRestart.recover(store, "run", workspace, { _, _ -> fail("Paused"); "" }, { false }))
        var archived = 0
        assertEquals(1, CollaborationPublicationRestart.recover(store, "run", workspace, { _, saved ->
            assertEquals(raw, saved); archived++; "a".repeat(64)
        }, { true }))
        assertEquals(AgentSubagentStatus.SUCCEEDED, store.snapshot("run")!!.members.first { it.memberId == "node" }.status)
        val recoveredResult = store.resumeCheckpoint("run")!!.completed.getValue("node")
        assertTrue(CollaborationTeamOrganizationProjection.hasHostProvenance(
            CollaborationTeamOrganizationProjection.Scope("run", store.snapshot("run")!!.teamId, "group", "group", "turn"),
            member, recoveredResult))
        assertNotNull(store.resumeCheckpoint("run"))
        assertEquals(0, CollaborationPublicationRestart.recover(store, "run", workspace, { _, _ -> fail("Duplicate"); "" }, { true }))
        assertEquals(1, archived)
    }

    @Test fun rejectedDraftRecoversInSameDispatchWithoutChangingSuccessfulPublication() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        enroll(workspace)
        val session = CollaborationPublicationRecovery(workspace, access)
        assertFalse(session.accept(raw(item().put("kind", "unknown"))))
        assertTrue(workspace.browse(access).revisions.isEmpty())
        assertTrue(session.feedback().contains("Unknown workspace object kind"))
        assertTrue(session.repairing)
        val restored = CollaborationPublicationRecovery(CollaborationResearchWorkspace(rows), access)
        assertEquals(session.latest.toString(), restored.latest.toString())
        val corrected = raw(item())
        assertTrue(restored.accept(" \n$corrected\n "))
        assertFalse(restored.repairing)
        assertEquals(2, restored.latest!!.getLong("sequence"))
        assertEquals(corrected, restored.latest!!.getString("raw"))
        assertEquals(2, rows.data.keys.count { ":attempt:" in it })
        val receipt = workspace.publish(access, corrected)
        assertEquals("recorded", receipt.getString("status"))
        val count = rows.data.size
        assertTrue(CollaborationPublicationRecovery(workspace, access).accept(corrected))
        assertEquals(count, rows.data.size)
        assertThrows(IllegalStateException::class.java) {
            CollaborationPublicationRecovery(workspace, access).accept(raw(item("second-result")))
        }
        assertEquals(1, workspace.browse(access).revisions.size)
    }

    @Test fun malformedJsonAndVerdictErrorsRemainExplicitAndCanBeCorrected() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        enroll(workspace)
        val session = CollaborationPublicationRecovery(workspace, access)
        assertFalse(session.accept("not JSON"))
        assertTrue(session.feedback().contains("valid ${CollaborationResearchArtifact.FORMAT}"))
        val review = JSONObject().put("criterion_id", "accuracy").put("requirement", "Exact preserved requirement")
            .put("rationale", "No observation has been obtained yet").put("global_verdict", "not_tested")
            .put("unresolved", JSONArray().put("Missing verification"))
            .put("target", JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64)))
        val proposal = item("review").put("kind", "acceptance_review").put("body", JSONObject().put("acceptance_review", review))
        assertFalse(session.accept(raw(proposal)))
        assertTrue(session.feedback().contains("Invalid review verdict"))
        review.remove("global_verdict")
        review.put("verdict", "not_tested")
        assertTrue(session.accept(raw(proposal)))
        assertEquals(3, session.latest!!.getLong("sequence"))
        assertEquals("member_reported_not_verified", workspace.browse(access).revisions.single().getString("evidence_state"))
    }

    @Test fun editingKindIsRejectedButASeparateReviewObjectCanBePublished() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        val author = access.copy(nodeId = "author", personId = "author")
        val original = workspace.publish(author, raw(item())).getJSONArray("revisions").getJSONObject(0)
        val reviewer = access.copy(dependencyNodes = setOf("author"))
        workspace.enrollPublication(reviewer, CollaborationResearchStage.VERIFY)
        val session = CollaborationPublicationRecovery(workspace, reviewer)
        val change = item("critique").put("kind", "counterexample")
            .put("object_id", original.getString("object_id")).put("base_revision", 1)
        assertFalse(session.accept(raw(change)))
        assertTrue(session.feedback().contains("An object's kind cannot be changed"))
        change.remove("object_id"); change.remove("base_revision")
        change.put("parents", JSONArray().put(original))
        assertTrue(session.accept(raw(change)))
        assertNull(workspace.read(reviewer, original.getString("object_id"), 2))
        assertEquals(2, workspace.browse(reviewer).revisions.size)
    }

    @Test fun rejectedBatchCommitsNoPartialObjectsAndStorageFailureIsAtomic() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        enroll(workspace)
        assertEquals("rejected", workspace.submitPublication(access, raw(item(), item("bad").put("title", ""))).getString("status"))
        assertTrue(workspace.browse(access).revisions.isEmpty())
        val before = rows.data.toMap()
        rows.failWrite = true
        assertThrows(IllegalStateException::class.java) { workspace.submitPublication(access, raw(item())) }
        assertEquals(before, rows.data)
        rows.failWrite = false
        assertEquals("recorded", workspace.submitPublication(access, raw(item())).getString("status"))
    }

    @Test fun corruptOriginalEvidenceIsNotReclassifiedAsARepairableModelMistake() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows, evidence = { _, _ ->
            throw IllegalStateException("Research evidence integrity check failed")
        })
        enroll(workspace)
        val before = rows.data.toMap()
        val draft = item().put("observations", JSONArray().put(JSONObject()
            .put("evidence_id", "a".repeat(64)).put("sha256", "b".repeat(64))))
        assertThrows(IllegalStateException::class.java) { workspace.submitPublication(access, raw(draft)) }
        assertEquals(before, rows.data)
        assertNull(workspace.publicationCheckpoint(access))
    }

    @Test fun contractIdentityRevocationAndJournalIntegrityCannotBeBypassed() {
        val rows = Rows()
        var authorized = true
        val workspace = CollaborationResearchWorkspace(rows, accessAuthorized = { authorized })
        assertThrows(IllegalArgumentException::class.java) { workspace.submitPublication(access, raw(item())) }
        enroll(workspace)
        assertThrows(IllegalArgumentException::class.java) {
            workspace.enrollPublication(access, CollaborationResearchStage.REVISE)
        }
        assertThrows(IllegalArgumentException::class.java) { workspace.publicationCheckpoint(access.copy(personId = "other")) }
        assertThrows(IllegalArgumentException::class.java) {
            workspace.publicationCheckpoint(access.copy(dependencyNodes = setOf("unassigned")))
        }
        workspace.submitPublication(access, "malformed")
        authorized = false
        assertThrows(IllegalArgumentException::class.java) { workspace.publicationCheckpoint(access) }
        assertThrows(IllegalArgumentException::class.java) { workspace.submitPublication(access, raw(item())) }
        authorized = true
        val key = rows.data.keys.single { it.endsWith(":latest") }
        rows.data[key] = rows.data.getValue(key).replace("malformed", "tampered!")
        assertThrows(IllegalStateException::class.java) { workspace.publicationCheckpoint(access) }
    }

    @Test fun repairsPreserveAllAttemptsAndOnlyAllowSavedEvidenceReads() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        enroll(workspace)
        val session = CollaborationPublicationRecovery(workspace, access)
        assertTrue(session.permitsTool("web_search"))
        repeat(10) { assertFalse(session.accept("invalid draft $it")) }
        assertEquals(60_000, session.backoffMillis())
        assertTrue(session.permitsTool(CollaborationCloudRecall.NAME))
        listOf("web_search", "web_fetch", CloudImageAnnotationPlan.TOOL, "exec_command").forEach {
            assertFalse(session.permitsTool(it))
        }
        assertTrue(session.accept(raw(item())))
        assertEquals(11, session.latest!!.getLong("sequence"))
    }

    @Test fun memberChoosesWhenToRequestAssistanceAndRetainsRecoverableDraft() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        enroll(workspace)
        val bad = raw(item().put("kind", "unknown"))
        repeat(12) {
            CollaborationPublicationRecovery(workspace, access).apply {
                assertFalse(accept(bad)); resumeAssistance()
            }
        }
        val session = CollaborationPublicationRecovery(workspace, access)
        val request = JSONObject().put("format", CollaborationPublicationAssistance.FORMAT)
            .put("diagnosis", "The host rejects the workspace kind, not JSON syntax")
            .put("attempted_corrections", "Changed prose did not change the constraint")
            .put("requested_help", "Ask the coordinator to inspect the supported kind contract")
        val error = assertThrows(CollaborationPublicationAssistanceException::class.java) { session.accept(request.toString()) }
        assertTrue(error.message!!.contains("goal is NOT complete"))
        assertEquals(bad, session.latest!!.getString("raw"))
        val before = rows.data.toMap()
        assertFalse(session.accept(bad, revalidate = true))
        assertEquals(before, rows.data)
        assertThrows(CollaborationPublicationAssistanceException::class.java) {
            CollaborationPublicationRecovery(workspace, access).resumeAssistance()
        }
        assertTrue(session.accept(raw(item())))
        session.resumeAssistance()
    }

    @Test fun assistanceCannotGrantNewAuthorityOrOverwriteTheDraft() {
        val workspace = CollaborationResearchWorkspace(Rows())
        enroll(workspace)
        val session = CollaborationPublicationRecovery(workspace, access)
        val draft = raw(item().put("kind", "unknown"))
        assertFalse(session.accept(draft))
        val request = JSONObject().put("format", CollaborationPublicationAssistance.FORMAT)
            .put("diagnosis", "Need assistance").put("attempted_corrections", "Inspected error")
            .put("requested_help", "Ask coordinator").put("permission", "all")
        assertThrows(IllegalArgumentException::class.java) { session.accept(request.toString()) }
        assertEquals(draft, session.latest!!.getString("raw"))
        assertNull(workspace.publicationAssistance(access))
    }

    @Test fun oldCountLimitRejectionCanBeRevalidatedWithoutRewritingTheDraft() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        enroll(workspace)
        val draft = JSONObject(raw(item())).put("findings", JSONArray((1..12).map {
            JSONObject().put("claim", "Recorded finding $it").put("outcome", "not_tested")
        })).toString()
        rows.commit(CollaborationPublicationJournal(rows, access).outcomeWrites(draft,
            JSONObject().put("status", "rejected").put("reason", "Return a valid structured artifact"), 1L))
        val session = CollaborationPublicationRecovery(workspace, access)
        assertTrue(session.accept(draft, revalidate = true))
        assertEquals(draft, session.latest!!.getString("raw"))
        assertEquals(1, workspace.browse(access).revisions.size)
        assertEquals(2, session.latest!!.getInt("sequence"))
    }

    @Test fun repairRequestsAdvertiseOnlyScopedRecallForAllCloudWireFormats() {
        ModelStreamProvider.entries.forEach { provider ->
            val body = JSONObject().put("tools", JSONArray().put(JSONObject().put("name", "unsafe_tool")))
                .put("tool_choice", "required").put("parallel_tool_calls", true).put("toolConfig", JSONObject())
            val request = PreparedCloudConversationStream("test", provider, "https://example.test", emptyMap(), body, JSONArray(), "messages")
            CloudConversationStreamEngine.restrictPublicationRepairTools(request)
            assertFalse(body.toString().contains("unsafe_tool"))
            assertFalse(body.has("tool_choice")); assertFalse(body.has("toolConfig"))
            val tool = body.getJSONArray("tools").getJSONObject(0)
            val name = when (provider) {
                ModelStreamProvider.OPENAI_COMPATIBLE -> tool.getJSONObject("function").getString("name")
                ModelStreamProvider.ANTHROPIC -> tool.getString("name")
                ModelStreamProvider.GEMINI -> tool.getJSONArray("functionDeclarations").getJSONObject(0).getString("name")
            }
            assertEquals(CollaborationCloudRecall.NAME, name)
            CloudConversationStreamEngine.restrictPublicationRepairTools(request, false)
            assertFalse(body.has("tools"))
        }
    }

    @Test fun assistanceReachesCoordinatorWhileIndependentWorkStillCompletes(): Unit = runBlocking {
        val runtime = AgentSubagentRuntime(limits = AgentSubagentLimits(maxChildren = 3, maxConcurrency = 3))
        try {
            val result = runtime.execute(AgentSubagentPlan("assistance-fixture", children = listOf(
                AgentSubagentChild("researcher"), AgentSubagentChild("independent"),
                AgentSubagentChild("coordinator", dependencies = setOf("researcher"),
                    dependencyPolicy = AgentSubagentDependencyPolicy.ALLOW_TERMINAL)
            ))) { execution ->
                if (execution.childId == "researcher") throw CollaborationPublicationAssistanceException("researcher", "Inspect validator contract")
                if (execution.childId == "coordinator") {
                    assertTrue(execution.handoff.dependencies.single().errorMessage.contains(CollaborationPublicationAssistanceException.CODE))
                }
                AgentSubagentOutput("Independent work or coordinator decision completed")
            }
            assertEquals(AgentSubagentStatus.SUCCEEDED, result["coordinator"]?.status)
            assertEquals(AgentSubagentStatus.SUCCEEDED, result["independent"]?.status)
            assertEquals(AgentSubagentStatus.FAILED, result["researcher"]?.status)
        } finally { runtime.shutdown() }
    }
}
