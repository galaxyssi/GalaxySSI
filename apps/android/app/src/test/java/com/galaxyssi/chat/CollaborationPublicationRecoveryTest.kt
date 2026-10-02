package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
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

    @Test fun repairsHaveBackoffNotAnAttemptCountCutoffAndOnlyAllowSavedEvidenceReads() {
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
}
