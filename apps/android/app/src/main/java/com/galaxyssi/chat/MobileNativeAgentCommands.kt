package com.galaxyssi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunRequest
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiMerger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.Date
import java.text.SimpleDateFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

internal fun MobileNativeAgent.saveMemoryCommand(value: String): AgentUiState {
    val blockReason = if (activeConversationContext.privateMode) {
        "Private sessions cannot write long-term memory"
    } else {
        memoryBlockReason(value, currentScreen)
    }
    var writeResult: AgentMemoryWriteResult? = null
    val resultMessage = if (blockReason == null) "Saved personal memory" else blockReason
    val action = AgentAction(
        id = "save-memory",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Memory",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Save personal memory",
        result = resultMessage
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Memory",
        confirmationRequired = false,
        expectedResult = resultMessage,
        route = AgentRoute(
            routeId = "agent-memory",
            kind = AgentRouteKind.KNOWLEDGE,
            targetId = "agent-memory",
            targetTitle = "Agent Memory",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.KNOWLEDGE_SEARCH)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    if (blockReason == null) {
        writeResult = memoryStore.remember(memoryItemFromCommand(value))
        writeResult?.conflict?.let { conflict ->
            recordAudit(
                AgentAuditEvent.MEMORY_CONFLICT_DETECTED,
                "group:${conflict.groupId}; candidates:${conflict.candidates.size}"
            )
        }
    } else {
        recordAudit(AgentAuditEvent.MEMORY_SKIPPED, blockReason)
    }
    val finalMessage = if (writeResult?.conflict != null) {
        "Memory conflict needs review"
    } else {
        resultMessage
    }
    currentPlan = currentPlan?.copy(
        actions = listOf(action.copy(result = finalMessage)),
        expectedResult = finalMessage
    )
    lastActionResult = AgentActionResult(action.id, blockReason == null, finalMessage)
    if (writeResult?.item != null && writeResult?.conflict == null) {
        recordAudit(
            AgentAuditEvent.MEMORY_UPDATED,
            "item:${writeResult?.item?.id}; version:${writeResult?.item?.version}; duplicate:${writeResult?.duplicate}"
        )
    }
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    saveTaskRecord(result = finalMessage)
    return snapshot()
}

internal fun MobileNativeAgent.memoryItemFromCommand(rawValue: String): AgentMemoryItem {
    val cleanValue = rawValue.trim()
    val typedPrefixes = listOf(
        "profile" to AgentMemoryKind.IDENTITY,
        "identity" to AgentMemoryKind.IDENTITY,
        "contact" to AgentMemoryKind.CONTACT,
        "preference" to AgentMemoryKind.PREFERENCE,
        "workflow" to AgentMemoryKind.WORKFLOW,
        "security" to AgentMemoryKind.SAFETY,
        "safety" to AgentMemoryKind.SAFETY,
        "knowledge" to AgentMemoryKind.KNOWLEDGE,
        "\u8eab\u4efd" to AgentMemoryKind.IDENTITY,
        "\u8054\u7cfb\u4eba" to AgentMemoryKind.CONTACT,
        "\u504f\u597d" to AgentMemoryKind.PREFERENCE,
        "\u5de5\u4f5c\u6d41" to AgentMemoryKind.WORKFLOW,
        "\u5b89\u5168" to AgentMemoryKind.SAFETY,
        "\u77e5\u8bc6" to AgentMemoryKind.KNOWLEDGE
    )
    val typed = typedPrefixes.firstOrNull { (prefix, _) ->
        cleanValue.startsWith("$prefix:", ignoreCase = true)
    }
    val content = typed?.first?.let { prefix -> cleanValue.drop(prefix.length + 1).trim() }
        ?.takeIf { it.isNotBlank() }
        ?: cleanValue
    val keySeparator = listOf(content.indexOf('='), content.indexOf(':'))
        .filter { it in 1..64 }
        .minOrNull()
    return AgentMemoryItem(
        kind = typed?.second ?: AgentMemoryKind.KNOWLEDGE,
        value = content,
        source = "agent_memory_command",
        key = keySeparator?.let { content.substring(0, it).trim() }.orEmpty()
    )
}

internal fun MobileNativeAgent.showRecentTasksCommand(): AgentUiState {
    val tasks = taskStore.recent(limit = 8)
    val result = if (tasks.isEmpty()) {
        "No recent Agent tasks"
    } else {
        tasks.joinToString(" | ") { task ->
            val status = when {
                task.blocked -> "blocked"
                task.phase == AgentPhase.COMPLETED -> "done"
                task.phase == AgentPhase.FAILED -> "failed"
                task.phase == AgentPhase.CANCELLED -> "cancelled"
                else -> task.phase.name.lowercase(Locale.US)
            }
            "${task.goal.take(48)}:$status:${task.targetTitle.take(32)}"
        }
    }
    val action = AgentAction(
        id = "show-recent-tasks",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Task History",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Show recent Agent tasks",
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Task History",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-task-history",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-task-history",
            targetTitle = "Agent Task History",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.searchTasksCommand(query: String): AgentUiState {
    val tasks = taskStore.search(query, limit = 8)
    val result = if (tasks.isEmpty()) {
        "No task history hits for \"$query\""
    } else {
        tasks.joinToString(" | ") { task ->
            val status = when {
                task.blocked -> "blocked"
                task.phase == AgentPhase.COMPLETED -> "done"
                task.phase == AgentPhase.FAILED -> "failed"
                task.phase == AgentPhase.CANCELLED -> "cancelled"
                else -> task.phase.name.lowercase(Locale.US)
            }
            "${task.goal.take(48)}:$status:${task.targetTitle.take(32)}"
        }
    }
    val action = AgentAction(
        id = "search-task-history",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Task History",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Search Agent task history",
        parameters = mapOf("query" to query),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Task History",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-task-history",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-task-history",
            targetTitle = "Agent Task History",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.showCallableInventoryCommand(filter: CallableInventoryFilter): AgentUiState {
    val targets = connectorRegistry.availableTargets()
    val tools = workflowSystemTools() + AgentSystemToolPlanner.availableTools()
    val result = callableInventorySummary(filter, targets, tools)
    val action = AgentAction(
        id = "show-callable-inventory",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Tool Router",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Show Agent callable inventory",
        parameters = mapOf("filter" to filter.name),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Tool Router",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-tool-router",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-tool-router",
            targetTitle = "Agent Tool Router",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.searchCallableInventoryCommand(query: String): AgentUiState {
    val targets = connectorRegistry.availableTargets()
    val tools = workflowSystemTools() + AgentSystemToolPlanner.availableTools()
    val result = callableInventorySearchSummary(query, targets, tools)
    val action = AgentAction(
        id = "search-callable-inventory",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Tool Router",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Search Agent callable inventory",
        parameters = mapOf("query" to query),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Tool Router",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-tool-router",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-tool-router",
            targetTitle = "Agent Tool Router",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.showSecurityStatusCommand(): AgentUiState {
    val settings = safetySettingsStore.load()
    val result = buildString {
        append("mode=").append(settings.permissionMode.name.lowercase(Locale.US))
        append("; high_risk_guard=").append(settings.highRiskGuard)
        append("; memory_capture=").append(settings.memoryCapture)
        append("; accessibility=").append(currentScreen.isAccessibilityEnabled)
        append("; notifications=").append(currentScreen.notifications.hasAccess)
        append("; clipboard=").append(currentScreen.clipboard.hasText)
        append("; sensitive_screen_flags=").append(currentScreen.sensitiveFlagCount)
        append("; sensitive_notifications=").append(currentScreen.notifications.sensitiveFlags.size)
        append("; sensitive_clipboard=").append(currentScreen.clipboard.sensitiveFlags.size)
    }
    val action = AgentAction(
        id = "show-security-status",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Security",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Show Agent security and permission status",
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Security",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-security",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-security",
            targetTitle = "Agent Security",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.showPermissionChecklistCommand(): AgentUiState {
    val microphoneGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
        appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    val postNotificationsGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    val batteryUnrestricted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
        runCatching {
            appContext.getSystemService(PowerManager::class.java)
                ?.isIgnoringBatteryOptimizations(appContext.packageName) == true
        }.getOrDefault(false)
    val items = listOf(
        AgentPermissionChecklistItem(
            title = "Screen Agent",
            ready = currentScreen.isAccessibilityEnabled,
            required = true,
            fixCommand = "open accessibility settings"
        ),
        AgentPermissionChecklistItem(
            title = "Notification access",
            ready = currentScreen.notifications.hasAccess,
            required = false,
            fixCommand = "open notification access settings"
        ),
        AgentPermissionChecklistItem(
            title = "Microphone",
            ready = microphoneGranted,
            required = false,
            fixCommand = "start a voice action to request access"
        ),
        AgentPermissionChecklistItem(
            title = "Post notifications",
            ready = postNotificationsGranted,
            required = false,
            fixCommand = "open GalaxySSI app permissions"
        ),
        AgentPermissionChecklistItem(
            title = "Background battery access",
            ready = batteryUnrestricted,
            required = false,
            fixCommand = "open battery settings"
        )
    )
    val readyCount = items.count { it.ready }
    val requiredMissing = items.count { it.required && !it.ready }
    val result = buildString {
        append("Agent permissions: ").append(readyCount).append("/").append(items.size).append(" ready")
        items.forEach { item ->
            append("\n").append(if (item.ready) "ready" else "missing")
            append(": ").append(item.title)
            if (!item.ready) append(" -> ").append(item.fixCommand)
            if (item.required) append(" [required]")
        }
    }
    val action = AgentAction(
        id = "show-permission-checklist",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Permissions",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Show Agent permission readiness checklist",
        parameters = mapOf(
            "ready_count" to readyCount.toString(),
            "permission_count" to items.size.toString(),
            "required_missing" to requiredMissing.toString()
        ),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Permissions",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-permissions",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-permissions",
            targetTitle = "Agent Permissions",
            status = if (requiredMissing == 0) AgentConnectorStatus.AVAILABLE else AgentConnectorStatus.NEEDS_SETUP,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.SYSTEM_SETTINGS, AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.showScreenOverviewCommand(): AgentUiState {
    val screen = currentScreen
    val sensitive = screen.sensitiveFlagCount > 0 || screen.sensitiveFlags.isNotEmpty()
    val result = when {
        !screen.isAccessibilityEnabled -> "Screen Agent permission is disabled"
        sensitive -> buildString {
            append("Screen: ").append(screen.pageTitle.ifBlank { screen.foregroundApp })
            append("; app=").append(screen.foregroundApp)
            append("; text=").append(screen.visibleTextCount)
            append("; actions=").append(screen.clickableNodeCount)
            append("; fields=").append(screen.inputFieldCount)
            append("; scroll_regions=").append(screen.scrollableRegionCount)
            append("\nSensitive values hidden: ").append(screen.sensitiveFlags.joinToString(", "))
        }
        else -> buildString {
            append("Screen: ").append(screen.pageTitle.ifBlank { screen.foregroundApp })
            append("\nApp: ").append(screen.foregroundApp)
            if (screen.activityName.isNotBlank()) append("\nActivity: ").append(screen.activityName)
            append("\nElements: text=").append(screen.visibleTextCount)
            append(", actions=").append(screen.clickableNodeCount)
            append(", fields=").append(screen.inputFieldCount)
            append(", scroll_regions=").append(screen.scrollableRegionCount)
            if (screen.selectedText.isNotBlank()) {
                append("\nSelected: ").append(screen.selectedText.replace(Regex("\\s+"), " ").take(160))
            }
            screen.visibleTexts.distinct().take(12).forEach { text ->
                append("\ntext: ").append(text.replace(Regex("\\s+"), " ").take(140))
            }
            screen.clickableElements.take(12).forEach { element ->
                append("\naction: ").append(screenElementTitle(element)).append(" @ ").append(element.bounds)
            }
            screen.inputFields.take(8).forEach { element ->
                append("\nfield: ").append(screenElementTitle(element)).append(" @ ").append(element.bounds)
            }
            screen.scrollableRegions.take(6).forEach { element ->
                append("\nscroll: ").append(screenElementTitle(element)).append(" @ ").append(element.bounds)
            }
        }
    }
    return completeScreenInspectionCommand(
        actionId = "show-screen-overview",
        description = "Show current screen structure",
        result = result,
        parameters = mapOf(
            "text_count" to screen.visibleTextCount.toString(),
            "action_count" to screen.clickableNodeCount.toString(),
            "field_count" to screen.inputFieldCount.toString(),
            "scroll_region_count" to screen.scrollableRegionCount.toString()
        )
    )
}

internal fun MobileNativeAgent.searchCurrentScreenCommand(query: String): AgentUiState {
    val screen = currentScreen
    val cleanQuery = query.trim().lowercase(Locale.US)
    val sensitive = screen.sensitiveFlagCount > 0 || screen.sensitiveFlags.isNotEmpty()
    val matches = if (sensitive || cleanQuery.isBlank()) {
        emptyList()
    } else {
        buildList {
            screen.visibleTexts.forEach { value -> add("text" to value) }
            screen.clickableElements.forEach { element -> add("action" to screenElementTitle(element)) }
            screen.inputFields.forEach { element -> add("field" to screenElementTitle(element)) }
            screen.scrollableRegions.forEach { element -> add("scroll" to screenElementTitle(element)) }
        }.filter { (_, value) -> value.lowercase(Locale.US).contains(cleanQuery) }
            .distinct()
            .take(20)
    }
    val result = when {
        !screen.isAccessibilityEnabled -> "Screen Agent permission is disabled"
        sensitive -> "Screen contains sensitive content; element values are hidden"
        matches.isEmpty() -> "No current screen elements match '$query'"
        else -> buildString {
            append("Screen matches: ").append(matches.size)
            matches.forEach { (kind, value) ->
                append("\n").append(kind).append(": ")
                append(value.replace(Regex("\\s+"), " ").take(160))
            }
        }
    }
    return completeScreenInspectionCommand(
        actionId = "search-current-screen",
        description = "Search current screen elements",
        result = result,
        parameters = mapOf("query" to query, "match_count" to matches.size.toString())
    )
}

internal fun MobileNativeAgent.screenElementTitle(element: ScreenElement): String =
    element.label.ifBlank { element.viewId.ifBlank { element.className.ifBlank { "Unnamed element" } } }

internal fun MobileNativeAgent.completeScreenInspectionCommand(
    actionId: String,
    description: String,
    result: String,
    parameters: Map<String, String>
): AgentUiState {
    val success = currentScreen.isAccessibilityEnabled || currentScreen.visualScene.available
    val status = if (success) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED
    val action = AgentAction(
        id = actionId,
        kind = AgentActionKind.READ_SCREEN,
        target = currentScreen.pageTitle.ifBlank { currentScreen.foregroundApp },
        risk = AgentRisk.LOW,
        status = status,
        description = description,
        parameters = parameters,
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Screen Perception",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "screen-perception",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "screen-perception",
            targetTitle = "Screen Perception",
            status = if (success) AgentConnectorStatus.AVAILABLE else AgentConnectorStatus.NEEDS_SETUP,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.SCREEN_READING, AgentCapability.APP_NAVIGATION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = if (success) AgentPhase.COMPLETED else AgentPhase.FAILED
    lastActionResult = AgentActionResult(action.id, success, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:$status")
    )
    return snapshot()
}

internal fun MobileNativeAgent.showHomeAssistantStatusCommand(): AgentUiState {
    val settings = HomeAssistantSettingsStore.load(appContext)
    val response = HomeAssistantDeviceClient.connectionStatus(appContext)
    val result = buildString {
        append(response.message)
        append("\nEnabled: ").append(settings.enabled)
        append("\nURL configured: ").append(settings.baseUrl.isNotBlank())
        append("\nToken configured: ").append(settings.accessToken.isNotBlank())
        append("\nDefault entity: ").append(settings.defaultEntityId.ifBlank { "none" })
    }
    return completeHomeAssistantQueryCommand(
        actionId = "home-assistant-status",
        description = "Check Home Assistant connection status",
        result = result,
        success = response.success,
        parameters = mapOf("configured" to settings.configured.toString())
    )
}

internal fun MobileNativeAgent.showHomeAssistantEntitiesCommand(): AgentUiState {
    val response = HomeAssistantDeviceClient.listEntities(appContext)
    return completeHomeAssistantEntityResult(
        actionId = "list-home-assistant-entities",
        description = "List Home Assistant entities",
        response = response,
        parameters = mapOf("entity_count" to response.entities.size.toString())
    )
}

internal fun MobileNativeAgent.showHomeAssistantCollectionCommand(collection: String): AgentUiState {
    val response = when (collection) {
        "scenes" -> HomeAssistantDeviceClient.listScenes(appContext)
        "automations" -> HomeAssistantDeviceClient.listAutomations(appContext)
        "scripts" -> HomeAssistantDeviceClient.listScripts(appContext)
        else -> HomeAssistantEntityResult(true, false, "Unknown Home Assistant collection")
    }
    return completeHomeAssistantEntityResult(
        actionId = "list-home-assistant-$collection",
        description = "List Home Assistant $collection",
        response = response,
        parameters = mapOf(
            "collection" to collection,
            "entity_count" to response.entities.size.toString()
        )
    )
}

internal fun MobileNativeAgent.searchHomeAssistantEntitiesCommand(query: String): AgentUiState {
    val response = HomeAssistantDeviceClient.listEntities(appContext, query = query)
    return completeHomeAssistantEntityResult(
        actionId = "search-home-assistant-entities",
        description = "Search Home Assistant entities",
        response = response,
        parameters = mapOf("query" to query, "entity_count" to response.entities.size.toString())
    )
}

internal fun MobileNativeAgent.readHomeAssistantEntityCommand(entityId: String): AgentUiState {
    val response = HomeAssistantDeviceClient.readEntity(appContext, entityId)
    return completeHomeAssistantEntityResult(
        actionId = "read-home-assistant-entity",
        description = "Read Home Assistant entity state",
        response = response,
        parameters = mapOf("entity_id" to entityId)
    )
}

internal fun MobileNativeAgent.completeHomeAssistantEntityResult(
    actionId: String,
    description: String,
    response: HomeAssistantEntityResult,
    parameters: Map<String, String>
): AgentUiState {
    val result = buildString {
        append(response.message)
        response.entities.take(40).forEach { entity ->
            append("\n").append(entity.friendlyName)
            append(" | ").append(entity.entityId)
            append(" | ").append(entity.state)
            if (entity.protected) append(" [protected]")
        }
    }
    return completeHomeAssistantQueryCommand(
        actionId = actionId,
        description = description,
        result = result,
        success = response.success,
        parameters = parameters
    )
}

internal fun MobileNativeAgent.completeHomeAssistantQueryCommand(
    actionId: String,
    description: String,
    result: String,
    success: Boolean,
    parameters: Map<String, String>
): AgentUiState {
    val status = if (success) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED
    val action = AgentAction(
        id = actionId,
        kind = AgentActionKind.READ_SCREEN,
        target = "Home Assistant",
        risk = AgentRisk.LOW,
        status = status,
        description = description,
        parameters = parameters,
        result = result
    )
    val configured = HomeAssistantSettingsStore.load(appContext).configured
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Home Assistant",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "home-assistant",
            kind = AgentRouteKind.DEVICE_CONNECTOR,
            targetId = "home-assistant",
            targetTitle = "Home Assistant",
            status = if (configured) AgentConnectorStatus.AVAILABLE else AgentConnectorStatus.NEEDS_SETUP,
            deliveryMode = "local-rest",
            capabilities = listOf(AgentCapability.SMART_HOME, AgentCapability.DEVICE_CONTROL)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = if (success) AgentPhase.COMPLETED else AgentPhase.FAILED
    lastActionResult = AgentActionResult(action.id, success, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:$status")
    )
    return snapshot()
}

internal fun MobileNativeAgent.showNotificationInboxCommand(): AgentUiState {
    val notifications = currentScreen.notifications
    val result = when {
        !notifications.hasAccess -> "Notification access is disabled"
        notifications.items.isEmpty() -> "No active notifications"
        else -> notificationSummary(notifications.items, "Active notifications")
    }
    return completeNotificationCommand(
        actionId = "show-notification-inbox",
        description = "Show privacy-protected notification inbox",
        result = result,
        parameters = mapOf(
            "has_access" to notifications.hasAccess.toString(),
            "notification_count" to notifications.items.size.toString()
        )
    )
}

internal fun MobileNativeAgent.searchNotificationsCommand(query: String): AgentUiState {
    val notifications = currentScreen.notifications
    val normalizedQuery = query.lowercase(Locale.US)
    val matches = notifications.items.filter { item ->
        item.packageName.lowercase(Locale.US).contains(normalizedQuery) ||
            item.category.lowercase(Locale.US).contains(normalizedQuery) ||
            item.title.lowercase(Locale.US).contains(normalizedQuery) ||
            item.textPreview.lowercase(Locale.US).contains(normalizedQuery)
    }
    val result = when {
        !notifications.hasAccess -> "Notification access is disabled"
        matches.isEmpty() -> "No active notifications match '$query'"
        else -> notificationSummary(matches, "Notification matches")
    }
    return completeNotificationCommand(
        actionId = "search-notifications",
        description = "Search privacy-protected notifications",
        result = result,
        parameters = mapOf("query" to query, "match_count" to matches.size.toString())
    )
}

internal fun MobileNativeAgent.notificationSummary(items: List<AgentNotificationItem>, heading: String): String =
    buildString {
        append(heading).append(": ").append(items.size)
        items.take(12).forEach { item ->
            val appLabel = currentScreen.installedApps
                .firstOrNull { it.packageName == item.packageName }
                ?.label
                ?: item.packageName
            append("\n").append(appLabel).append(" [").append(item.category).append("] ")
            if (item.canReply) append("[reply available] ")
            if (item.sensitiveFlags.isNotEmpty()) {
                append("[sensitive content hidden]")
            } else {
                append(item.title.ifBlank { "Notification" })
                if (item.textPreview.isNotBlank()) append(": ").append(item.textPreview)
            }
        }
    }

internal fun MobileNativeAgent.completeNotificationCommand(
    actionId: String,
    description: String,
    result: String,
    parameters: Map<String, String>
): AgentUiState {
    val success = currentScreen.notifications.hasAccess
    val status = if (success) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED
    val action = AgentAction(
        id = actionId,
        kind = AgentActionKind.READ_SCREEN,
        target = "Notification Inbox",
        risk = AgentRisk.LOW,
        status = status,
        description = description,
        parameters = parameters,
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Notification Context",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "notification-inbox",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "notification-inbox",
            targetTitle = "Notification Context",
            status = if (currentScreen.notifications.hasAccess) {
                AgentConnectorStatus.AVAILABLE
            } else {
                AgentConnectorStatus.NEEDS_SETUP
            },
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.SCREEN_READING)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = if (success) AgentPhase.COMPLETED else AgentPhase.FAILED
    lastActionResult = AgentActionResult(action.id, success, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:$status")
    )
    return snapshot()
}

internal fun MobileNativeAgent.setPermissionModeCommand(mode: PermissionMode): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(permissionMode = mode))
    val modeLabel = appContext.getString(
        when (mode) {
            PermissionMode.OBSERVE_ONLY -> R.string.permission_mode_observe_only
            PermissionMode.SUGGEST_ONLY -> R.string.permission_mode_suggest_only
            PermissionMode.ASK_BEFORE_ACTION -> R.string.permission_mode_ask_before_action
            PermissionMode.AUTO_LOW_RISK -> R.string.permission_mode_auto_low_risk
            PermissionMode.FULL_ACCESS -> R.string.permission_mode_full_access
        }
    )
    val result = appContext.getString(R.string.agent_permission_mode_updated, modeLabel)
    return completeSafetySettingCommand(
        actionId = "set-permission-mode",
        description = "Set Agent permission mode",
        result = result,
        parameters = mapOf("permission_mode" to mode.name)
    )
}

internal fun MobileNativeAgent.setHighRiskGuardCommand(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(highRiskGuard = enabled))
    val result = "Agent high-risk guard ${if (enabled) "enabled" else "disabled"}"
    return completeSafetySettingCommand(
        actionId = "set-high-risk-guard",
        description = "Set Agent high-risk action guard",
        result = result,
        parameters = mapOf("high_risk_guard" to enabled.toString())
    )
}

internal fun MobileNativeAgent.completeSafetySettingCommand(
    actionId: String,
    description: String,
    result: String,
    parameters: Map<String, String>
): AgentUiState {
    val action = AgentAction(
        id = actionId,
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Security",
        risk = AgentRisk.MEDIUM,
        status = AgentActionStatus.COMPLETED,
        description = description,
        parameters = parameters,
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Security",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-security",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-security",
            targetTitle = "Agent Security",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.MEDIUM,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, parameters.entries.joinToString { "${it.key}:${it.value}" })
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    return snapshot()
}

internal fun MobileNativeAgent.showAuditTrailCommand(): AgentUiState {
    val result = if (auditTrail.isEmpty()) {
        "No Agent audit events"
    } else {
        auditTrail.takeLast(8).joinToString(" | ") { entry ->
            "${entry.event.name.lowercase(Locale.US)}:${entry.detail.take(80)}"
        }
    }
    val action = AgentAction(
        id = "show-audit-trail",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Audit Trail",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Show Agent audit trail",
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Audit Trail",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-audit-trail",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-audit-trail",
            targetTitle = "Agent Audit Trail",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.LOW,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudits(
        AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal)),
        AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    )
    return snapshot()
}

internal fun MobileNativeAgent.clearTaskHistoryCommand(): AgentUiState {
    taskStore.clear()
    AgentTranscriptStore(appContext).clear()
    val result = "Cleared Agent task history"
    val action = AgentAction(
        id = "clear-task-history",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Task History",
        risk = AgentRisk.MEDIUM,
        status = AgentActionStatus.COMPLETED,
        description = "Clear Agent task history",
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Task History",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-task-history",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-task-history",
            targetTitle = "Agent Task History",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = AgentRisk.MEDIUM,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "task_history_cleared")
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    return snapshot()
}
