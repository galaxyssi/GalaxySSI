package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationAssessmentValidationTest {
    private fun criterion() = JSONObject().put("id", "measurement").put("requirement", "Measure and compare actual outcomes")
        .put("status", "open").put("verification", "computational").put("evidence_kind", "proposal").put("evidence", JSONArray())
    private fun report(item: JSONObject = criterion()) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("summary", "Plan a discriminating measurement").put("decision", "continue").put("criteria", JSONArray().put(item))
        .put("work", JSONArray()).put("blockers", JSONArray())

    @Test fun unknownOriginReportsExactPathReceivedAndRegistryWithoutRelabeling() {
        val item = criterion().put("required_observations", JSONArray().put(JSONObject().put("origin", "desktop").put("tool", "exec_command")))
        val raw = report(item).toString()
        val result = CollaborationAssessmentValidation.inspect(raw)
        assertNull(result.assessment)
        assertTrue(result.syntaxValid)
        val failure = requireNotNull(result.failure)
        assertEquals("$.criteria[0].required_observations[0].origin", failure.path)
        assertEquals("unknown_origin", failure.code)
        assertEquals("desktop", failure.actual)
        assertTrue(failure.expected.contains("desktop_codex_tool"))
        assertTrue(raw.contains("exec_command"))
        assertNull(CollaborationGoalLoop.decode(raw))
    }

    @Test fun initialCriteriaAreNotDescribedAsCorrupt() {
        val failed = CollaborationAssessmentValidation.inspect(report().put("criteria", JSONArray()).toString())
        val feedback = JSONObject(failed.feedback(JSONArray()))
        assertEquals("valid", feedback.getString("json_syntax"))
        assertEquals("initial_criteria_pending", feedback.getString("contract_state"))
        assertEquals("$.criteria", feedback.getJSONObject("failure").getString("path"))
        assertTrue(feedback.getString("next_action").contains("not corruption"))
        assertTrue(feedback.getString("next_action").contains("Define complete criteria"))
    }

    @Test fun establishedCriteriaCannotBeReplacedByRepairGuidance() {
        val failed = CollaborationAssessmentValidation.inspect(report().put("criteria", JSONArray()).toString())
        val feedback = JSONObject(failed.feedback(JSONArray().put(criterion())))
        assertEquals("established", feedback.getString("contract_state"))
        assertEquals(1, feedback.getInt("established_criteria_count"))
        assertTrue(feedback.getString("next_action").contains("preserving every established"))
        assertFalse(feedback.getString("next_action").contains("Define complete criteria"))
    }

    @Test fun malformedSyntaxAndValidNonObjectAreDifferentFailures() {
        assertFalse(CollaborationAssessmentValidation.inspect("{").syntaxValid)
        val array = CollaborationAssessmentValidation.inspect("[]")
        assertTrue(array.syntaxValid)
        assertEquals("invalid_type", array.failure?.code)
        assertFalse(CollaborationAssessmentValidation.inspect(report().toString() + " trailing").syntaxValid)
        for (raw in listOf("{unquoted:1}", "{\"a\":1,}", "{\"a\":1,\"a\":2}", "[1,]"))
            assertFalse(raw, CollaborationAssessmentValidation.inspect(raw).syntaxValid)
    }

    @Test fun missingFieldReportsItsPathInsteadOfCallingJsonInvalid() {
        val raw = report(criterion().apply { remove("requirement") }).toString()
        val failed = CollaborationAssessmentValidation.inspect(raw)
        assertTrue(failed.syntaxValid)
        assertEquals("$.criteria[0].requirement", failed.failure?.path)
        assertEquals("missing", failed.failure?.actual)
    }

    @Test fun unknownValidatorHasComponentSpecificFeedback() {
        val result = CollaborationAssessmentValidation.inspect(report(criterion().put("validator", JSONObject().put("id", "invented"))).toString())
        assertTrue(result.syntaxValid)
        assertEquals("$.criteria[0].validator", result.failure?.path)
        assertTrue(requireNotNull(result.failure).detail.contains("exact_integer_sum.v1"))
        assertNull(result.assessment)
    }

    @Test fun allMalformedEvidenceRequirementShapesAreDiagnosable() {
        val shapes = listOf(JSONObject.NULL, "none", JSONArray().put(7),
            JSONArray().put(JSONObject().put("origin", "desktop_codex_tool")),
            JSONArray().put(JSONObject().put("origin", "desktop_codex_tool").put("tool", "")))
        shapes.forEach { shape ->
            val result = CollaborationAssessmentValidation.inspect(report(criterion().put("required_observations", shape)).toString())
            assertTrue(result.syntaxValid)
            assertNull(result.assessment)
            assertTrue(requireNotNull(result.failure).path.startsWith("$.criteria[0].required_observations"))
        }
    }

    @Test fun validUnknownDomainStaysOpenWithoutInventingAValidator() {
        val result = CollaborationAssessmentValidation.inspect(report().toString())
        assertNotNull(result.assessment)
        assertNull(result.failure)
        assertFalse(requireNotNull(result.assessment).getJSONArray("criteria").getJSONObject(0).has("validator"))
    }

    @Test fun fencedAssessmentStillWorksAndDiagnosticsDoNotEchoLargeDrafts() {
        assertNotNull(CollaborationGoalLoop.decode("```json\n${report()}\n```"))
        val draft = report().put("summary", "PRIVATE".repeat(2000)).put("decision", "SECRET".repeat(1000))
        val feedback = CollaborationAssessmentValidation.inspect(draft.toString()).feedback(JSONArray())
        assertFalse(feedback.contains("PRIVATE"))
        assertFalse(feedback.contains("SECRET"))
        assertTrue(feedback.contains("6000 characters"))
    }
}
