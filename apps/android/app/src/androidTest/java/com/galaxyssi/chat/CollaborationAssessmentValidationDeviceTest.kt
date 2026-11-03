package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Android's JSON implementation must give the same repair diagnosis without invoking a model. */
@RunWith(AndroidJUnit4::class)
class CollaborationAssessmentValidationDeviceTest {
    private fun report(origin: String) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("summary", "A test draft").put("decision", "continue").put("work", JSONArray()).put("blockers", JSONArray())
        .put("criteria", JSONArray().put(JSONObject().put("id", "evidence").put("requirement", "Execute a measurement")
            .put("status", "open").put("verification", "computational").put("evidence", JSONArray())
            .put("required_observations", JSONArray().put(JSONObject().put("origin", origin).put("tool", "codex.commandExecution")))))

    @Test fun androidReportsTheActualFieldAndAllowsTargetedCorrection() {
        val raw = report("desktop").toString()
        val rejected = CollaborationAssessmentValidation.inspect(raw)
        assertTrue(rejected.syntaxValid)
        assertEquals("$.criteria[0].required_observations[0].origin", rejected.failure?.path)
        val feedback = JSONObject(rejected.feedback(JSONArray()))
        assertEquals("initial_criteria_pending", feedback.getString("contract_state"))
        assertEquals("desktop", feedback.getJSONObject("failure").getString("actual"))
        assertTrue(feedback.getJSONObject("failure").getString("expected").contains("desktop_codex_tool"))
        val accepted = CollaborationAssessmentValidation.inspect(report("desktop_codex_tool").toString())
        assertNotNull(accepted.assessment)
        assertNull(accepted.failure)
        assertEquals("open", requireNotNull(accepted.assessment).getJSONArray("criteria").getJSONObject(0).getString("status"))
    }

    @Test fun androidDistinguishesSyntaxFromSchemaAndPreservesEstablishedCriteria() {
        assertFalse(CollaborationAssessmentValidation.inspect("{").syntaxValid)
        assertFalse(CollaborationAssessmentValidation.inspect("{unquoted:1}").syntaxValid)
        assertFalse(CollaborationAssessmentValidation.inspect(report("desktop").toString() + " trailing").syntaxValid)
        val rejected = CollaborationAssessmentValidation.inspect(report("desktop").toString())
        val prior = report("desktop_codex_tool").getJSONArray("criteria")
        val feedback = JSONObject(rejected.feedback(prior))
        assertEquals("established", feedback.getString("contract_state"))
        assertEquals("valid", feedback.getString("json_syntax"))
        assertTrue(feedback.getString("next_action").contains("preserving every established"))
    }
}
