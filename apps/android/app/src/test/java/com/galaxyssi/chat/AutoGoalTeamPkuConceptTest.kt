package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AutoGoalTeamPkuConceptTest {
    @Test fun aSingleReferencePointCannotValidateTheCandidateResponse() = runBlocking {
        // Dimensionless illustrative response functions, not fitted biological parameters or patient data.
        fun linear(x: Double) = x / (1 + x)
        fun steeper(x: Double) = x * x / (1 + x * x)
        val inputs = listOf(0.25, 1.0, 4.0)
        val observations = inputs.associateWith { linear(it) to steeper(it) }
        assertEquals(linear(1.0), steeper(1.0), 0.0)
        assertTrue(steeper(0.25) < 0.10 && steeper(4.0) > 0.85)
        assertFalse(linear(0.25) < 0.10 || linear(4.0) > 0.85)
        val objection = "Matching the middle point does not identify a response curve or validate a protein."
        val result = runAutoGoalTeam("Assess the fictional Phe-Buffer concept using toy responses $observations.", { _, payload ->
            val p = JSONObject(payload)
            when (p.getString("stage")) {
                "plan" -> "ROLE|math|worker|-|Compare the two toy curves.\n" +
                    "ROLE|audit|reviewer|math|Check what this calculation cannot establish.\nSYNTHESIS|Separate math from evidence."
                "role" -> if (p.getString("id") == "math") {
                    assertEquals(0, p.getJSONArray("reports").length())
                    "FINDING|Only the steeper toy response meets both illustrative criteria.\nDISSENT|-\nEND"
                } else {
                    assertEquals("math", p.getJSONArray("reports").getJSONObject(0).getString("id"))
                    "FINDING|No candidate was measured.\nDISSENT|$objection\nEND"
                }
                else -> "Mathematical illustration only.\nEND"
            }
        })
        assertTrue(result.contains(objection))
    }
}
