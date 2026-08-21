package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPlannerObservationTest {
    @Test
    fun `long result cannot hide distinct evidence`() {
        val observation = AgentPlannerObservation.from(
            action(result = "result ".repeat(100), evidence = "LATEST_VERIFIED_EVIDENCE"),
            maximumCharacters = 120
        ).orEmpty()

        assertTrue(observation.length <= 120)
        assertTrue(observation.contains("result"))
        assertTrue(observation.contains("LATEST_VERIFIED_EVIDENCE"))
    }

    @Test
    fun `duplicate result and evidence are emitted once`() {
        val observation = AgentPlannerObservation.from(
            action(result = "same verified receipt", evidence = "same verified receipt"),
            maximumCharacters = 120
        ).orEmpty()

        assertEquals("same verified receipt", observation)
    }

    private fun action(result: String, evidence: String): AgentAction = AgentAction(
        id = "observation-test",
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = "signalasi.test.tool",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Test observation compilation",
        result = result,
        evidence = evidence,
        requiresConfirmation = false
    )
}
