package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPublicationProblemTest {
    private fun raw() = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Preserved result")
        .put("candidates", JSONArray()).put("findings", JSONArray((1..12).map { JSONObject().put("outcome", "not_tested") })).toString()
    private fun rejected(reason: String) = JSONObject().put("status", "rejected").put("reason", reason)

    @Test fun factsDistinguishSyntaxSchemaAndWorkspaceWithoutSelectingARecovery() {
        val schema = CollaborationPublicationProblem.observe("{}", rejected("Missing format"), null)
        assertEquals("accepted", schema.getString("json_parse_status"))
        assertEquals("artifact_schema", schema.getString("failure_phase"))
        val syntax = CollaborationPublicationProblem.observe("invalid", rejected("Malformed JSON"), null)
        assertEquals("json_parsing", syntax.getString("failure_phase"))
        val workspace = CollaborationPublicationProblem.observe(raw(), rejected("Evidence digest mismatch"), null)
        assertEquals("workspace_contract", workspace.getString("failure_phase"))
        assertEquals(12, workspace.getJSONObject("observed_counts").getInt("findings"))
        assertFalse(workspace.has("retry_limit"))
        assertFalse(workspace.has("selected_strategy"))
    }

    @Test fun changedTextIsNotMisrepresentedAsProgressAgainstTheSameRejection() {
        val receipt = rejected("Version conflict")
        val previous = JSONObject().put("raw_sha256", AgentNativeJsonCodec.sha256(raw())).put("receipt", receipt)
        val unchanged = CollaborationPublicationProblem.observe(raw(), receipt, previous).getJSONObject("progress")
        assertFalse(unchanged.getBoolean("draft_changed"))
        assertFalse(unchanged.getBoolean("validator_feedback_changed"))
        val changed = CollaborationPublicationProblem.observe(raw().replace("Preserved", "Reworded"), receipt, previous).getJSONObject("progress")
        assertTrue(changed.getBoolean("draft_changed"))
        assertFalse(changed.getBoolean("validator_feedback_changed"))
        assertEquals("not_assessed_by_format_validator", changed.getString("scientific_progress"))
        val accepted = CollaborationPublicationProblem.observe(raw(), JSONObject().put("status", "recorded"), previous)
        assertTrue(accepted.getJSONObject("progress").getBoolean("validator_feedback_changed"))
    }
}
