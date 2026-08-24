package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class AgentRuntimeExecutionFailureDiagnosisTest {
    @Test
    fun deterministicPreflightFailureBecomesAStructuredModelObservation() {
        val result = AgentOnDeviceRuntimeTools.runtimeExecutionResult(
            AgentRuntimeExecutionResponse(
                exitCode = 127,
                stdout = "",
                stderr = "SignalASI missing executable: java\nSignalASI missing executable: gradle\n",
                durationMillis = 4L
            )
        )

        val diagnosis = result.output["failure_diagnosis"] as Map<*, *>
        assertFalse(result.isSuccess)
        assertEquals("on_device_runtime_missing_executable", result.error?.code)
        assertEquals("missing_executable", diagnosis["kind"])
        assertEquals(listOf("java", "gradle"), diagnosis["missing_executables"])
        assertEquals(diagnosis, result.error?.details?.get("failure_diagnosis"))
    }

    @Test
    fun arbitraryShellErrorsAreNotMisclassified() {
        val response = AgentRuntimeExecutionResponse(
            exitCode = 127,
            stdout = "",
            stderr = "sh: unknown-tool: not found",
            durationMillis = 4L
        )

        assertNull(AgentRuntimeExecutionFailureDiagnosis.from(response))
        assertEquals(
            "on_device_runtime_nonzero_exit",
            AgentOnDeviceRuntimeTools.runtimeExecutionResult(response).error?.code
        )
    }
}
