package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class AgentRuntimeExecutionFailureDiagnosisTest {
    @Test
    fun deterministicPreflightFailureBecomesAStructuredModelObservation() {
        val recoveryCandidates = listOf(
            mapOf(
                "executable" to "java",
                "install_runtime_pack" to mapOf("tool_id" to AgentLinuxSoftwareNativeTools.INSTALL)
            )
        )
        val result = AgentOnDeviceRuntimeTools.runtimeExecutionResult(
            AgentRuntimeExecutionResponse(
                exitCode = 127,
                stdout = "",
                stderr = "SignalASI missing executable: java\nSignalASI missing executable: gradle\n",
                durationMillis = 4L
            ),
            recoveryCandidates = recoveryCandidates
        )

        val diagnosis = result.output["failure_diagnosis"] as Map<*, *>
        assertFalse(result.isSuccess)
        assertEquals("on_device_runtime_missing_executable", result.error?.code)
        assertEquals("missing_executable", diagnosis["kind"])
        assertEquals(listOf("java", "gradle"), diagnosis["missing_executables"])
        assertEquals(recoveryCandidates, diagnosis["recovery_candidates"])
        assertEquals(diagnosis, result.error?.details?.get("failure_diagnosis"))
    }

    @Test
    fun softwareRecoveryCandidatesExposeDirectAndSearchActions() {
        val candidates = AgentLinuxSoftwareNativeTools.recoveryCandidates(
            executables = listOf("java", "pnpm", "mvn"),
            statuses = listOf(
                AgentRuntimePackStatus("java", AgentRuntimePackState.NOT_INSTALLED),
                AgentRuntimePackStatus("node-js", AgentRuntimePackState.READY)
            ),
            architecture = "arm64-v8a"
        )

        val java = candidates.first { it["executable"] == "java" }
        val pnpm = candidates.first { it["executable"] == "pnpm" }
        val maven = candidates.first { it["executable"] == "mvn" }
        assertEquals(
            "java",
            ((java["install_runtime_pack"] as Map<*, *>)["arguments"] as Map<*, *>)["software_id"]
        )
        assertEquals(listOf("node-js"), (pnpm["managed_runtime_packs"] as List<*>)
            .map { (it as Map<*, *>)["software_id"] })
        assertEquals(AgentLinuxSoftwareNativeTools.SEARCH, (maven["search_software"] as Map<*, *>)["tool_id"])
        assertFalse(maven.containsKey("install_runtime_pack"))
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
