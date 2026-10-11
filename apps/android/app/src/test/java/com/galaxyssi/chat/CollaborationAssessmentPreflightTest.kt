package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationAssessmentPreflightTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { data.putAll(values) }
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "planner", "coordinator")
    private fun draft() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Draft only")
        .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "source")
            .put("requirement", "Preserve a runnable method").put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray()).put("blockers", JSONArray())
    private fun input(raw: String) = JSONObject().put("mode", CollaborationAssessmentPreflight.MODE).put("artifact", raw)

    @Test fun plannerCanRepairDraftInSameAssignmentWithoutPublishingOrGrantingAuthority() {
        val rows = Rows(); val workspace = CollaborationResearchWorkspace(rows)
        assertFalse(workspace.publicationCapability(access).getBoolean("publish_allowed"))
        val original = draft().apply { remove("criteria") }.toString()
        val failed = CollaborationMilestoneTool.execute(workspace, access, input(original)) {}
        assertTrue(failed.getBoolean("success"))
        assertFalse(failed.getBoolean("schema_valid"))
        assertEquals("$.criteria", failed.getJSONObject("failure").getString("path"))
        val repaired = draft().toString()
        val checked = CollaborationMilestoneTool.execute(workspace, access, input(repaired)) {}
        assertTrue(checked.getBoolean("schema_valid"))
        assertEquals(MqttImmutableContent.sha256(repaired), checked.getString("draft_sha256"))
        assertFalse(checked.getBoolean("committed")); assertFalse(checked.getBoolean("goal_accepted"))
        assertFalse(checked.getBoolean("assignment_completed"))
        assertTrue(checked.getJSONArray("not_checked").toString().contains("work_graph"))
        assertTrue(checked.getJSONArray("not_checked").toString().contains("preserved_contract"))
        assertNull(workspace.publicationCheckpoint(access))
        assertTrue(rows.data.isEmpty())
        assertFalse(workspace.publicationCapability(access).getBoolean("publish_allowed"))
    }

    @Test fun executableCaseConstraintUsesFinalValidatorAndPreservesDraft() {
        val raw = draft()
        fun case(id: String, purpose: String) = JSONObject().put("id", id).put("purpose", purpose)
            .put("reason", "Synthetic diagnostic").put("input", JSONObject()).put("expected", 1)
        val spec = JSONObject().put("id", CollaborationExecutableAcceptance.id).put("environment", "fixture")
            .put("purpose", "fixture").put("oracle_basis", "fixture").put("coverage_gaps", "synthetic only")
            .put("cases", JSONArray().put(case("target", "target")).put(case("edge", "edge")))
        raw.getJSONArray("criteria").getJSONObject(0).put("requirement", CollaborationExecutableAcceptance.REQUIREMENT)
            .put("verification", "computational").put("evidence_kind", "observed").put("validator", spec)
        val before = raw.toString()
        val failed = CollaborationAssessmentPreflight.inspect(before)
        assertEquals("valid", failed.getString("json_syntax"))
        assertFalse(failed.getBoolean("schema_valid"))
        assertEquals("$.criteria[0].validator", failed.getJSONObject("failure").getString("path"))
        assertEquals("Preserve target and regression cases", failed.getJSONObject("failure").getString("detail"))
        assertEquals(before, raw.toString())
        spec.getJSONArray("cases").put(case("regression", "regression"))
        assertTrue(CollaborationAssessmentPreflight.inspect(raw.toString()).getBoolean("schema_valid"))
        assertNotNull(CollaborationAssessmentValidation.inspect(raw.toString()).assessment)
        assertTrue(CollaborationExecutableAcceptance.rules().contains("target case AND at least one regression case"))
    }

    @Test fun invalidSyntaxIsNotConfusedWithValidRejectedFields() {
        val syntax = CollaborationAssessmentPreflight.inspect("{bad")
        assertEquals("invalid", syntax.getString("json_syntax"))
        assertEquals("invalid_json", syntax.getJSONObject("failure").getString("code"))
        assertEquals("valid", CollaborationAssessmentPreflight.inspect("[]").getString("json_syntax"))
        assertEquals("invalid_type", CollaborationAssessmentPreflight.inspect("[]").getJSONObject("failure").getString("code"))
    }

    @Test fun pausedOrRevokedAssignmentsCannotUsePreflight() {
        val rows = Rows(); val workspace = CollaborationResearchWorkspace(rows)
        val paused = CollaborationMilestoneTool.execute(workspace, access, input(draft().toString())) {
            throw IllegalArgumentException("paused")
        }
        val revoked = CollaborationMilestoneTool.execute(CollaborationResearchWorkspace(rows, authorized = { false }),
            access, input(draft().toString())) {}
        for (result in listOf(paused, revoked)) {
            assertFalse(result.getBoolean("success"))
            assertEquals("rejected", result.getString("status"))
            assertFalse(result.getBoolean("assignment_completed"))
            assertFalse(result.has("schema_valid"))
        }
        assertTrue(rows.data.isEmpty())
    }

    @Test fun authoritySelectorsAndOversizedDraftsAreRejectedBeforeInspection() {
        val original = input(draft().toString())
        for ((key, value) in listOf("member_id" to "other", "milestone_id" to "new", "cursor" to "", "execute" to true)) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationMilestoneTool.validate(JSONObject(original.toString()).put(key, value)) }
        }
        for (raw in listOf<Any>(JSONObject(), "", " ", "x".repeat(CollaborationMilestoneTool.MAX_BYTES))) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationMilestoneTool.validate(JSONObject(original.toString()).put("artifact", raw)) }
        }
        assertTrue(CollaborationMilestoneTool.unavailable(CollaborationAssessmentPreflight.MODE).getString("error")
            .contains("no plan or artifact was submitted"))
    }
}
