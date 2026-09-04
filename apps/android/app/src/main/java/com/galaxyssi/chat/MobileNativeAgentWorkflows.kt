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

internal fun MobileNativeAgent.saveWorkflowCommand(name: String, workflowGoal: String): AgentUiState {
    val blockReason = sensitiveMemoryReason(workflowGoal, currentScreen)
    val outcome = if (blockReason == null) runCatching { workflowStore.save(name, workflowGoal) } else null
    val saved = outcome?.isSuccess == true
    val result = if (blockReason != null) {
        "Workflow was not saved: $blockReason"
    } else {
        outcome?.fold(
            onSuccess = { workflow -> "Saved workflow ${workflow.name}" },
            onFailure = { error -> error.message ?: "Workflow could not be saved" }
        ) ?: "Workflow could not be saved"
    }
    return completeWorkflowManagementCommand(
        actionId = "save-workflow",
        description = "Save reusable Agent workflow",
        result = result,
        risk = AgentRisk.LOW,
        parameters = mapOf("workflow_name" to name, "saved" to saved.toString())
    )
}

internal fun MobileNativeAgent.showWorkflowsCommand(): AgentUiState {
    val workflows = workflowStore.list()
    val result = if (workflows.isEmpty()) {
        "No saved workflows. Use: save workflow Name :: goal"
    } else {
        buildString {
            append("Saved workflows: ").append(workflows.size)
            workflows.take(20).forEach { workflow ->
                append("\n").append(workflow.name)
                append(" | runs=").append(workflow.runCount)
                append(" | ").append(workflow.goal.replace(Regex("\\s+"), " ").take(120))
            }
        }
    }
    return completeWorkflowManagementCommand(
        actionId = "list-workflows",
        description = "Show saved Agent workflows",
        result = result,
        risk = AgentRisk.LOW,
        parameters = mapOf("workflow_count" to workflows.size.toString())
    )
}

internal fun MobileNativeAgent.showWorkflowHistoryCommand(): AgentUiState {
    val records = workflowExecutionHistoryStore.recent(limit = 20)
    val result = if (records.isEmpty()) {
        "No workflow execution history"
    } else {
        buildString {
            append("Workflow execution history: ").append(records.size)
            records.forEach { record ->
                append("\n").append(record.id)
                append(" | ").append(record.workflowName)
                append(" | ").append(record.source.name.lowercase(Locale.US))
                append(" | ").append(record.status.name.lowercase(Locale.US).replace('_', ' '))
                append(" | started=").append(formatWorkflowExecutionTime(record.startedAtMillis))
                if (record.completedAtMillis > 0L) {
                    append(" | completed=").append(formatWorkflowExecutionTime(record.completedAtMillis))
                }
                if (record.resultSummary.isNotBlank()) {
                    append(" | ").append(record.resultSummary.replace(Regex("\\s+"), " ").take(160))
                }
            }
        }
    }
    return completeWorkflowManagementCommand(
        actionId = "list-workflow-history",
        description = "Show Agent workflow execution history",
        result = result,
        risk = AgentRisk.LOW,
        parameters = mapOf("history_count" to records.size.toString())
    )
}

internal fun MobileNativeAgent.attachWorkflowTriggerConditionCommand(request: WorkflowTriggerConditionRequest): AgentUiState {
    val trigger = workflowTriggerStore.findById(request.triggerId)
        ?: return completeWorkflowManagementCommand(
            actionId = "attach-workflow-trigger-condition-missing",
            description = "Find workflow trigger for condition",
            result = "Workflow trigger '${request.triggerId}' was not found",
            risk = AgentRisk.LOW,
            parameters = mapOf("trigger_id" to request.triggerId)
        )
    val conditions = (trigger.conditions + request.condition).distinct()
    val outcome = runCatching { workflowTriggerStore.upsert(trigger.copy(conditions = conditions)) }
    val attached = outcome.isSuccess
    val result = if (attached) {
        "Attached condition to trigger ${trigger.id}: ${workflowConditionLabel(request.condition)}"
    } else {
        outcome.exceptionOrNull()?.message ?: "Workflow trigger condition could not be attached"
    }
    return completeWorkflowManagementCommand(
        actionId = "attach-workflow-trigger-condition",
        description = "Attach condition to encrypted Agent workflow trigger",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf(
            "trigger_id" to trigger.id,
            "condition_count" to conditions.size.toString(),
            "attached" to attached.toString()
        )
    )
}

internal fun MobileNativeAgent.clearWorkflowTriggerConditionsCommand(triggerId: String): AgentUiState {
    val trigger = workflowTriggerStore.findById(triggerId)
        ?: return completeWorkflowManagementCommand(
            actionId = "clear-workflow-trigger-conditions-missing",
            description = "Find workflow trigger for condition cleanup",
            result = "Workflow trigger '$triggerId' was not found",
            risk = AgentRisk.LOW,
            parameters = mapOf("trigger_id" to triggerId)
        )
    val clearedCount = trigger.conditions.size
    val outcome = runCatching { workflowTriggerStore.upsert(trigger.copy(conditions = emptyList())) }
    val cleared = outcome.isSuccess
    val result = if (cleared) {
        "Cleared $clearedCount conditions from trigger ${trigger.id}"
    } else {
        outcome.exceptionOrNull()?.message ?: "Workflow trigger conditions could not be cleared"
    }
    return completeWorkflowManagementCommand(
        actionId = "clear-workflow-trigger-conditions",
        description = "Clear encrypted Agent workflow trigger conditions",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf(
            "trigger_id" to trigger.id,
            "cleared_count" to clearedCount.toString(),
            "cleared" to cleared.toString()
        )
    )
}

internal fun MobileNativeAgent.createWorkflowTriggerCommand(request: WorkflowTriggerRequest): AgentUiState {
    val workflow = workflowStore.find(request.workflowName) ?: return completeWorkflowManagementCommand(
        actionId = "create-workflow-trigger-missing",
        description = "Find workflow for event trigger",
        result = "Workflow '${request.workflowName}' was not found",
        risk = AgentRisk.LOW,
        parameters = mapOf("workflow_name" to request.workflowName)
    )
    val trigger = AgentWorkflowTrigger(
        workflowId = workflow.id,
        workflowName = workflow.name,
        kind = request.kind,
        condition = request.condition.take(240)
    )
    val outcome = runCatching { workflowTriggerStore.upsert(trigger) }
    val created = outcome.isSuccess
    val result = if (created) {
        "Created trigger ${trigger.id} for ${workflow.name}: ${workflowTriggerLabel(trigger)}"
    } else {
        outcome.exceptionOrNull()?.message ?: "Workflow trigger could not be created"
    }
    return completeWorkflowManagementCommand(
        actionId = "create-workflow-trigger",
        description = "Create encrypted Agent workflow event trigger",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf(
            "workflow_name" to workflow.name,
            "trigger_id" to trigger.id,
            "trigger_kind" to trigger.kind.name,
            "created" to created.toString()
        )
    )
}

internal fun MobileNativeAgent.showWorkflowTriggersCommand(): AgentUiState {
    val triggers = workflowTriggerStore.list()
    val result = if (triggers.isEmpty()) {
        "No workflow triggers"
    } else {
        buildString {
            append("Workflow triggers: ").append(triggers.size)
            triggers.take(20).forEach { trigger ->
                append("\n").append(trigger.id)
                append(" | ").append(trigger.workflowName)
                append(" | ").append(workflowTriggerLabel(trigger))
                if (trigger.conditions.isNotEmpty()) {
                    append(" | if ").append(trigger.conditions.joinToString(" and ", transform = ::workflowConditionLabel))
                }
                append(" | ").append(if (trigger.enabled) "enabled" else "disabled")
            }
        }
    }
    return completeWorkflowManagementCommand(
        actionId = "list-workflow-triggers",
        description = "Show encrypted Agent workflow event triggers",
        result = result,
        risk = AgentRisk.LOW,
        parameters = mapOf("trigger_count" to triggers.size.toString())
    )
}

internal fun MobileNativeAgent.deleteWorkflowTriggerCommand(triggerId: String): AgentUiState {
    val trigger = workflowTriggerStore.findById(triggerId)
    val deleted = if (trigger == null) 0 else workflowTriggerStore.delete(trigger.id)
    val result = if (trigger != null && deleted > 0) {
        "Deleted trigger ${trigger.id} for ${trigger.workflowName}"
    } else {
        "Workflow trigger '$triggerId' was not found"
    }
    return completeWorkflowManagementCommand(
        actionId = "delete-workflow-trigger",
        description = "Delete encrypted Agent workflow event trigger",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf("trigger_id" to triggerId, "deleted_count" to deleted.toString())
    )
}

internal fun MobileNativeAgent.workflowTriggerLabel(trigger: AgentWorkflowTrigger): String = when (trigger.kind) {
    AgentWorkflowTriggerKind.NOTIFICATION_PACKAGE -> "notification package contains '${trigger.condition}'"
    AgentWorkflowTriggerKind.NOTIFICATION_TEXT -> "notification text contains '${trigger.condition}'"
    AgentWorkflowTriggerKind.POWER_CONNECTED -> "charging"
    AgentWorkflowTriggerKind.BATTERY_LOW -> "battery low"
}

internal fun MobileNativeAgent.workflowConditionLabel(condition: AgentWorkflowCondition): String = when (condition) {
    is AgentWorkflowCondition.DeviceCharging -> if (condition.required) "charging" else "not charging"
    is AgentWorkflowCondition.BatteryThreshold -> {
        val comparison = when (condition.comparison) {
            AgentWorkflowBatteryComparison.BELOW -> "below"
            AgentWorkflowBatteryComparison.AT_MOST -> "at most"
            AgentWorkflowBatteryComparison.AT_LEAST -> "at least"
            AgentWorkflowBatteryComparison.ABOVE -> "above"
        }
        "battery $comparison ${condition.percent}%"
    }
    is AgentWorkflowCondition.NetworkAvailable -> if (condition.required) "network available" else "network unavailable"
    is AgentWorkflowCondition.TimeWindow -> "time %02d:%02d-%02d:%02d".format(
        Locale.US,
        condition.startMinuteOfDay / 60,
        condition.startMinuteOfDay % 60,
        condition.endMinuteOfDay / 60,
        condition.endMinuteOfDay % 60
    )
    is AgentWorkflowCondition.Text -> "text contains '${condition.expected}'"
    is AgentWorkflowCondition.PackageName -> "package matches '${condition.expected}'"
}

internal fun MobileNativeAgent.deleteWorkflowCommand(name: String): AgentUiState {
    val workflow = workflowStore.find(name)
    workflowScheduleStore.findByWorkflowName(name)?.let { schedule ->
        AgentWorkflowScheduler.cancel(appContext, schedule)
    }
    val deleted = workflowStore.delete(name)
    val deletedTriggers = if (deleted > 0 && workflow != null) {
        workflowTriggerStore.deleteForWorkflow(workflow.id)
    } else {
        0
    }
    val deletedHistory = if (deleted > 0 && workflow != null) {
        workflowExecutionHistoryStore.deleteForWorkflow(workflow.id)
    } else {
        0
    }
    val result = if (deleted > 0) {
        "Deleted workflow ${workflow?.name ?: name}; removed triggers=$deletedTriggers; removed history=$deletedHistory"
    } else {
        "Workflow '$name' was not found"
    }
    return completeWorkflowManagementCommand(
        actionId = "delete-workflow",
        description = "Delete saved Agent workflow",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf(
            "workflow_name" to name,
            "deleted_count" to deleted.toString(),
            "deleted_trigger_count" to deletedTriggers.toString(),
            "deleted_history_count" to deletedHistory.toString()
        )
    )
}

internal fun MobileNativeAgent.runWorkflowCommand(name: String): AgentUiState {
    val workflow = workflowStore.find(name) ?: return completeWorkflowManagementCommand(
        actionId = "run-workflow-missing",
        description = "Find saved Agent workflow",
        result = "Workflow '$name' was not found",
        risk = AgentRisk.LOW,
        parameters = mapOf("workflow_name" to name)
    )
    workflowStore.markRun(workflow.id)
    val execution = AgentWorkflowExecutionRecord(
        workflowId = workflow.id,
        workflowName = workflow.name,
        source = AgentWorkflowExecutionSource.MANUAL,
        status = AgentWorkflowExecutionStatus.RUNNING
    )
    workflowExecutionHistoryStore.upsert(execution)
    activeWorkflowExecutionId = execution.id
    recordAudit(AgentAuditEvent.WORKFLOW_RUN, "workflow_id=${workflow.id}; name_hash=${workflow.name.hashCode()}")
    return submitGoal(workflow.goal)
}

internal fun MobileNativeAgent.scheduleWorkflowCommand(request: WorkflowScheduleRequest): AgentUiState {
    val workflow = workflowStore.find(request.workflowName) ?: return completeWorkflowManagementCommand(
        actionId = "schedule-workflow-missing",
        description = "Find workflow for scheduling",
        result = "Workflow '${request.workflowName}' was not found",
        risk = AgentRisk.LOW,
        parameters = mapOf("workflow_name" to request.workflowName)
    )
    val outcome = runCatching {
        when (request.kind) {
            AgentWorkflowScheduleKind.DAILY -> AgentWorkflowScheduler.scheduleDaily(
                appContext,
                workflow,
                request.hour,
                request.minute
            )
            AgentWorkflowScheduleKind.INTERVAL -> AgentWorkflowScheduler.scheduleInterval(
                appContext,
                workflow,
                request.intervalMinutes
            )
        }
    }
    val schedule = outcome.getOrNull()
    val result = schedule?.let {
        "Scheduled ${workflow.name}: ${workflowScheduleLabel(it)}; next=${formatScheduleTime(it.nextRunAtMillis)}"
    } ?: (outcome.exceptionOrNull()?.message ?: "Workflow could not be scheduled")
    return completeWorkflowManagementCommand(
        actionId = "schedule-workflow",
        description = "Schedule reusable Agent workflow",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf(
            "workflow_name" to workflow.name,
            "schedule_kind" to request.kind.name,
            "scheduled" to (schedule != null).toString()
        )
    )
}

internal fun MobileNativeAgent.showWorkflowSchedulesCommand(): AgentUiState {
    val schedules = workflowScheduleStore.list()
    val result = if (schedules.isEmpty()) {
        "No workflow schedules"
    } else {
        buildString {
            append("Workflow schedules: ").append(schedules.size)
            schedules.take(20).forEach { schedule ->
                append("\n").append(schedule.workflowName)
                append(" | ").append(workflowScheduleLabel(schedule))
                append(" | next=").append(formatScheduleTime(schedule.nextRunAtMillis))
            }
        }
    }
    return completeWorkflowManagementCommand(
        actionId = "list-workflow-schedules",
        description = "Show Agent workflow schedules",
        result = result,
        risk = AgentRisk.LOW,
        parameters = mapOf("schedule_count" to schedules.size.toString())
    )
}

internal fun MobileNativeAgent.cancelWorkflowScheduleCommand(name: String): AgentUiState {
    val schedule = workflowScheduleStore.findByWorkflowName(name)
    val result = if (schedule == null) {
        "Schedule '$name' was not found"
    } else {
        AgentWorkflowScheduler.cancel(appContext, schedule)
        "Cancelled schedule for ${schedule.workflowName}"
    }
    return completeWorkflowManagementCommand(
        actionId = "cancel-workflow-schedule",
        description = "Cancel Agent workflow schedule",
        result = result,
        risk = AgentRisk.MEDIUM,
        parameters = mapOf("workflow_name" to name, "cancelled" to (schedule != null).toString())
    )
}

internal fun MobileNativeAgent.workflowScheduleLabel(schedule: AgentWorkflowSchedule): String = when (schedule.kind) {
    AgentWorkflowScheduleKind.DAILY -> "daily at %02d:%02d".format(Locale.US, schedule.hour, schedule.minute)
    AgentWorkflowScheduleKind.INTERVAL -> "every ${schedule.intervalMinutes} minutes"
}

internal fun MobileNativeAgent.formatScheduleTime(timestampMillis: Long): String =
    if (timestampMillis <= 0L) "pending" else SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date(timestampMillis))

internal fun MobileNativeAgent.formatWorkflowExecutionTime(timestampMillis: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(timestampMillis))

internal fun MobileNativeAgent.syncActiveWorkflowExecution() {
    val executionId = activeWorkflowExecutionId ?: return
    val record = workflowExecutionHistoryStore.findById(executionId) ?: run {
        activeWorkflowExecutionId = null
        return
    }
    val status = when (phase) {
        AgentPhase.WAITING_CONFIRMATION -> AgentWorkflowExecutionStatus.WAITING_CONFIRMATION
        AgentPhase.WAITING_RESPONSE -> AgentWorkflowExecutionStatus.WAITING_RESPONSE
        AgentPhase.COMPLETED -> AgentWorkflowExecutionStatus.COMPLETED
        AgentPhase.FAILED -> AgentWorkflowExecutionStatus.FAILED
        AgentPhase.CANCELLED -> AgentWorkflowExecutionStatus.CANCELLED
        AgentPhase.BLOCKED -> AgentWorkflowExecutionStatus.BLOCKED
        AgentPhase.OBSERVING,
        AgentPhase.PLANNING,
        AgentPhase.EXECUTING,
        AgentPhase.VERIFYING,
        AgentPhase.PAUSED -> AgentWorkflowExecutionStatus.RUNNING
    }
    val terminal = status == AgentWorkflowExecutionStatus.COMPLETED ||
        status == AgentWorkflowExecutionStatus.FAILED ||
        status == AgentWorkflowExecutionStatus.CANCELLED ||
        status == AgentWorkflowExecutionStatus.BLOCKED
    val summary = lastActionResult?.message.orEmpty().trim().take(2_000)
    val completedAtMillis = when {
        !terminal -> 0L
        record.completedAtMillis > 0L -> record.completedAtMillis
        else -> System.currentTimeMillis()
    }
    if (record.status != status ||
        record.completedAtMillis != completedAtMillis ||
        record.resultSummary != summary
    ) {
        workflowExecutionHistoryStore.upsert(
            record.copy(
                status = status,
                completedAtMillis = completedAtMillis,
                resultSummary = summary
            )
        )
    }
    if (terminal) {
        activeWorkflowExecutionId = null
        persistSession()
    }
}

internal fun MobileNativeAgent.showTemplatesCommand(): AgentUiState {
    val templates = AgentWorkflowTemplates.all
    val result = buildString {
        append("Workflow templates: ").append(templates.size)
        templates.forEach { template ->
            append("\n").append(template.name).append(" | ").append(template.goal)
        }
    }
    return completeWorkflowManagementCommand(
        actionId = "list-workflow-templates",
        description = "Show built-in Agent workflow templates",
        result = result,
        risk = AgentRisk.LOW,
        parameters = mapOf("template_count" to templates.size.toString())
    )
}

internal fun MobileNativeAgent.runTemplateCommand(name: String): AgentUiState {
    val template = AgentWorkflowTemplates.find(name) ?: return completeWorkflowManagementCommand(
        actionId = "run-template-missing",
        description = "Find Agent workflow template",
        result = "Template '$name' was not found",
        risk = AgentRisk.LOW,
        parameters = mapOf("template_name" to name)
    )
    recordAudit(AgentAuditEvent.WORKFLOW_RUN, "template_id=${template.id}")
    return submitGoal(template.goal)
}

internal fun MobileNativeAgent.completeWorkflowManagementCommand(
    actionId: String,
    description: String,
    result: String,
    risk: AgentRisk,
    parameters: Map<String, String>
): AgentUiState {
    val action = AgentAction(
        id = actionId,
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Workflows",
        risk = risk,
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
        selectedAgentOrModel = "Agent Workflows",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-workflows",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-workflows",
            targetTitle = "Agent Workflows",
            status = AgentConnectorStatus.AVAILABLE,
            deliveryMode = "local",
            capabilities = listOf(AgentCapability.TASK_EXECUTION)
        ),
        safetyReview = AgentSafetyReview(
            risk = risk,
            requiresConfirmation = false,
            mode = safetyPolicy.permissionMode()
        )
    )
    phase = AgentPhase.COMPLETED
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.WORKFLOW_UPDATED, "action=$actionId; ${parameters.entries.joinToString { "${it.key}:${it.value}" }}")
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    return snapshot()
}

internal fun MobileNativeAgent.callableInventorySummary(
    filter: CallableInventoryFilter,
    targets: List<AgentCallableTarget>,
    tools: List<AgentSystemTool>
): String {
    val targetLines = targets
        .filter { target ->
            when (filter) {
                CallableInventoryFilter.AGENTS -> target.kind == AgentConnectorKind.AGENT
                CallableInventoryFilter.MODELS -> target.kind == AgentConnectorKind.MODEL
                CallableInventoryFilter.DEVICES -> target.kind == AgentConnectorKind.DEVICE
                CallableInventoryFilter.TOOLS -> false
                CallableInventoryFilter.ALL -> true
            }
        }
        .joinToString(" | ") { target ->
            "${target.title}:${target.kind.name.lowercase(Locale.US)}:${target.status.name.lowercase(Locale.US)}"
        }
    val toolLines = if (filter == CallableInventoryFilter.TOOLS || filter == CallableInventoryFilter.ALL) {
        tools.joinToString(" | ") { tool ->
            "${tool.title}:${tool.kind.name.lowercase(Locale.US)}:${tool.risk.name.lowercase(Locale.US)}"
        }
    } else {
        ""
    }
    return listOf(targetLines, toolLines)
        .filter { it.isNotBlank() }
        .joinToString(" | ")
        .ifBlank { "No callable inventory for ${filter.name.lowercase(Locale.US)}" }
}

internal fun MobileNativeAgent.callableInventorySearchSummary(
    query: String,
    targets: List<AgentCallableTarget>,
    tools: List<AgentSystemTool>
): String {
    val cleanQuery = query.trim().lowercase(Locale.US)
    if (cleanQuery.isBlank()) return "No callable inventory query"
    val targetMatches = targets
        .filter { target -> callableTargetSearchText(target).contains(cleanQuery) }
        .take(6)
        .joinToString(" | ") { target ->
            "${target.title}:${target.kind.name.lowercase(Locale.US)}:${target.status.name.lowercase(Locale.US)}"
        }
    val toolMatches = tools
        .filter { tool -> systemToolSearchText(tool).contains(cleanQuery) }
        .take(8)
        .joinToString(" | ") { tool ->
            "${tool.title}:${tool.kind.name.lowercase(Locale.US)}:${tool.risk.name.lowercase(Locale.US)}"
        }
    return listOf(targetMatches, toolMatches)
        .filter { it.isNotBlank() }
        .joinToString(" | ")
        .ifBlank { "No callable inventory hits for \"$query\"" }
}

internal fun MobileNativeAgent.callableTargetSearchText(target: AgentCallableTarget): String =
    listOf(
        target.id,
        target.title,
        target.kind.name,
        target.status.name,
        target.capabilities.joinToString(" ") { it.name }
    ).joinToString(" ").lowercase(Locale.US)

internal fun MobileNativeAgent.systemToolSearchText(tool: AgentSystemTool): String =
    listOf(
        tool.id,
        tool.title,
        tool.kind.name,
        tool.risk.name,
        tool.capabilities.joinToString(" ") { it.name },
        tool.examples.joinToString(" ")
    ).joinToString(" ").lowercase(Locale.US)

internal fun MobileNativeAgent.setMemoryCaptureCommand(enabled: Boolean): AgentUiState {
    safetySettingsStore.save(safetySettingsStore.load().copy(memoryCapture = enabled))
    val result = if (enabled) "Memory capture resumed" else "Private mode enabled; memory capture paused"
    val action = AgentAction(
        id = "set-memory-capture",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Privacy",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = if (enabled) "Resume memory capture" else "Pause memory capture",
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Privacy",
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = "agent-privacy",
            kind = AgentRouteKind.LOCAL_SYSTEM,
            targetId = "agent-privacy",
            targetTitle = "Agent Privacy",
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
    recordAudit(AgentAuditEvent.SETTINGS_UPDATED, "memory_capture:$enabled")
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    saveTaskRecord(result = result)
    return snapshot()
}

internal fun MobileNativeAgent.showMemoryOverviewCommand(): AgentUiState {
    val recent = memoryStore.recent(limit = 10)
    val memorySnapshot = memoryStore.snapshot()
    val count = memorySnapshot.activeCount
    val captureEnabled = safetySettingsStore.load().memoryCapture
    val result = buildString {
        append("Personal memory: ").append(count)
        append("; conflicts=").append(memorySnapshot.conflicts.size)
        append("; capture=").append(if (captureEnabled) "on" else "paused")
        if (recent.isEmpty()) {
            append("\nNo saved memories")
        } else {
            recent.forEach { item ->
                append("\n").append(item.kind.name.lowercase(Locale.US))
                append(": ").append(item.value.replace(Regex("\\s+"), " ").take(120))
            }
        }
    }
    return completePersonalDataOverviewCommand(
        actionId = "show-memory-overview",
        target = "Agent Memory",
        description = "Show personal memory status and recent items",
        result = result,
        parameters = mapOf(
            "memory_count" to count.toString(),
            "memory_conflicts" to memorySnapshot.conflicts.size.toString(),
            "capture_enabled" to captureEnabled.toString()
        )
    )
}

internal fun MobileNativeAgent.showKnowledgeOverviewCommand(): AgentUiState {
    val stats = knowledgeStore.stats()
    val recent = knowledgeStore.search(query = "", limit = 10)
    val result = buildString {
        append("Knowledge base: ").append(stats.itemCount)
        append(" items; sources=").append(stats.sourceCount)
        if (recent.isEmpty()) {
            append("\nNo knowledge items")
        } else {
            recent.forEach { item ->
                append("\n").append(item.kind.name.lowercase(Locale.US))
                append(": ").append(item.title.replace(Regex("\\s+"), " ").take(100))
                if (item.source.isNotBlank()) append(" [").append(item.source.take(48)).append("]")
            }
        }
    }
    return completePersonalDataOverviewCommand(
        actionId = "show-knowledge-overview",
        target = "Agent Knowledge",
        description = "Show knowledge base status and recent items",
        result = result,
        parameters = mapOf(
            "item_count" to stats.itemCount.toString(),
            "source_count" to stats.sourceCount.toString()
        )
    )
}

internal fun MobileNativeAgent.completePersonalDataOverviewCommand(
    actionId: String,
    target: String,
    description: String,
    result: String,
    parameters: Map<String, String>
): AgentUiState {
    val action = AgentAction(
        id = actionId,
        kind = AgentActionKind.DRAFT_PLAN,
        target = target,
        risk = AgentRisk.LOW,
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
        selectedAgentOrModel = target,
        confirmationRequired = false,
        expectedResult = result,
        route = AgentRoute(
            routeId = actionId,
            kind = AgentRouteKind.KNOWLEDGE,
            targetId = actionId,
            targetTitle = target,
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
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    return snapshot()
}

internal fun MobileNativeAgent.searchKnowledgeCommand(query: String): AgentUiState {
    val rankedHits = knowledgeStore.searchRanked(query, limit = 8)
    val hits = rankedHits.map { it.item }
    val result = knowledgeHitsSummary(query, hits)
    val action = AgentAction(
        id = "search-knowledge",
        kind = AgentActionKind.DRAFT_PLAN,
        target = "Agent Knowledge",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = "Search Agent knowledge",
        parameters = mapOf("query" to query),
        result = result
    )
    currentPlan = AgentPlan(
        goal = currentGoal,
        screen = currentScreen,
        steps = completedSteps(),
        actions = listOf(action),
        selectedAgentOrModel = "Agent Knowledge",
        confirmationRequired = false,
        expectedResult = "Returned local knowledge search hits",
        route = AgentRoute(
            routeId = "agent-knowledge",
            kind = AgentRouteKind.KNOWLEDGE,
            targetId = "agent-knowledge",
            targetTitle = "Agent Knowledge",
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
    lastActionResult = AgentActionResult(action.id, true, result)
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(AgentAuditEvent.ACTION_EXECUTED, "action:${action.kind}:${AgentActionStatus.COMPLETED}")
    saveTaskRecord(result = result)
    return snapshot()
}

internal fun MobileNativeAgent.prepareKnowledgeAnswerCommand(query: String): AgentUiState {
    val targets = connectorRegistry.availableTargets()
    val hasPairedDesktop = GalaxySSILinkProtocol.allServerLinks(appContext).any { it.paired }
    val preferredTargets = if (hasPairedDesktop) {
        listOf("codex", "hermes", "local-llm", "cloud-models")
    } else {
        listOf("cloud-models", "local-llm")
    }
    val target = preferredTargets
        .firstNotNullOfOrNull { preferredId ->
            targets.firstOrNull { target ->
                target.status == AgentConnectorStatus.AVAILABLE &&
                    (target.id == preferredId || target.id.endsWith(":$preferredId"))
            }
        }
    if (target == null) {
        val localHits = knowledgeStore.search(query, limit = 6)
        return completePersonalDataOverviewCommand(
            actionId = "knowledge-answer-unavailable",
            target = "Agent Knowledge",
            description = "Prepare knowledge evidence without an available model",
            result = "No Codex, Hermes, local model, or cloud model is available.\n${knowledgeHitsSummary(query, localHits)}",
            parameters = mapOf("query" to query, "source_count" to localHits.size.toString())
        )
    }
    val rag = AgentKnowledgeRetriever.retrieve(knowledgeStore, query, target.id, limit = 8)
    if (rag.citations.isEmpty()) {
        if (rag.blockedMatchCount > 0) {
            return completePersonalDataOverviewCommand(
                actionId = "knowledge-access-blocked",
                target = "Agent Knowledge",
                description = "Apply knowledge source access policy",
                result = "Matching knowledge exists, but its access policy does not allow ${target.title} to read it.",
                parameters = mapOf(
                    "query" to query,
                    "target_id" to target.id,
                    "blocked_matches" to rag.blockedMatchCount.toString()
                )
            )
        }
        return searchKnowledgeCommand(query)
    }
    val hits = knowledgeStore.findByIds(rag.citations.map { it.itemId }.toSet())
    val externalCloud = target.id == "cloud-models" || target.id.startsWith("cloud-model:")
    val action = AgentAction(
        id = "knowledge-answer",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = target.title,
        risk = if (externalCloud) AgentRisk.HIGH else AgentRisk.MEDIUM,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = if (externalCloud) {
            "Send selected knowledge excerpts to the configured cloud model and answer with citations"
        } else {
            "Answer from selected local knowledge with citations"
        },
        parameters = mapOf(
            "connector_id" to target.id,
            "_galaxyssi_desktop_executor_full" to
                (target.desktopAccessProfile == GalaxySSILinkProtocol.ACCESS_DESKTOP_EXECUTOR).toString(),
            "knowledge_query" to query,
            "knowledge_item_ids" to rag.citations.joinToString(",") { it.itemId },
            "knowledge_source_count" to rag.sourceCount.toString(),
            "knowledge_blocked_match_count" to rag.blockedMatchCount.toString(),
            "knowledge_evidence_modes" to rag.citations.joinToString(",") { it.evidenceMode.name },
            "shares_knowledge_externally" to externalCloud.toString()
        )
    )
    val context = buildRuntimeContext(
        goal = currentGoal,
        screen = currentScreen,
        targets = targets,
        memories = emptyList(),
        knowledgeItems = hits,
        knowledgeStats = knowledgeStore.stats()
    )
    val request = AgentRequest(
        goal = currentGoal,
        screen = currentScreen,
        targets = targets,
        memories = emptyList(),
        runtimeContext = context
    )
    val plan = AgentPlanFactory.singleAction(request, action)
    val review = safetyPolicy.review(plan, sessionId)
    currentPlan = plan.withSafetyReview(review)
    phase = if (review.blocked) AgentPhase.BLOCKED else AgentPhase.WAITING_CONFIRMATION
    lastActionResult = null
    recordAudit(AgentAuditEvent.GOAL_RECEIVED, goalAuditDetail(currentGoal))
    recordAudit(
        AgentAuditEvent.INVOCATION_AUDIT,
        "knowledge_answer_prepared; target=${target.id}; sources=${rag.sourceCount}; blocked=${rag.blockedMatchCount}; external_cloud=$externalCloud"
    )
    recordAudit(
        AgentAuditEvent.KNOWLEDGE_ACCESSED,
        "prepared; target=${target.id}; citations=${rag.citations.size}; modes=${rag.citations.map { it.evidenceMode }.distinct()}"
    )
    if (review.blocked) recordAudit(AgentAuditEvent.ACTION_BLOCKED, review.reason.ifBlank { "blocked" })
    saveTaskRecord()
    return snapshot()
}
