package com.signalasi.chat

enum class AgentExecutionLocationKind {
    PHONE,
    DESKTOP,
    CLOUD,
    CONNECTED_DEVICE,
    UNKNOWN
}

data class AgentExecutionPresentation(
    val executorId: String,
    val executorLabel: String,
    val locationKind: AgentExecutionLocationKind,
    val locationLabelHint: String,
    val currentStep: String,
    val phase: AgentPhase,
    val cancellable: Boolean,
    val startedAtMillis: Long,
    val completedAtMillis: Long = 0L
)

object AgentExecutionPresentationPolicy {
    fun local(
        routeKind: AgentRouteKind,
        targetTitle: String,
        selectedAgentOrModel: String,
        phase: AgentPhase,
        currentStep: String,
        startedAtMillis: Long,
        completedAtMillis: Long = 0L
    ): AgentExecutionPresentation {
        val target = targetTitle.trim().ifBlank { selectedAgentOrModel.trim() }
        val targetParts = target.split(TARGET_SEPARATOR, limit = 2).map(String::trim)
        val executor = when (routeKind) {
            AgentRouteKind.LOCAL_SYSTEM,
            AgentRouteKind.KNOWLEDGE,
            AgentRouteKind.UNKNOWN -> "SignalASI"
            else -> targetParts.firstOrNull().orEmpty().ifBlank { "SignalASI" }
        }
        val locationKind = when (routeKind) {
            AgentRouteKind.CLOUD_MODEL -> AgentExecutionLocationKind.CLOUD
            AgentRouteKind.DESKTOP_AGENT -> AgentExecutionLocationKind.DESKTOP
            AgentRouteKind.DEVICE_CONNECTOR -> AgentExecutionLocationKind.CONNECTED_DEVICE
            AgentRouteKind.LOCAL_SYSTEM,
            AgentRouteKind.LOCAL_MODEL,
            AgentRouteKind.KNOWLEDGE -> AgentExecutionLocationKind.PHONE
            AgentRouteKind.UNKNOWN -> AgentExecutionLocationKind.UNKNOWN
        }
        return AgentExecutionPresentation(
            executorId = targetParts.firstOrNull().orEmpty().ifBlank { "signalasi" },
            executorLabel = executor,
            locationKind = locationKind,
            locationLabelHint = if (locationKind == AgentExecutionLocationKind.DESKTOP) {
                targetParts.getOrNull(1).orEmpty()
            } else {
                ""
            },
            currentStep = currentStep.trim(),
            phase = phase,
            cancellable = isCancellable(phase),
            startedAtMillis = startedAtMillis,
            completedAtMillis = completedAtMillis
        )
    }

    fun remote(
        executorId: String,
        executorLabel: String,
        locationKind: String,
        locationName: String,
        status: String,
        currentStep: String,
        startedAtMillis: Long,
        completedAtMillis: Long,
        advertisedCancellable: Boolean
    ): AgentExecutionPresentation {
        val phase = phaseForRemoteStatus(status)
        return AgentExecutionPresentation(
            executorId = executorId.trim().ifBlank { executorLabel.trim() },
            executorLabel = executorLabel.trim().ifBlank { executorId.trim() }.ifBlank { "Agent" },
            locationKind = when (locationKind.trim().lowercase()) {
                "phone", "android", "ios" -> AgentExecutionLocationKind.PHONE
                "desktop", "windows", "macos", "linux" -> AgentExecutionLocationKind.DESKTOP
                "cloud" -> AgentExecutionLocationKind.CLOUD
                "device", "connected_device" -> AgentExecutionLocationKind.CONNECTED_DEVICE
                else -> AgentExecutionLocationKind.UNKNOWN
            },
            locationLabelHint = locationName.trim(),
            currentStep = currentStep.trim(),
            phase = phase,
            cancellable = advertisedCancellable && isCancellable(phase),
            startedAtMillis = startedAtMillis,
            completedAtMillis = completedAtMillis
        )
    }

    fun isCancellable(phase: AgentPhase): Boolean = phase !in setOf(
        AgentPhase.COMPLETED,
        AgentPhase.FAILED,
        AgentPhase.CANCELLED,
        AgentPhase.BLOCKED
    )

    fun phaseForRemoteStatus(status: String): AgentPhase = when (status.trim().lowercase()) {
        "waiting_input", "waiting_approval" -> AgentPhase.PAUSED
        "completed" -> AgentPhase.COMPLETED
        "failed", "timed_out", "not_found" -> AgentPhase.FAILED
        "cancelled" -> AgentPhase.CANCELLED
        else -> AgentPhase.EXECUTING
    }

    private const val TARGET_SEPARATOR = " \u00b7 "
}
