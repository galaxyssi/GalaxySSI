package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPublicationEnvelopeTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) =
            data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { data.putAll(values) }
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "author")
    private fun item() = JSONObject().put("id", "data").put("kind", "artifact").put("title", "Measured observations")
        .put("body", JSONObject().put("content", "Synthetic observations, not independently verified"))
    private fun artifact(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Observations ready for review").put("workspace", JSONArray(items.toList()))
    private fun setup(rows: Rows) = CollaborationResearchWorkspace(rows).also {
        it.enrollPublication(access, CollaborationResearchStage.EXPLORE)
    }

    @Test fun minimalMilestoneCommitsPreservesRawAndReplaysExactlyAfterReopening() {
        val rows = Rows(); val workspace = setup(rows)
        val raw = artifact(item()).toString()
        val input = JSONObject().put("mode", "publish").put("milestone_id", "observations-v1").put("artifact", raw)
        val result = CollaborationMilestoneTool.execute(workspace, access, input) {}
        assertTrue(result.toString(), result.getBoolean("success"))
        assertFalse(result.getBoolean("assignment_completed"))
        val record = JSONObject(rows.data.filterKeys { ":milestone-attempt:" in it }.values.single())
        assertEquals(raw, record.getString("raw"))
        assertEquals(AgentNativeJsonCodec.sha256(raw), record.getString("raw_sha256"))
        assertEquals("member_reported_not_verified", workspace.browse(access).revisions.single().getString("evidence_state"))
        val before = rows.data.toMap()
        val reopened = CollaborationResearchWorkspace(rows)
        assertEquals(result.toString(), CollaborationMilestoneTool.execute(reopened, access, input) {}.toString())
        assertEquals(before, rows.data)
        val explicit = JSONObject(raw).put("candidates", JSONArray()).put("findings", JSONArray()).toString()
        assertEquals("rejected", reopened.publishMilestone(access, "observations-v1", explicit).getString("status"))
        assertEquals(before, rows.data)
        assertNull(reopened.publicationCheckpoint(access))
    }

    @Test fun minimalFinalCanIncludeAnExactMilestoneWithoutRecreatingIt() {
        val rows = Rows(); val workspace = setup(rows)
        val receipt = workspace.publishMilestone(access, "m1", artifact(item()).toString())
        val final = artifact().put("milestones", JSONArray().put("m1")).toString()
        val saved = workspace.submitPublication(access, final)
        assertEquals("recorded", saved.getString("status"))
        assertEquals(receipt.getJSONArray("revisions").toString(), saved.getJSONArray("revisions").toString())
        val reopened = CollaborationResearchWorkspace(rows)
        assertEquals(final, reopened.publicationCheckpoint(access)!!.getString("raw"))
        assertEquals(saved.toString(), reopened.submitPublication(access, final).toString())
        assertEquals(1, reopened.browse(access).revisions.size)
    }

    @Test fun malformedSuppliedNotesDoNotBecomeEmptySuccesses() {
        val rows = Rows(); val workspace = setup(rows)
        listOf("candidates", "findings").forEach { field ->
            val raw = artifact(item()).put(field, JSONObject.NULL).toString()
            val receipt = workspace.submitPublication(access, raw)
            assertEquals("rejected", receipt.getString("status"))
            assertTrue(receipt.getString("reason").contains("$field must be an array"))
            val checkpoint = workspace.publicationCheckpoint(access)!!
            assertEquals(raw, checkpoint.getString("raw"))
            assertEquals("artifact_schema", checkpoint.getJSONObject("problem_state").getString("failure_phase"))
            assertTrue(workspace.browse(access).revisions.isEmpty())
        }
    }

    @Test fun emptyWorkspaceAndInvalidBodiesStillFailAtTheWorkspaceContract() {
        val rows = Rows(); val workspace = setup(rows)
        val bad = listOf(
            artifact(),
            artifact(item().put("kind", "candidate")),
            artifact(item().put("kind", "acceptance_review")),
            artifact(item().put("observations", JSONArray().put(JSONObject()
                .put("evidence_id", "a".repeat(64)).put("sha256", "b".repeat(64)))))
        )
        bad.forEachIndexed { index, value ->
            val raw = value.toString()
            val receipt = workspace.publishMilestone(access, "bad$index", raw)
            assertEquals(receipt.toString(), "rejected", receipt.getString("status"))
            assertEquals("workspace_contract", CollaborationPublicationProblem.observe(raw, receipt, null).getString("failure_phase"))
            assertTrue(workspace.browse(access).revisions.isEmpty())
        }
        assertEquals(0, workspace.milestones(access).getJSONArray("milestones").length())
    }

    @Test fun aPreviouslyRejectedRawDraftCanBeRevalidatedWithoutModelRewrite() {
        val rows = Rows(); val workspace = setup(rows)
        val raw = artifact(item()).toString()
        rows.commit(CollaborationPublicationJournal(rows, access).outcomeWrites(raw,
            JSONObject().put("status", "rejected").put("reason", "Missing candidates"), 1))
        val originals = rows.data.filterKeys { ":attempt:" in it }.toMap()
        val session = CollaborationPublicationRecovery(CollaborationResearchWorkspace(rows), access)
        assertTrue(session.accept(raw, revalidate = true))
        assertEquals(raw, session.latest!!.getString("raw"))
        assertEquals(2, session.latest!!.getInt("sequence"))
        originals.forEach { (key, value) -> assertEquals(value, rows.data[key]) }
        assertEquals(1, workspace.browse(access).revisions.size)
    }
}
