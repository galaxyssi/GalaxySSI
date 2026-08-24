package com.signalasi.chat

internal data class AgentTaskPersistenceFingerprint(
    val taskId: String,
    val sessionId: String,
    val goal: String,
    val phase: AgentPhase,
    val routeKind: AgentRouteKind,
    val targetTitle: String,
    val risk: AgentRisk,
    val blocked: Boolean,
    val executionLocationKind: AgentExecutionLocationKind,
    val executionRuntimeKind: AgentExecutionRuntimeKind,
    val executionLocationId: String,
    val executionLocationName: String,
    val executionRuntimeId: String,
    val executionLocationTrusted: Boolean,
    val result: String,
    val verification: String,
    val actionLog: List<String>
)

internal class AgentTaskPersistenceGate {
    private var lastPersisted: AgentTaskPersistenceFingerprint? = null

    @Synchronized
    fun persistIfChanged(
        fingerprint: AgentTaskPersistenceFingerprint,
        persist: () -> Unit
    ): Boolean {
        if (fingerprint == lastPersisted) return false
        persist()
        lastPersisted = fingerprint
        return true
    }
}
