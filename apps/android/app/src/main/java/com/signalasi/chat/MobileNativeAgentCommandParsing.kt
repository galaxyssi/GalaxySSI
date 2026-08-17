package com.signalasi.chat

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
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunRequest
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
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

internal fun MobileNativeAgent.memoryCommandValue(goal: String): String? {
    val prefixes = listOf(
        "remember ",
        "save note ",
        "save memory ",
        "memorize ",
        "\u8bb0\u4f4f",
        "\u4fdd\u5b58\u8bb0\u5fc6",
        "\u4fdd\u5b58\u7b14\u8bb0"
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.callableInventoryCommand(goal: String): CallableInventoryFilter? {
    val normalized = goal.trim().lowercase(Locale.US)
    return when (normalized) {
        "list tools",
        "show tools",
        "available tools",
        "list system tools",
        "show system tools" -> CallableInventoryFilter.TOOLS
        "list agents",
        "show agents",
        "available agents" -> CallableInventoryFilter.AGENTS
        "list models",
        "show models",
        "available models" -> CallableInventoryFilter.MODELS
        "list devices",
        "show devices",
        "available devices" -> CallableInventoryFilter.DEVICES
        "list capabilities",
        "show capabilities",
        "list callable targets",
        "show callable targets",
        "what can you do" -> CallableInventoryFilter.ALL
        else -> null
    }
}

internal fun MobileNativeAgent.callableSearchCommandValue(goal: String): String? {
    val prefixes = listOf(
        "search tools ",
        "find tools ",
        "search tool ",
        "find tool ",
        "search capabilities ",
        "find capabilities ",
        "search capability ",
        "find capability ",
        "search agents ",
        "find agents ",
        "search models ",
        "find models "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.securityStatusCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "security status" ||
        normalized == "permission status" ||
        normalized == "agent security status" ||
        normalized == "agent permission status" ||
        normalized == "safety status" ||
        normalized == "privacy status"
}

internal fun MobileNativeAgent.permissionChecklistCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "permission checklist" ||
        normalized == "show permission checklist" ||
        normalized == "check permissions" ||
        normalized == "agent permissions" ||
        normalized == "show agent permissions" ||
        normalized == "missing permissions"
}

internal fun MobileNativeAgent.approveTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "approve" ||
        normalized == "confirm" ||
        normalized == "approve next" ||
        normalized == "confirm next" ||
        normalized == "run next" ||
        normalized == "execute next"
}

internal fun MobileNativeAgent.retryTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "retry" ||
        normalized == "retry task" ||
        normalized == "retry action" ||
        normalized == "retry failed action" ||
        normalized == "try again"
}

internal fun MobileNativeAgent.pauseTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "pause" || normalized == "pause task" || normalized == "pause execution"
}

internal fun MobileNativeAgent.resumeTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "resume" ||
        normalized == "resume task" ||
        normalized == "resume execution" ||
        normalized == "continue" ||
        normalized == "continue task" ||
        normalized == "continue execution" ||
        normalized == "继续" ||
        normalized == "继续任务" ||
        normalized == "继续执行"
}

internal fun MobileNativeAgent.replanTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "replan" ||
        normalized == "replan task" ||
        normalized == "update plan" ||
        normalized == "plan again"
}

internal fun MobileNativeAgent.rollbackTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "rollback" ||
        normalized == "rollback task" ||
        normalized == "undo last action" ||
        normalized == "restore checkpoint"
}

internal fun MobileNativeAgent.cancelTaskCommand(goal: String): Boolean {
    val normalized = goal.lowercase(Locale.US)
    return normalized == "cancel" ||
        normalized == "cancel task" ||
        normalized == "stop task" ||
        normalized == "abort task"
}

internal fun MobileNativeAgent.notificationInboxCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "notifications" ||
        normalized == "read notifications" ||
        normalized == "list notifications" ||
        normalized == "show notifications" ||
        normalized == "notification inbox" ||
        normalized == "show notification inbox"
}

internal fun MobileNativeAgent.homeAssistantStatusCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "home assistant status" ||
        normalized == "check home assistant" ||
        normalized == "test home assistant" ||
        normalized == "test home assistant connection"
}

internal fun MobileNativeAgent.homeAssistantEntitiesCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "home assistant entities" ||
        normalized == "list home assistant entities" ||
        normalized == "show home assistant entities" ||
        normalized == "list smart devices" ||
        normalized == "show smart devices"
}

internal fun MobileNativeAgent.homeAssistantCollectionCommand(goal: String): String? {
    val normalized = goal.trim().lowercase(Locale.US)
    return when (normalized) {
        "home assistant scenes", "list home assistant scenes", "show home assistant scenes",
        "list scenes", "show scenes" -> "scenes"
        "home assistant automations", "list home assistant automations", "show home assistant automations",
        "list automations", "show automations" -> "automations"
        "home assistant scripts", "list home assistant scripts", "show home assistant scripts",
        "list scripts", "show scripts" -> "scripts"
        else -> null
    }
}

internal fun MobileNativeAgent.homeAssistantEntitySearchCommandValue(goal: String): String? {
    val prefixes = listOf(
        "search home assistant entities ",
        "find home assistant entity ",
        "search smart devices ",
        "find smart device "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.homeAssistantEntityReadCommandValue(goal: String): String? {
    val prefixes = listOf(
        "read home assistant entity ",
        "get home assistant entity ",
        "read sensor ",
        "get sensor "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.screenOverviewCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "screen status" ||
        normalized == "inspect screen" ||
        normalized == "screen elements" ||
        normalized == "show screen elements" ||
        normalized == "screen structure" ||
        normalized == "show screen structure"
}

internal fun MobileNativeAgent.screenSearchCommandValue(goal: String): String? {
    val prefixes = listOf(
        "search screen elements ",
        "find screen element ",
        "search screen ",
        "find on screen "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.notificationSearchCommandValue(goal: String): String? {
    val prefixes = listOf(
        "search notifications ",
        "find notifications ",
        "search notification ",
        "find notification "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal object AgentLocalControlCommandPolicy {
    fun permissionMode(goal: String): PermissionMode? {
        val normalized = goal.trim().lowercase(Locale.US)
        when (normalized.replace(" ", "")) {
            "\u8bbe\u7f6e\u5b8c\u5168\u8bbf\u95ee",
            "\u8bbe\u7f6e\u5b8c\u5168\u8bbf\u95ee\u6743\u9650",
            "\u8bbe\u7f6e\u5b8c\u5168\u8bbf\u95ee\u7684\u6743\u9650",
            "\u5f00\u542f\u5b8c\u5168\u8bbf\u95ee",
            "\u542f\u7528\u5b8c\u5168\u8bbf\u95ee",
            "\u6743\u9650\u6a21\u5f0f\u5b8c\u5168\u8bbf\u95ee" -> return PermissionMode.FULL_ACCESS
        }
        val value = listOf(
            "set permission mode ",
            "permission mode ",
            "set agent mode ",
            "agent mode "
        ).firstOrNull { normalized.startsWith(it) }
            ?.let { normalized.removePrefix(it).trim() }
            ?: return null
        return when (value.replace('-', ' ').replace('_', ' ')) {
            "observe", "observe only", "read only" -> PermissionMode.OBSERVE_ONLY
            "suggest", "suggest only", "assist", "assisted" -> PermissionMode.SUGGEST_ONLY
            "confirm", "ask", "ask first", "ask before action" -> PermissionMode.ASK_BEFORE_ACTION
            "auto", "automatic", "auto low risk", "low risk auto" -> PermissionMode.AUTO_LOW_RISK
            "full", "full access", "unrestricted", "no confirmation" -> PermissionMode.FULL_ACCESS
            else -> null
        }
    }

    fun highRiskGuard(goal: String): Boolean? {
        val normalized = goal.trim().lowercase(Locale.US)
        when (normalized.replace(" ", "")) {
            "\u5173\u95ed\u9ad8\u98ce\u9669\u4fdd\u62a4" -> return false
            "\u5f00\u542f\u9ad8\u98ce\u9669\u4fdd\u62a4",
            "\u542f\u7528\u9ad8\u98ce\u9669\u4fdd\u62a4" -> return true
        }
        val value = listOf(
            "set high risk guard ",
            "high risk guard ",
            "set high-risk guard ",
            "high-risk guard "
        ).firstOrNull { normalized.startsWith(it) }
            ?.let { normalized.removePrefix(it).trim() }
            ?: return null
        return when (value) {
            "on", "enable", "enabled" -> true
            "off", "disable", "disabled" -> false
            else -> null
        }
    }

    fun matches(goal: String): Boolean = permissionMode(goal) != null || highRiskGuard(goal) != null
}

internal fun MobileNativeAgent.permissionModeCommandValue(goal: String): PermissionMode? =
    AgentLocalControlCommandPolicy.permissionMode(goal)

internal fun MobileNativeAgent.highRiskGuardCommandValue(goal: String): Boolean? =
    AgentLocalControlCommandPolicy.highRiskGuard(goal)

internal fun MobileNativeAgent.auditTrailCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "audit trail" ||
        normalized == "show audit trail" ||
        normalized == "audit log" ||
        normalized == "show audit log" ||
        normalized == "execution log" ||
        normalized == "show execution log"
}

internal fun MobileNativeAgent.clearTaskHistoryCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "clear task history" ||
        normalized == "clear recent tasks" ||
        normalized == "delete task history" ||
        normalized == "delete recent tasks"
}

internal fun MobileNativeAgent.recentTasksCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "recent tasks" ||
        normalized == "show recent tasks" ||
        normalized == "task history" ||
        normalized == "show task history" ||
        normalized == "last tasks" ||
        normalized == "show last tasks"
}

internal fun MobileNativeAgent.taskSearchCommandValue(goal: String): String? {
    val prefixes = listOf("search tasks ", "find tasks ", "search task ", "find task ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.memoryCaptureCommandValue(goal: String): Boolean? {
    val normalized = goal.trim().lowercase(Locale.US)
    return when (normalized) {
        "private mode on",
        "privacy mode on",
        "pause memory",
        "stop memory",
        "disable memory capture" -> false
        "private mode off",
        "privacy mode off",
        "resume memory",
        "enable memory capture" -> true
        else -> null
    }
}

internal fun MobileNativeAgent.workflowSaveCommandValue(goal: String): Pair<String, String>? {
    val prefixes = listOf("save workflow ", "create workflow ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    val payload = goal.drop(prefix.length).trim()
    val separator = when {
        "::" in payload -> "::"
        "=>" in payload -> "=>"
        else -> return null
    }
    val name = payload.substringBefore(separator).trim()
    val workflowGoal = payload.substringAfter(separator).trim()
    return if (name.isNotBlank() && workflowGoal.isNotBlank()) name to workflowGoal else null
}

internal fun MobileNativeAgent.workflowSaveSyntaxCommand(goal: String): Boolean =
    goal.startsWith("save workflow ", ignoreCase = true) ||
        goal.startsWith("create workflow ", ignoreCase = true)

internal fun MobileNativeAgent.workflowListCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "workflows" ||
        normalized == "list workflows" ||
        normalized == "show workflows"
}

internal fun MobileNativeAgent.workflowHistoryListCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "workflow history" ||
        normalized == "workflow execution history" ||
        normalized == "workflow run history" ||
        normalized == "workflow runs" ||
        normalized == "list workflow history" ||
        normalized == "list workflow runs" ||
        normalized == "show workflow history" ||
        normalized == "show workflow runs"
}

internal fun MobileNativeAgent.workflowRunCommandValue(goal: String): String? {
    val prefixes = listOf("run workflow ", "start workflow ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.workflowTriggerConditionCommandValue(goal: String): WorkflowTriggerConditionRequest? {
    val cleanGoal = goal.trim()
    val match = listOf(
        Regex(
            "^(?:add|attach)\\s+(?:workflow\\s+)?trigger\\s+condition\\s+(\\S+)\\s*(?:::|when|if)\\s*(.+)$",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            "^(?:add|attach)\\s+condition\\s+to\\s+(?:workflow\\s+)?trigger\\s+(\\S+)\\s*(?:::|when|if)\\s*(.+)$",
            RegexOption.IGNORE_CASE
        )
    ).firstNotNullOfOrNull { it.matchEntire(cleanGoal) } ?: return null
    val triggerId = match.groupValues[1].trim()
    val condition = parseWorkflowTriggerCondition(match.groupValues[2]) ?: return null
    return WorkflowTriggerConditionRequest(triggerId, condition)
}

internal fun MobileNativeAgent.parseWorkflowTriggerCondition(value: String): AgentWorkflowCondition? {
    val normalized = value.trim().lowercase(Locale.US).replace(Regex("\\s+"), " ")
    when (normalized) {
        "charging", "device charging", "is charging", "charging required" ->
            return AgentWorkflowCondition.DeviceCharging(required = true)
        "not charging", "device not charging", "is not charging" ->
            return AgentWorkflowCondition.DeviceCharging(required = false)
        "network available", "network availability", "online", "connected" ->
            return AgentWorkflowCondition.NetworkAvailable(required = true)
        "network unavailable", "offline", "no network", "disconnected" ->
            return AgentWorkflowCondition.NetworkAvailable(required = false)
    }

    Regex(
        "^battery(?:\\s+threshold)?\\s+(below|under|at most|at least|above|over|<=|>=|<|>)\\s*(\\d{1,3})%?$",
        RegexOption.IGNORE_CASE
    ).matchEntire(normalized)?.let { match ->
        val percent = match.groupValues[2].toIntOrNull()?.takeIf { it in 0..100 } ?: return null
        val comparison = when (match.groupValues[1].lowercase(Locale.US)) {
            "below", "under", "<" -> AgentWorkflowBatteryComparison.BELOW
            "at most", "<=" -> AgentWorkflowBatteryComparison.AT_MOST
            "at least", ">=" -> AgentWorkflowBatteryComparison.AT_LEAST
            "above", "over", ">" -> AgentWorkflowBatteryComparison.ABOVE
            else -> return null
        }
        return AgentWorkflowCondition.BatteryThreshold(percent, comparison)
    }

    Regex(
        "^(?:time(?:\\s+window)?|between)\\s+(\\d{1,2}):(\\d{2})\\s*(?:-|to|and)\\s*(\\d{1,2}):(\\d{2})$",
        RegexOption.IGNORE_CASE
    ).matchEntire(normalized)?.let { match ->
        val start = minuteOfDay(match.groupValues[1], match.groupValues[2]) ?: return null
        val end = minuteOfDay(match.groupValues[3], match.groupValues[4]) ?: return null
        return AgentWorkflowCondition.TimeWindow(start, end)
    }
    return null
}

internal fun MobileNativeAgent.minuteOfDay(hourValue: String, minuteValue: String): Int? {
    val hour = hourValue.toIntOrNull()?.takeIf { it in 0..23 } ?: return null
    val minute = minuteValue.toIntOrNull()?.takeIf { it in 0..59 } ?: return null
    return hour * 60 + minute
}

internal fun MobileNativeAgent.workflowTriggerConditionsClearCommandValue(goal: String): String? {
    val patterns = listOf(
        Regex(
            "^(?:clear|remove)\\s+(?:workflow\\s+)?trigger\\s+conditions\\s+(\\S+)$",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            "^(?:clear|remove)\\s+(?:all\\s+)?conditions\\s+from\\s+(?:workflow\\s+)?trigger\\s+(\\S+)$",
            RegexOption.IGNORE_CASE
        )
    )
    return patterns.firstNotNullOfOrNull { pattern ->
        pattern.matchEntire(goal.trim())?.groupValues?.get(1)?.trim()?.takeIf { it.isNotBlank() }
    }
}

internal fun MobileNativeAgent.workflowTriggerConditionSyntaxCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized.startsWith("add trigger condition ") ||
        normalized.startsWith("attach trigger condition ") ||
        normalized.startsWith("add workflow trigger condition ") ||
        normalized.startsWith("attach workflow trigger condition ") ||
        normalized.startsWith("add condition to trigger ") ||
        normalized.startsWith("attach condition to trigger ")
}

internal fun MobileNativeAgent.workflowTriggerCreateCommandValue(goal: String): WorkflowTriggerRequest? {
    val cleanGoal = goal.trim()
    val conversationalMatch = listOf(
        Regex(
            "^(?:create|add)\\s+(?:workflow\\s+)?trigger\\s+(?:for\\s+)?(.+?)\\s+(?:when|on)\\s+(.+)$",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            "^trigger\\s+workflow\\s+(.+?)\\s+(?:when|on)\\s+(.+)$",
            RegexOption.IGNORE_CASE
        )
    ).firstNotNullOfOrNull { it.matchEntire(cleanGoal) }
    val delimiterMatch = Regex(
        "^(?:create|add)\\s+(?:workflow\\s+)?trigger\\s+(?:for\\s+)?(.+?)\\s*::\\s*(.+)$",
        RegexOption.IGNORE_CASE
    ).matchEntire(cleanGoal)
    val match = conversationalMatch ?: delimiterMatch ?: return null
    val workflowName = match.groupValues[1].trim()
    val triggerClause = match.groupValues[2].trim()
    if (workflowName.isBlank() || triggerClause.isBlank()) return null

    val packageMatch = Regex(
        "^notification\\s+(?:from\\s+)?package(?:\\s+(?:contains|matches))?(?:\\s*::\\s*|\\s+)(.+)$",
        RegexOption.IGNORE_CASE
    ).matchEntire(triggerClause)
    if (packageMatch != null) {
        return WorkflowTriggerRequest(
            workflowName = workflowName,
            kind = AgentWorkflowTriggerKind.NOTIFICATION_PACKAGE,
            condition = packageMatch.groupValues[1].trim()
        ).takeIf { it.condition.isNotBlank() }
    }

    val textMatch = Regex(
        "^notification\\s+text(?:\\s+(?:contains|matches))?(?:\\s*::\\s*|\\s+)(.+)$",
        RegexOption.IGNORE_CASE
    ).matchEntire(triggerClause)
    if (textMatch != null) {
        return WorkflowTriggerRequest(
            workflowName = workflowName,
            kind = AgentWorkflowTriggerKind.NOTIFICATION_TEXT,
            condition = textMatch.groupValues[1].trim()
        ).takeIf { it.condition.isNotBlank() }
    }

    val normalizedClause = triggerClause.lowercase(Locale.US).replace(Regex("\\s+"), " ")
    return when (normalizedClause) {
        "charging", "power connected", "power connection" -> WorkflowTriggerRequest(
            workflowName = workflowName,
            kind = AgentWorkflowTriggerKind.POWER_CONNECTED
        )
        "battery low", "low battery" -> WorkflowTriggerRequest(
            workflowName = workflowName,
            kind = AgentWorkflowTriggerKind.BATTERY_LOW
        )
        else -> null
    }
}

internal fun MobileNativeAgent.workflowTriggerCreateSyntaxCommand(goal: String): Boolean =
    goal.startsWith("create trigger ", ignoreCase = true) ||
        goal.startsWith("add trigger ", ignoreCase = true) ||
        goal.startsWith("create workflow trigger ", ignoreCase = true) ||
        goal.startsWith("add workflow trigger ", ignoreCase = true) ||
        goal.startsWith("trigger workflow ", ignoreCase = true)

internal fun MobileNativeAgent.workflowTriggerListCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "triggers" ||
        normalized == "list triggers" ||
        normalized == "show triggers" ||
        normalized == "workflow triggers" ||
        normalized == "list workflow triggers" ||
        normalized == "show workflow triggers"
}

internal fun MobileNativeAgent.workflowTriggerDeleteCommandValue(goal: String): String? {
    val prefixes = listOf(
        "delete workflow trigger ",
        "remove workflow trigger ",
        "delete trigger ",
        "remove trigger "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.workflowDeleteCommandValue(goal: String): String? {
    val prefixes = listOf("delete workflow ", "remove workflow ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.workflowScheduleCommandValue(goal: String): WorkflowScheduleRequest? {
    val daily = Regex(
        "^(?:schedule workflow|schedule)\\s+(.+?)\\s+at\\s+(\\d{1,2}):(\\d{2})$",
        RegexOption.IGNORE_CASE
    ).matchEntire(goal.trim())
    if (daily != null) {
        val name = daily.groupValues[1].trim()
        val hour = daily.groupValues[2].toIntOrNull() ?: return null
        val minute = daily.groupValues[3].toIntOrNull() ?: return null
        return WorkflowScheduleRequest(
            workflowName = name,
            kind = AgentWorkflowScheduleKind.DAILY,
            hour = hour,
            minute = minute
        )
    }
    val interval = Regex(
        "^(?:schedule workflow|schedule)\\s+(.+?)\\s+every\\s+(\\d+)\\s+(minutes?|hours?|days?)$",
        RegexOption.IGNORE_CASE
    ).matchEntire(goal.trim()) ?: return null
    val amount = interval.groupValues[2].toLongOrNull() ?: return null
    val unit = interval.groupValues[3].lowercase(Locale.US)
    val minutes = when {
        unit.startsWith("day") -> amount * 24L * 60L
        unit.startsWith("hour") -> amount * 60L
        else -> amount
    }.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    return WorkflowScheduleRequest(
        workflowName = interval.groupValues[1].trim(),
        kind = AgentWorkflowScheduleKind.INTERVAL,
        intervalMinutes = minutes
    )
}

internal fun MobileNativeAgent.workflowScheduleListCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "schedules" ||
        normalized == "list schedules" ||
        normalized == "show schedules" ||
        normalized == "workflow schedules"
}

internal fun MobileNativeAgent.workflowScheduleSyntaxCommand(goal: String): Boolean =
    goal.startsWith("schedule workflow ", ignoreCase = true) ||
        goal.startsWith("schedule ", ignoreCase = true)

internal fun MobileNativeAgent.workflowScheduleCancelCommandValue(goal: String): String? {
    val prefixes = listOf("cancel schedule ", "delete schedule ", "remove schedule ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.templateListCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "workflow templates" ||
        normalized == "list templates" ||
        normalized == "show templates"
}

internal fun MobileNativeAgent.templateRunCommandValue(goal: String): String? {
    val prefixes = listOf("run template ", "start template ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.memoryOverviewCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "memory status" ||
        normalized == "show memory" ||
        normalized == "list memories" ||
        normalized == "recent memories" ||
        normalized == "show recent memories" ||
        normalized == "what do you remember"
}

internal fun MobileNativeAgent.knowledgeOverviewCommand(goal: String): Boolean {
    val normalized = goal.trim().lowercase(Locale.US)
    return normalized == "knowledge status" ||
        normalized == "knowledge base status" ||
        normalized == "show knowledge" ||
        normalized == "list knowledge" ||
        normalized == "recent knowledge" ||
        normalized == "show recent knowledge"
}

internal fun MobileNativeAgent.forgetMemoryCommandValue(goal: String): String? {
    val prefixes = listOf("forget memory ", "delete memory ", "remove memory ", "forget note ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.knowledgeSearchCommandValue(goal: String): String? {
    val prefixes = listOf("search knowledge ", "find knowledge ", "search memory ", "find memory ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.knowledgeAnswerCommandValue(goal: String): String? {
    val prefixes = listOf(
        "ask knowledge ",
        "answer from knowledge ",
        "use knowledge to answer ",
        "ask my knowledge "
    )
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}

internal fun MobileNativeAgent.forgetKnowledgeCommandValue(goal: String): String? {
    val prefixes = listOf("forget knowledge ", "delete knowledge ", "remove knowledge ", "forget document ", "delete document ")
    val prefix = prefixes.firstOrNull { goal.startsWith(it, ignoreCase = true) } ?: return null
    return goal.drop(prefix.length).trim().takeIf { it.isNotBlank() }
}
