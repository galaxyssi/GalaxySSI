package com.galaxyssi.chat

/** Protocol failures are observations, never instructions to repeat a browser mutation. */
internal object AgentBrowserInterruptionPolicy {
    private val lostSessionCodes = setOf("session_lost", "session_closed", "session_not_found", "browser_closed")
    private val recordedCodes = lostSessionCodes + setOf("browser_host_restarted", "browser_user_handoff_invalid",
        "browser_runtime_exited", "browser_runtime_replaced")

    fun valid(code: String) = code in recordedCodes

    fun observed(record: AgentBrowserUserRequest, code: String, input: AgentNativeJsonObject): AgentBrowserUserRequest? {
        if (record.state != "active" || record.handoffId.isBlank()) return null
        val handoffInspection = input["operation"] in setOf("human_control_state", "human_control_finish") ||
            input["operation"] == "human_control_execute" &&
            (input["action"] as? Map<*, *>)?.get("operation") == "snapshot"
        if (code !in lostSessionCodes && !(code == "browser_user_handoff_invalid" && handoffInspection)) return null
        return record.copy(state = "interrupted", interruptionCode = code)
    }

    fun message(code: String): String {
        val cause = if (code == "browser_host_restarted")
            "The App host restarted while this task was waiting; browser availability is unconfirmed, not proved lost."
        else "The browser host reported $code for the recorded user-control handoff."
        return "$cause Control ownership, authentication and business results are unconfirmed. " +
            "Inspect the existing runtime and browser before choosing a repair; no browser mutation was replayed."
    }
}
