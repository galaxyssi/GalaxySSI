package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReviewedPredictionTest {
    private val task = "Compare two sensor readings. What observation would contradict this prediction? Independently audit the final answer."
    private val plan = """{"roles":["Assess the gauge"],"synthesis":"Propose a testable response","final_review":"Check the published contrast"}"""
    private fun claim(input: String = "load") = JSONObject().put("purpose", "A hypothetical strain gauge")
        .put("input", input).put("input_direction", "higher").put("readout", "voltage")
        .put("expected_direction", "lower").put("alternative", "Temperature can change voltage independently")
        .put("gap", "No calibration evidence").toString()

    @Test fun onlyTheApprovedRenderedClaimCanBePublished() = runBlocking {
        for (mode in listOf("approve", "return", "replace", "bypass", "reject", "qualitative")) {
            val calls = mutableListOf<String>()
            var firstDraft = ""
            var lastDraft = ""
            val run = runCatching { runAutoGoalTeam(task, { _, raw ->
                val p = JSONObject(raw)
                val stage = p.getString("stage")
                calls += stage
                when (stage) {
                    "plan" -> plan
                    "role" -> """{"finding":"No observations were provided."}"""
                    "synthesis" -> if (mode == "qualitative") """{"answer":"A qualitative explanation."}""" else claim()
                    "audit" -> {
                        firstDraft = p.getString("draft")
                        when (mode) {
                            "approve", "qualitative" -> """{"verdict":"accept"}"""
                            "replace" -> """{"verdict":"revise","objection":"Which load?","answer":"Never checked."}"""
                            else -> """{"verdict":"request_changes","objection":"Which load?"}"""
                        }
                    }
                    "rewrite" -> {
                        assertEquals(firstDraft, p.getString("draft"))
                        assertEquals("load", p.getJSONObject("original_claim").getString("input"))
                        assertEquals("Which load?", p.getString("objection"))
                        if (mode == "bypass") """{"answer":"Never checked."}""" else claim("axial load")
                    }
                    "recheck" -> {
                        lastDraft = p.getString("draft")
                        assertEquals(firstDraft, p.getString("rejected_draft"))
                        assertEquals("role2", p.getString("id"))
                        if (mode == "reject") """{"verdict":"withhold","objection":"Not supported."}""" else """{"verdict":"accept"}"""
                    }
                    else -> error("Unexpected stage")
                }
            }) }
            when (mode) {
                "approve" -> { assertTrue(firstDraft.contains("voltage")); assertEquals(firstDraft, run.getOrThrow()); assertEquals(4, calls.size) }
                "qualitative" -> assertEquals("A qualitative explanation.", run.getOrThrow())
                "bypass", "reject" -> {
                    assertTrue(run.exceptionOrNull() is TeamAnswerWithheld)
                    assertEquals(if (mode == "bypass") 5 else 6, calls.size)
                }
                else -> {
                    assertNotEquals(firstDraft, lastDraft)
                    assertTrue(run.getOrThrow().startsWith(lastDraft) && lastDraft.contains("axial load"))
                    assertFalse("Never checked." in run.getOrThrow())
                    assertEquals(listOf("plan", "role", "synthesis", "audit", "rewrite", "recheck"), calls)
                }
            }
        }
    }
}
