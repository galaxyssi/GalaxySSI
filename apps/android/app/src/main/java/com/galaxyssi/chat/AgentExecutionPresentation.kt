package com.galaxyssi.chat

enum class AgentExecutionLocationKind {
    PHONE,
    DESKTOP,
    CLOUD,
    CONNECTED_DEVICE,
    UNKNOWN
}

enum class AgentExecutionRuntimeKind {
    PHONE_NATIVE,
    PHONE_LINUX,
    PHONE_LOCAL_MODEL,
    PHONE_CLOUD_API,
    DESKTOP_AGENT,
    DESKTOP_TOOL,
    CONNECTED_DEVICE,
    KNOWLEDGE,
    UNKNOWN
}

data class AgentExecutionLocation(
    val contract: String = AgentExecutionLocationContract.VERSION,
    val locationKind: AgentExecutionLocationKind,
    val runtimeKind: AgentExecutionRuntimeKind,
    val locationId: String = "",
    val locationName: String = "",
    val runtimeId: String = "",
    val trusted: Boolean = true
)

object AgentExecutionLocationContract {
    const val VERSION = "galaxyssi.execution-location/1.0"
}

data class AgentExecutionPresentation(
    val executorId: String,
    val executorLabel: String,
    val locationKind: AgentExecutionLocationKind,
    val locationLabelHint: String,
    val runtimeKind: AgentExecutionRuntimeKind = AgentExecutionRuntimeKind.UNKNOWN,
    val runtimeLabelHint: String = "",
    val runtimeId: String = "",
    val locationId: String = "",
    val locationTrusted: Boolean = true,
    val currentStep: String,
    val phase: AgentPhase,
    val cancellable: Boolean,
    val startedAtMillis: Long,
    val completedAtMillis: Long = 0L
)

object AgentExecutionPresentationPolicy {
    fun location(
        route: AgentRoute?,
        action: AgentAction? = null
    ): AgentExecutionLocation {
        if (action?.isSupervisedProjectConnector() == true) {
            return AgentExecutionLocation(
                locationKind = AgentExecutionLocationKind.PHONE,
                runtimeKind = AgentExecutionRuntimeKind.PHONE_NATIVE,
                locationId = "galaxyssi-phone",
                runtimeId = "galaxyssi-supervised-project",
                trusted = true
            )
        }
        val routeKind = route?.kind ?: AgentRouteKind.UNKNOWN
        val targetParts = route?.targetTitle
            .orEmpty()
            .split(TARGET_SEPARATOR, limit = 2)
            .map(String::trim)
        val toolId = action?.parameters?.get("tool_id").orEmpty()
        val declaredLocation = route?.executionLocationKind
            ?.takeUnless { it == AgentExecutionLocationKind.UNKNOWN }
        val declaredRuntime = route?.executionRuntimeKind
            ?.takeUnless { it == AgentExecutionRuntimeKind.UNKNOWN }
        val nativeToolAction = action?.kind == AgentActionKind.CALL_NATIVE_TOOL
        val locationKind = declaredLocation ?: when {
            toolId == AgentOnDeviceRuntimeTools.EXECUTE -> AgentExecutionLocationKind.PHONE
            nativeToolAction -> AgentExecutionLocationKind.PHONE
            routeKind == AgentRouteKind.DESKTOP_AGENT -> AgentExecutionLocationKind.DESKTOP
            routeKind == AgentRouteKind.LOCAL_MODEL &&
                route?.executionDeviceId.orEmpty().isNotBlank() -> AgentExecutionLocationKind.DESKTOP
            routeKind == AgentRouteKind.DEVICE_CONNECTOR -> AgentExecutionLocationKind.CONNECTED_DEVICE
            routeKind == AgentRouteKind.CLOUD_MODEL -> AgentExecutionLocationKind.PHONE
            routeKind in setOf(
                AgentRouteKind.LOCAL_SYSTEM,
                AgentRouteKind.LOCAL_MODEL,
                AgentRouteKind.KNOWLEDGE
            ) -> AgentExecutionLocationKind.PHONE
            else -> AgentExecutionLocationKind.UNKNOWN
        }
        val runtimeKind = declaredRuntime ?: when {
            toolId == AgentOnDeviceRuntimeTools.EXECUTE -> AgentExecutionRuntimeKind.PHONE_LINUX
            nativeToolAction -> AgentExecutionRuntimeKind.PHONE_NATIVE
            routeKind == AgentRouteKind.DESKTOP_AGENT -> AgentExecutionRuntimeKind.DESKTOP_AGENT
            routeKind == AgentRouteKind.LOCAL_MODEL &&
                locationKind == AgentExecutionLocationKind.DESKTOP ->
                AgentExecutionRuntimeKind.DESKTOP_AGENT
            routeKind == AgentRouteKind.LOCAL_MODEL ->
                AgentExecutionRuntimeKind.PHONE_LOCAL_MODEL
            routeKind == AgentRouteKind.CLOUD_MODEL ->
                AgentExecutionRuntimeKind.PHONE_CLOUD_API
            routeKind == AgentRouteKind.DEVICE_CONNECTOR ->
                AgentExecutionRuntimeKind.CONNECTED_DEVICE
            routeKind == AgentRouteKind.KNOWLEDGE ->
                AgentExecutionRuntimeKind.KNOWLEDGE
            routeKind == AgentRouteKind.LOCAL_SYSTEM ->
                AgentExecutionRuntimeKind.PHONE_NATIVE
            else -> AgentExecutionRuntimeKind.UNKNOWN
        }
        return AgentExecutionLocation(
            locationKind = locationKind,
            runtimeKind = runtimeKind,
            locationId = route?.executionDeviceId.orEmpty(),
            locationName = route?.executionDeviceName.orEmpty()
                .ifBlank {
                    if (locationKind == AgentExecutionLocationKind.DESKTOP) {
                        targetParts.getOrNull(1).orEmpty()
                    } else {
                        ""
                    }
                },
            runtimeId = toolId.ifBlank { route?.targetId.orEmpty() },
            trusted = true
        )
    }

    fun location(record: AgentTaskRecord): AgentExecutionLocation {
        if (
            record.executionLocationKind != AgentExecutionLocationKind.UNKNOWN ||
            record.executionRuntimeKind != AgentExecutionRuntimeKind.UNKNOWN
        ) {
            return AgentExecutionLocation(
                locationKind = record.executionLocationKind,
                runtimeKind = record.executionRuntimeKind,
                locationId = record.executionLocationId,
                locationName = record.executionLocationName,
                runtimeId = record.executionRuntimeId,
                trusted = record.executionLocationTrusted
            )
        }
        return location(
            AgentRoute(
                kind = record.routeKind,
                targetTitle = record.targetTitle
            )
        )
    }

    fun local(
        route: AgentRoute,
        action: AgentAction?,
        selectedAgentOrModel: String,
        phase: AgentPhase,
        currentStep: String,
        startedAtMillis: Long,
        completedAtMillis: Long = 0L
    ): AgentExecutionPresentation {
        val location = location(route, action)
        return local(
            routeKind = route.kind,
            targetTitle = route.targetTitle,
            selectedAgentOrModel = selectedAgentOrModel,
            phase = phase,
            currentStep = currentStep,
            startedAtMillis = startedAtMillis,
            completedAtMillis = completedAtMillis,
            resolvedLocation = location
        )
    }

    fun local(
        routeKind: AgentRouteKind,
        targetTitle: String,
        selectedAgentOrModel: String,
        phase: AgentPhase,
        currentStep: String,
        startedAtMillis: Long,
        completedAtMillis: Long = 0L,
        resolvedLocation: AgentExecutionLocation? = null
    ): AgentExecutionPresentation {
        val target = targetTitle.trim().ifBlank { selectedAgentOrModel.trim() }
        val targetParts = target.split(TARGET_SEPARATOR, limit = 2).map(String::trim)
        val executor = when (routeKind) {
            AgentRouteKind.LOCAL_SYSTEM,
            AgentRouteKind.KNOWLEDGE,
            AgentRouteKind.UNKNOWN -> "GalaxySSI"
            else -> targetParts.firstOrNull().orEmpty().ifBlank { "GalaxySSI" }
        }
        val locationKind = when (routeKind) {
            AgentRouteKind.CLOUD_MODEL -> AgentExecutionLocationKind.PHONE
            AgentRouteKind.DESKTOP_AGENT -> AgentExecutionLocationKind.DESKTOP
            AgentRouteKind.DEVICE_CONNECTOR -> AgentExecutionLocationKind.CONNECTED_DEVICE
            AgentRouteKind.LOCAL_SYSTEM,
            AgentRouteKind.LOCAL_MODEL,
            AgentRouteKind.KNOWLEDGE -> AgentExecutionLocationKind.PHONE
            AgentRouteKind.UNKNOWN -> AgentExecutionLocationKind.UNKNOWN
        }
        val location = resolvedLocation ?: AgentExecutionLocation(
            locationKind = locationKind,
            runtimeKind = when (routeKind) {
                AgentRouteKind.LOCAL_SYSTEM -> AgentExecutionRuntimeKind.PHONE_NATIVE
                AgentRouteKind.CLOUD_MODEL -> AgentExecutionRuntimeKind.PHONE_CLOUD_API
                AgentRouteKind.LOCAL_MODEL -> AgentExecutionRuntimeKind.PHONE_LOCAL_MODEL
                AgentRouteKind.DESKTOP_AGENT -> AgentExecutionRuntimeKind.DESKTOP_AGENT
                AgentRouteKind.DEVICE_CONNECTOR -> AgentExecutionRuntimeKind.CONNECTED_DEVICE
                AgentRouteKind.KNOWLEDGE -> AgentExecutionRuntimeKind.KNOWLEDGE
                AgentRouteKind.UNKNOWN -> AgentExecutionRuntimeKind.UNKNOWN
            },
            locationName = if (locationKind == AgentExecutionLocationKind.DESKTOP) {
                targetParts.getOrNull(1).orEmpty()
            } else {
                ""
            }
        )
        return AgentExecutionPresentation(
            executorId = targetParts.firstOrNull().orEmpty().ifBlank { "galaxyssi" },
            executorLabel = executor,
            locationKind = location.locationKind,
            locationLabelHint = location.locationName,
            runtimeKind = location.runtimeKind,
            runtimeLabelHint = "",
            runtimeId = location.runtimeId,
            locationId = location.locationId,
            locationTrusted = location.trusted,
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
        locationId: String = "",
        locationName: String,
        runtimeKind: String = "",
        runtimeId: String = "",
        runtimeName: String = "",
        contract: String = "",
        status: String,
        currentStep: String,
        startedAtMillis: Long,
        completedAtMillis: Long,
        advertisedCancellable: Boolean
    ): AgentExecutionPresentation {
        val phase = phaseForRemoteStatus(status)
        val declaredLocation = when (locationKind.trim().lowercase()) {
            "desktop", "windows", "macos", "linux" -> AgentExecutionLocationKind.DESKTOP
            else -> AgentExecutionLocationKind.UNKNOWN
        }
        val trustedLocation = contract == AgentExecutionLocationContract.VERSION &&
            declaredLocation == AgentExecutionLocationKind.DESKTOP &&
            locationId.isNotBlank()
        return AgentExecutionPresentation(
            executorId = executorId.trim().ifBlank { executorLabel.trim() },
            executorLabel = executorLabel.trim().ifBlank { executorId.trim() }.ifBlank { "Agent" },
            locationKind = AgentExecutionLocationKind.DESKTOP,
            locationLabelHint = locationName.trim(),
            runtimeKind = when (runtimeKind.trim().lowercase()) {
                "desktop_tool" -> AgentExecutionRuntimeKind.DESKTOP_TOOL
                "desktop_agent", "agent" -> AgentExecutionRuntimeKind.DESKTOP_AGENT
                else -> AgentExecutionRuntimeKind.DESKTOP_AGENT
            },
            runtimeLabelHint = runtimeName.trim(),
            runtimeId = runtimeId.trim(),
            locationId = locationId.trim(),
            locationTrusted = trustedLocation,
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

    fun phaseForRemoteStatus(status: String): AgentPhase =
        AgentRemoteTaskStatusPolicy.phase(status)

    private const val TARGET_SEPARATOR = " \u00b7 "
}
