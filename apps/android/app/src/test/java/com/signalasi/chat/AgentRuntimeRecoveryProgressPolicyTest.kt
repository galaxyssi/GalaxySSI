package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeRecoveryProgressPolicyTest {
    @Test
    fun unchangedCommandWaitsForDependencyRecovery() {
        val violation = AgentSupervisedProjectProgressPolicy.violation(
            runtimeAction("retry", "gradle test"),
            listOf(missingRuntimeFailure("failed", "gradle test"))
        )

        assertTrue(violation.orEmpty().contains("gradle"))
        assertTrue(violation.orEmpty().contains(AgentLinuxSoftwareNativeTools.INSTALL))
        assertTrue(violation.orEmpty().contains(AgentLinuxSoftwareNativeTools.SEARCH))
    }

    @Test
    fun correctedCommandRemainsAvailableToTheModel() {
        val violation = AgentSupervisedProjectProgressPolicy.violation(
            runtimeAction("retry", "./gradlew test"),
            listOf(missingRuntimeFailure("failed", "gradle test"))
        )

        assertNull(violation)
    }

    @Test
    fun successfulManagedInstallAllowsBlockedCommandRetry() {
        val history = listOf(
            missingRuntimeFailure("failed", "gradle test"),
            toolAction(AgentLinuxSoftwareNativeTools.INSTALL, "install")
        )

        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(
                runtimeAction("retry", "gradle test"),
                history
            )
        )
    }

    @Test
    fun successfulLinuxPackageInstallAllowsBlockedCommandRetry() {
        val history = listOf(
            missingRuntimeFailure("failed", "gradle test"),
            runtimeAction("install", "apt-get install -y gradle")
        )

        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(
                runtimeAction("retry", "gradle test"),
                history
            )
        )
    }

    @Test
    fun searchWithoutInstallDoesNotPretendDependencyRecovered() {
        val history = listOf(
            missingRuntimeFailure("failed", "gradle test"),
            toolAction(AgentLinuxSoftwareNativeTools.SEARCH, "search")
        )

        assertTrue(
            AgentSupervisedProjectProgressPolicy.violation(
                runtimeAction("retry", "gradle test"),
                history
            ).orEmpty().contains("Do not run it unchanged yet")
        )
    }

    @Test
    fun ordinaryRuntimeFailureIsLeftForModelDiagnosis() {
        val failure = runtimeAction("failed", "gradle test").copy(
            status = AgentActionStatus.FAILED,
            evidence = JSONObject().put("exit_code", 1).put("stderr", "Tests failed").toString()
        )

        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(
                runtimeAction("retry", "gradle test"),
                listOf(failure)
            )
        )
    }

    @Test
    fun runtimeDiagnosisStaysInsidePersistedEvidencePrefix() {
        val result = AgentOnDeviceRuntimeTools.runtimeExecutionResult(
            AgentRuntimeExecutionResponse(
                exitCode = 127,
                stdout = "x".repeat(50_000),
                stderr = "SignalASI missing executable: gradle",
                durationMillis = 10L
            )
        )
        val persistedPrefix = AgentNativeJsonCodec.stringify(result.output).take(12_000)

        assertTrue(persistedPrefix.contains("failure_diagnosis"))
        assertTrue(persistedPrefix.contains("missing_executable"))
    }

    private fun missingRuntimeFailure(id: String, source: String): AgentAction {
        val diagnosis = JSONObject()
            .put("kind", "missing_executable")
            .put("missing_executables", JSONArray().put("gradle"))
            .put(
                "recovery_candidates",
                JSONArray().put(
                    JSONObject()
                        .put("executable", "gradle")
                        .put(
                            "install_runtime_pack",
                            JSONObject().put("tool_id", AgentLinuxSoftwareNativeTools.INSTALL)
                        )
                        .put(
                            "search_software",
                            JSONObject().put("tool_id", AgentLinuxSoftwareNativeTools.SEARCH)
                        )
                )
            )
        return runtimeAction(id, source).copy(
            status = AgentActionStatus.FAILED,
            evidence = JSONObject().put("failure_diagnosis", diagnosis).toString()
        )
    }

    private fun runtimeAction(id: String, source: String): AgentAction = toolAction(
        AgentOnDeviceRuntimeTools.EXECUTE,
        id,
        JSONObject()
            .put("workspace_id", "current")
            .put("language", "shell")
            .put("source", source)
            .toString()
    )

    private fun toolAction(toolId: String, id: String, input: String = "{}"): AgentAction = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = toolId,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = toolId,
        parameters = mapOf("tool_id" to toolId, "input_json" to input),
        requiresConfirmation = false
    )
}
