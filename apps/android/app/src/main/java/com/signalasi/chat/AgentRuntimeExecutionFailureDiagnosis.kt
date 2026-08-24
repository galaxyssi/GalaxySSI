package com.signalasi.chat

internal object AgentRuntimeExecutionFailureDiagnosis {
    fun missingExecutables(response: AgentRuntimeExecutionResponse): List<String> {
        if (response.exitCode != MISSING_EXECUTABLE_EXIT_CODE) return emptyList()
        return response.stderr.lineSequence()
            .map(String::trim)
            .filter { line -> line.startsWith(MISSING_EXECUTABLE_PREFIX) }
            .map { line -> line.removePrefix(MISSING_EXECUTABLE_PREFIX).trim() }
            .filter { executable -> EXECUTABLE_NAME.matches(executable) }
            .distinct()
            .take(MAX_MISSING_EXECUTABLES)
            .toList()
    }

    fun from(
        response: AgentRuntimeExecutionResponse,
        recoveryCandidates: List<AgentNativeJsonObject> = emptyList()
    ): AgentNativeJsonObject? {
        val missing = missingExecutables(response)
        if (missing.isEmpty()) return null
        return buildMap {
            put("kind", "missing_executable")
            put("missing_executables", missing)
            put(
                "next_action",
                "use a supplied recovery action, observe it, then retry the exact blocked command"
            )
            if (recoveryCandidates.isNotEmpty()) put("recovery_candidates", recoveryCandidates)
        }
    }

    private val EXECUTABLE_NAME = Regex("[A-Za-z0-9._+-]{1,128}")
    private const val MISSING_EXECUTABLE_PREFIX = "SignalASI missing executable: "
    private const val MISSING_EXECUTABLE_EXIT_CODE = 127
    private const val MAX_MISSING_EXECUTABLES = 16
}
