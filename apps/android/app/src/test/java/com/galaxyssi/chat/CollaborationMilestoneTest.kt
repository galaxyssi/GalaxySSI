package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMilestoneTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
        override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) { removeKeys.forEach(data::remove); commit(values) }
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "worker", "author")
    private fun item(id: String = "candidate") = JSONObject().put("id", id).put("kind", "proposal")
        .put("title", "Testable candidate").put("body", JSONObject().put("content", "Actual candidate with constraints"))
    private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Candidate for independent review").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray(items.toList())).toString()
    private fun setup(rows: Rows = Rows()) = CollaborationResearchWorkspace(rows).also {
        it.enrollPublication(access, CollaborationResearchStage.EXPLORE)
    }

    @Test fun unEnrolledDispatchReportsCapabilityNotBrokenArtifactWithoutMutation() {
        val rows = Rows(); val workspace = CollaborationResearchWorkspace(rows)
        val status = CollaborationMilestoneTool.execute(workspace, access, JSONObject().put("mode", "status")) {}
        assertTrue(status.getBoolean("success"))
        assertFalse(status.getJSONObject("capability").getBoolean("publish_allowed"))
        assertEquals("assignment_not_enrolled", status.getJSONObject("capability").getString("reason_code"))
        val input = JSONObject().put("mode", "publish").put("milestone_id", "m1").put("artifact", raw(item()))
        repeat(2) {
            val result = CollaborationMilestoneTool.execute(workspace, access, input) {}
            assertEquals("unavailable", result.getString("status"))
            assertEquals("assignment_not_enrolled", result.getString("error_code"))
            assertFalse(result.getBoolean("artifact_validated"))
            assertFalse(result.getBoolean("retryable"))
            assertTrue(result.getString("error").contains("required planning or final-response format"))
        }
        assertTrue(rows.data.isEmpty())
        workspace.enrollPublication(access, CollaborationResearchStage.EXPLORE)
        assertTrue(workspace.publicationCapability(access).getBoolean("publish_allowed"))
        assertTrue(CollaborationMilestoneTool.execute(workspace, access, input) {}.getBoolean("success"))
    }

    @Test fun capabilityIsReadOnlyBoundToAssignmentAndReflectsFinalCommit() {
        val rows = Rows(); val workspace = setup(rows); val before = rows.data.toMap()
        val statusInput = JSONObject().put("mode", "status")
        assertTrue(CollaborationMilestoneTool.execute(workspace, access, statusInput) {}
            .getJSONObject("capability").getBoolean("publish_allowed"))
        assertFalse(CollaborationMilestoneTool.execute(workspace, access.copy(nodeId = "planner"), statusInput) {}
            .getJSONObject("capability").getBoolean("publish_allowed"))
        assertEquals(before, rows.data)
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationMilestoneTool.validate(JSONObject().put("mode", "status").put("member_id", "author"))
        }
        assertEquals("recorded", workspace.submitPublication(access, raw(item())).getString("status"))
        val final = rows.data.toMap()
        assertEquals("assignment_finalized", CollaborationResearchWorkspace(rows).publicationCapability(access).getString("reason_code"))
        assertEquals(final, rows.data)
        assertTrue(CollaborationMilestoneTool.execute(workspace, access, JSONObject().put("mode", "list")) {}.getBoolean("success"))
    }

    @Test fun candidateTransitionsRemainFinalOnlyAndRevokedAccessCannotReadCapability() {
        val capability = CollaborationPublicationCapability.describe(JSONObject().put("candidate_task", JSONObject()), false)
        assertFalse(capability.getBoolean("publish_allowed"))
        assertEquals("candidate_transition_final_only", capability.getString("reason_code"))
        val workspace = CollaborationResearchWorkspace(Rows(), authorized = { false })
        assertThrows(IllegalArgumentException::class.java) { workspace.publicationCapability(access) }
    }

    @Test fun interimAndFinalAreSeparateDurablePublications() {
        val rows = Rows(); val workspace = setup(rows)
        val first = workspace.publishMilestone(access, "candidate-v1", raw(item()), 100)
        assertEquals("recorded", first.getString("status"))
        assertNull(workspace.publicationCheckpoint(access))
        assertTrue(workspace.publicationRevisions(access, access.nodeId).isEmpty())
        val final = JSONObject(raw()).put("milestones", JSONArray(listOf("candidate-v1"))).toString()
        val receipt = CollaborationResearchWorkspace(rows).submitPublication(access, final)
        assertEquals(first.getJSONArray("revisions").toString(), receipt.getJSONArray("revisions").toString())
        assertEquals(1, workspace.publicationRevisions(access, access.nodeId).size)
        assertEquals("member_reported_not_verified", workspace.publicationRevisions(access, access.nodeId).single().getString("evidence_state"))
        assertEquals(receipt.toString(), workspace.submitPublication(access, final).toString())
        assertThrows(IllegalArgumentException::class.java) { workspace.publishMilestone(access, "late", raw(item("late"))) }
    }

    @Test fun duplicateAfterLostReceiptDoesNotCreateObjectsOrRewriteVersions() {
        val rows = Rows(); val workspace = setup(rows); val body = raw(item())
        val receipt = workspace.publishMilestone(access, "m1", body, 10)
        val original = rows.data.toMap()
        assertEquals(receipt.toString(), CollaborationResearchWorkspace(rows).publishMilestone(access, "m1", body, 20).toString())
        assertEquals(original, rows.data)
        assertEquals("rejected", workspace.publishMilestone(access, "m1", raw(item("replacement"))).getString("status"))
        assertEquals(original, rows.data)
    }

    @Test fun invalidDraftRetainedAndCorrectableWithoutFalsePublication() {
        val rows = Rows(); val workspace = setup(rows)
        val failed = workspace.publishMilestone(access, "m1", "not json")
        assertEquals("rejected", failed.getString("status"))
        assertTrue(failed.getString("reason").contains("valid"))
        assertEquals(0, workspace.milestones(access).getJSONArray("milestones").length())
        val attempts = rows.data.filterKeys { ":milestone-attempt:" in it }.toMap()
        assertEquals(1, attempts.size)
        assertEquals("recorded", workspace.publishMilestone(access, "m1", raw(item())).getString("status"))
        attempts.forEach { (key, value) -> assertEquals(value, rows.data[key]) }
        assertEquals(2, rows.data.keys.count { ":milestone-attempt:" in it })
    }

    @Test fun atomicFailureLeavesNeitherObjectNorMilestoneAndRetryRecovers() {
        val rows = Rows(); val workspace = setup(rows); val before = rows.data.toMap()
        rows.fail = true
        assertThrows(IllegalStateException::class.java) { workspace.publishMilestone(access, "m1", raw(item())) }
        assertEquals(before, rows.data)
        rows.fail = false
        assertEquals("recorded", workspace.publishMilestone(access, "m1", raw(item())).getString("status"))
    }

    @Test fun versionedCorrectionsPreserveOriginalAndFinalChoosesExactMilestones() {
        val workspace = setup()
        val ref = workspace.publishMilestone(access, "original", raw(item())).getJSONArray("revisions").getJSONObject(0)
        val changed = item().put("object_id", ref.getString("object_id")).put("base_revision", 1)
            .put("body", JSONObject().put("content", "Improved after counterexample"))
        assertEquals("recorded", workspace.publishMilestone(access, "revised", raw(changed)).getString("status"))
        val final = JSONObject(raw(item("new-evidence"))).put("milestones", JSONArray(listOf("revised"))).toString()
        val result = workspace.submitPublication(access, final)
        assertEquals("recorded", result.getString("status"))
        assertEquals(2, result.getJSONArray("revisions").length())
        assertEquals(2, result.getJSONArray("revisions").getJSONObject(0).getInt("revision"))
        assertEquals("Actual candidate with constraints", workspace.read(access, ref.getString("object_id"), 1)!!.getJSONObject("body").getString("content"))
    }

    @Test fun noEmptyRecursiveUnknownOrCrossAssignmentMilestones() {
        val workspace = setup()
        assertEquals("rejected", workspace.publishMilestone(access, "empty", raw()).getString("status"))
        assertEquals("rejected", workspace.publishMilestone(access, "recursive", JSONObject(raw(item())).put("milestones", JSONArray()).toString()).getString("status"))
        workspace.publishMilestone(access, "private", raw(item()))
        val reader = access.copy(nodeId = "reviewer", personId = "peer", dependencyNodes = setOf(access.nodeId))
        workspace.enrollPublication(reader, CollaborationResearchStage.VERIFY)
        assertEquals(0, workspace.milestones(reader).getJSONArray("milestones").length())
        val stolen = JSONObject(raw()).put("milestones", JSONArray(listOf("private"))).toString()
        assertEquals("rejected", workspace.submitPublication(reader, stolen).getString("status"))
        val ref = workspace.browse(reader).revisions.single()
        assertEquals("author", ref.getString("person_id"))
        assertTrue(workspace.browse(reader.copy(dependencyNodes = emptySet())).revisions.isEmpty())
    }

    @Test fun pagingDoesNotTruncateAndCursorCannotCrossAssignments() {
        val workspace = setup()
        repeat(35) { assertEquals("recorded", workspace.publishMilestone(access, "m$it", raw(item("item$it"))).getString("status")) }
        val first = workspace.milestones(access)
        assertEquals(32, first.getJSONArray("milestones").length())
        val cursor = first.getString("next_cursor")
        assertEquals(3, workspace.milestones(access, cursor).getJSONArray("milestones").length())
        assertThrows(IllegalArgumentException::class.java) { workspace.milestones(access.copy(nodeId = "other"), cursor) }
    }

    @Test fun tamperedReceiptCannotBeImportedByFinalAndGroupRemovalCleansAllRows() {
        val rows = Rows(); val workspace = setup(rows)
        workspace.publishMilestone(access, "m1", raw(item()))
        val key = rows.data.keys.single { ":milestone:" in it }
        val modified = JSONObject(rows.data.getValue(key))
        modified.getJSONObject("receipt").put("trust", "verified")
        rows.data[key] = modified.toString()
        assertThrows(IllegalArgumentException::class.java) { workspace.milestones(access) }
        assertEquals("rejected", workspace.submitPublication(access, JSONObject(raw()).put("milestones", JSONArray(listOf("m1"))).toString()).getString("status"))
        assertTrue(rows.data.keys.filter { "milestone" in it }.all { it.startsWith("group:") })
        workspace.removeGroup(access.groupId)
        assertTrue(rows.data.keys.none { it.startsWith("group:") })
    }

    @Test fun toolCannotSelectAuthorityAndReportsPauseWithoutMutation() {
        val rows = Rows(); val workspace = setup(rows); val before = rows.data.toMap()
        val input = JSONObject().put("mode", "publish").put("milestone_id", "m1").put("artifact", raw(item()))
        val paused = CollaborationMilestoneTool.execute(workspace, access, input) { throw IllegalArgumentException("paused") }
        assertFalse(paused.getBoolean("success")); assertEquals(before, rows.data)
        assertThrows(IllegalArgumentException::class.java) { CollaborationMilestoneTool.validate(JSONObject(input.toString()).put("member_id", "other")) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationMilestoneTool.validate(JSONObject(input.toString()).put("artifact", "x".repeat(131072))) }
        val result = CollaborationMilestoneTool.execute(workspace, access, input) {}
        assertTrue(result.getBoolean("success")); assertFalse(result.getBoolean("assignment_completed"))
    }
}
