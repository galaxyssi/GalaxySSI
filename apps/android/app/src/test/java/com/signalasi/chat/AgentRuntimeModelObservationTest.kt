package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeModelObservationTest {
    @Test
    fun shortOutputRemainsUnchanged() {
        val excerpt = AgentRuntimeModelObservation.compact("short output")

        assertEquals("short output", excerpt.text)
        assertEquals(12, excerpt.totalChars)
        assertEquals(0, excerpt.omittedChars)
        assertFalse(excerpt.truncated)
    }

    @Test
    fun longOutputKeepsTheBeginningAndFailureTail() {
        val source = "START\n" + "x".repeat(80_000) + "\nFAILURE_TAIL"

        val excerpt = AgentRuntimeModelObservation.compact(source)

        assertTrue(excerpt.truncated)
        assertEquals(source.length, excerpt.totalChars)
        assertTrue(excerpt.omittedChars > 0)
        assertTrue(excerpt.text.length <= 24 * 1024)
        assertTrue(excerpt.text.startsWith("START"))
        assertTrue(excerpt.text.endsWith("FAILURE_TAIL"))
        assertTrue(excerpt.text.contains("SignalASI omitted ${excerpt.omittedChars} characters"))
    }

    @Test
    fun runtimeToolOutputPublishesCompactionMetadata() {
        val stdout = "begin\n" + "o".repeat(40_000) + "\nend"
        val result = AgentOnDeviceRuntimeTools.runtimeExecutionResult(
            AgentRuntimeExecutionResponse(
                exitCode = 0,
                stdout = stdout,
                stderr = "",
                durationMillis = 12L
            )
        )

        assertEquals(stdout.length, result.output["stdout_total_chars"])
        assertEquals(true, result.output["stdout_truncated"])
        assertTrue((result.output["stdout"] as String).endsWith("end"))
        assertEquals(false, result.output["stderr_truncated"])
        assertFalse(result.output.containsKey("stderr_omitted_chars"))
    }
}
