package com.signalasi.chat

internal object AgentRuntimeExecutionFailureDiagnosis {
    fun from(response: AgentRuntimeExecutionResponse): AgentNativeJsonObject? {
        if (response.exitCode != MISSING_EXECUTABLE_EXIT_CODE) return null
        val missing = response.stderr.lineSequence()
            .map(String::trim)
            .filter { line -> line.startsWith(MISSING_EXECUTABLE_PREFIX) }
            .map { line -> line.removePrefix(MISSING_EXECUTABLE_PREFIX).trim() }
            .filter { executable -> EXECUTABLE_NAME.matches(executable) }
            .distinct()
            .take(MAX_MISSING_EXECUTABLES)
            .toList()
        if (missing.isEmpty()) return null
        return linkedMapOf(
            "kind" to "missing_executable",
            "missing_executables" to missing,
            "next_action" to "inspect available runtime packs or Linux packages, install the smallest match, then retry"
        )
    }

    private val EXECUTABLE_NAME = Regex("[A-Za-z0-9._+-]{1,128}")
    private const val MISSING_EXECUTABLE_PREFIX = "SignalASI missing executable: "
    private const val MISSING_EXECUTABLE_EXIT_CODE = 127
    private const val MAX_MISSING_EXECUTABLES = 16
}
