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

    @Test
    fun `evidence already preserved in result is not emitted twice`() {
        val observation = AgentPlannerObservation.from(
            action(
                result = "command failed with stderr=permission denied",
                evidence = "stderr=permission denied"
            ),
            maximumCharacters = 120
        ).orEmpty()

        assertEquals("command failed with stderr=permission denied", observation)
    }

    @Test
    fun `contained evidence remains separate when result compaction would hide it`() {
        val evidence = "failure_kind=missing_executable"
        val observation = AgentPlannerObservation.from(
            action(
                result = "command started " + "progress ".repeat(40) + evidence + " output ".repeat(40) + "stopped",
                evidence = evidence
            ),
            maximumCharacters = 160
        ).orEmpty()

        assertTrue(observation.contains(evidence))
        assertTrue(observation.contains("middle omitted"))
    }

    @Test
    fun `long tool output preserves command context and terminal failure`() {
        val observation = AgentPlannerObservation.sanitize(
            value = "Running ./gradlew assembleDebug " +
                "dependency progress ".repeat(80) +
                "FAILURE: Build failed because Android SDK platform 35 is missing",
            maximumCharacters = 180
        ).orEmpty()

        assertTrue(observation.length <= 180)
        assertTrue(observation.startsWith("Running ./gradlew"))
        assertTrue(observation.contains("middle omitted"))
        assertTrue(observation.endsWith("Android SDK platform 35 is missing"))
    }

    @Test
    fun `result and evidence each retain their newest tail`() {
        val observation = AgentPlannerObservation.from(
            action(
                result = "command started " + "output ".repeat(50) + "exit_code=1",
                evidence = "receipt created " + "detail ".repeat(50) + "stderr=permission denied"
            ),
            maximumCharacters = 220
        ).orEmpty()

        assertTrue(observation.length <= 220)
        assertTrue(observation.contains("exit_code=1"))
        assertTrue(observation.contains("stderr=permission denied"))
    }

    @Test
    fun `tail evidence is redacted before compaction`() {
        val observation = AgentPlannerObservation.sanitize(
            value = "tool output " + "progress ".repeat(50) + "access_token=top-secret failure",
            maximumCharacters = 120
        ).orEmpty()

        assertTrue(observation.contains("access_token=[redacted]"))
        assertTrue(!observation.contains("top-secret"))
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
