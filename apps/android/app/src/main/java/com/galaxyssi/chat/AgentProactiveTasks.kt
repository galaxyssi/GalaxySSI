package com.galaxyssi.chat

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

const val AGENT_PROACTIVE_PROTOCOL = "galaxyssi.proactive-task.v1"

enum class AgentProactiveTriggerKind {
    MANUAL,
    CRON,
    INTERVAL,
    GOAL_CHECKPOINT,
    WEBHOOK
}

enum class AgentProactiveActionKind {
    AGENT,
    SUBAGENT_TEAM,
    WORKFLOW,
    NATIVE_TOOL
}

enum class AgentProactiveMisfirePolicy {
    SKIP,
    FIRE_ONCE,
    CATCH_UP
}

enum class AgentProactiveRunStatus {
    QUEUED,
    RUNNING,
    WAITING,
    RETRYING,
    COMPLETED,
    UNVERIFIED,
    FAILED,
    CANCELLED,
    SKIPPED;

    val terminal: Boolean
        get() = this in setOf(COMPLETED, UNVERIFIED, FAILED, CANCELLED, SKIPPED)
}

enum class AgentProactiveTeamRole {
    LEAD,
    EXECUTOR,
    OBSERVER,
    VERIFIER
}

data class AgentProactiveTrigger(
    val kind: AgentProactiveTriggerKind,
    val cron: String = "",
    val timeZone: String = "UTC",
    val intervalSeconds: Long = 0L,
    val goalId: String = "",
    val webhookId: String = "",
    val eventFilter: Map<String, String> = emptyMap()
) {
    init {
        AgentCronExpression.parseZone(timeZone)
        if (kind == AgentProactiveTriggerKind.CRON) AgentCronExpression.parse(cron)
        if (kind in setOf(AgentProactiveTriggerKind.INTERVAL, AgentProactiveTriggerKind.GOAL_CHECKPOINT)) {
            require(intervalSeconds in MIN_INTERVAL_SECONDS..MAX_INTERVAL_SECONDS) {
                "Proactive interval must be between 60 seconds and one year"
            }
        }
        if (kind == AgentProactiveTriggerKind.GOAL_CHECKPOINT) {
            requireIdentifier(goalId, "Goal id")
        }
        if (kind == AgentProactiveTriggerKind.WEBHOOK && webhookId.isNotBlank()) {
            requireIdentifier(webhookId, "Webhook id")
        }
        require(eventFilter.size <= 32) { "Webhook event filter has too many fields" }
    }

    companion object {
        const val MIN_INTERVAL_SECONDS = 60L
        const val MAX_INTERVAL_SECONDS = 365L * 24L * 60L * 60L
    }
}

data class AgentProactiveTeamMember(
    val agentId: String,
    val role: AgentProactiveTeamRole,
    val instructions: String = ""
) {
    init {
        require(agentId.isNotBlank() && agentId.length <= 128) { "Team Agent id is invalid" }
        require(instructions.length <= 8_192) { "Team instructions are too long" }
    }
}

data class AgentProactiveAction(
    val kind: AgentProactiveActionKind,
    val targetId: String = "",
    val prompt: String = "",
    val argumentsJson: String = "{}",
    val team: List<AgentProactiveTeamMember> = emptyList(),
    val deliveryMode: String = "store",
    val contactId: String = "system",
    val clientRouteId: String = "",
    val grantedPermissions: Set<String> = emptySet(),
    val grantedConsents: Set<String> = emptySet(),
    val conversationId: String = "",
    val scheduleText: String = ""
) {
    init {
        require(prompt.length <= 65_536) { "Proactive prompt is too long" }
        require(runCatching { JSONObject(argumentsJson) }.isSuccess) {
            "Proactive native tool arguments must be a JSON object"
        }
        require(deliveryMode in setOf("store", "notify", "mobile")) {
            "Proactive delivery mode is invalid"
        }
        if (kind == AgentProactiveActionKind.SUBAGENT_TEAM) {
            require(team.isNotEmpty() && team.size <= 12) { "Agent team must contain 1 to 12 members" }
            require(team.count { it.role == AgentProactiveTeamRole.LEAD } == 1) {
                "Agent team requires exactly one lead"
            }
            require(team.map { it.agentId }.distinct().size == team.size) {
                "Agent team members must be unique"
            }
        } else {
            require(targetId.isNotBlank() && targetId.length <= 128) {
                "Proactive action target is invalid"
            }
        }
    }
}

data class AgentProactivePolicy(
    val misfire: AgentProactiveMisfirePolicy = AgentProactiveMisfirePolicy.FIRE_ONCE,
    val catchUpLimit: Int = 3,
    val jitterSeconds: Int = 0,
    val maxAttempts: Int = 3,
    val retryBackoffSeconds: Int = 5,
    val maxConcurrency: Int = 1,
    val maxConsecutiveFailures: Int = 5,
    val deadlineAtMillis: Long = 0L,
    val maxRuns: Int = 0,
    val network: String = "any",
    val requiresCharging: Boolean = false
) {
    init {
        require(catchUpLimit in 1..32)
        require(jitterSeconds in 0..86_400)
        require(maxAttempts in 1..12)
        require(retryBackoffSeconds in 1..86_400)
        require(maxConcurrency in 1..16)
        require(maxConsecutiveFailures in 0..100)
        require(deadlineAtMillis >= 0L && maxRuns >= 0)
        require(network in setOf("any", "unmetered", "offline"))
    }
}

data class AgentProactiveTask(
    val taskId: String = UUID.randomUUID().toString(),
    val name: String,
    val trigger: AgentProactiveTrigger,
    val action: AgentProactiveAction,
    val policy: AgentProactivePolicy = AgentProactivePolicy(),
    val enabled: Boolean = true,
    val nextRunAtMillis: Long = 0L,
    val lastRunAtMillis: Long = 0L,
    val lastStatus: AgentProactiveRunStatus = AgentProactiveRunStatus.QUEUED,
    val runCount: Int = 0,
    val consecutiveFailures: Int = 0,
    val revision: Int = 1,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis
) {
    init {
        requireIdentifier(taskId, "Task id")
        require(name.isNotBlank() && name.length <= 120) { "Proactive task name is invalid" }
    }
}

data class AgentProactiveRun(
    val runId: String,
    val taskId: String,
    val scheduledForMillis: Long,
    val status: AgentProactiveRunStatus,
    val attempt: Int = 1,
    val causeJson: String = "{}",
    val startedAtMillis: Long = 0L,
    val completedAtMillis: Long = 0L,
    val resultSummary: String = "",
    val errorCode: String = "",
    val linkedExecutionId: String = "",
    val teamRunId: String = "",
    val deliveryRecorded: Boolean = false,
    val resultRichOutputJson: String = ""
)

data class AgentRemoteProactiveEvent(
    val eventId: String,
    val desktopId: String,
    val desktopName: String,
    val taskId: String,
    val runId: String,
    val kind: String,
    val status: String,
    val detail: String,
    val timestampMillis: Long
)

class AgentRemoteProactiveEventStore(context: Context) {
    private val database = AgentEncryptedDatabase(
        context.applicationContext,
        DATABASE
    )

    @Synchronized
    fun ingest(payload: JSONObject, trustedDesktopId: String) {
        if (trustedDesktopId.isBlank()) return
        val runId = payload.optString("run_id").take(128)
        val sequence = payload.optLong("sequence")
        val timestamp = payload.optLong("timestamp_millis")
            .takeIf { it > 0L }
            ?: System.currentTimeMillis()
        val identity = listOf(
            trustedDesktopId,
            runId,
            sequence.toString(),
            payload.optString("kind"),
            timestamp.toString()
        ).joinToString("\u001f")
        val eventId = UUID.nameUUIDFromBytes(identity.toByteArray(Charsets.UTF_8)).toString()
        val event = AgentRemoteProactiveEvent(
            eventId = eventId,
            desktopId = trustedDesktopId.take(128),
            desktopName = payload.optString("desktop_name").take(120),
            taskId = payload.optString("task_id").take(128),
            runId = runId,
            kind = payload.optString("kind").take(64),
            status = payload.optString("status").take(32),
            detail = payload.optString("detail").take(2_048),
            timestampMillis = timestamp
        )
        database.writeString("$EVENT_PREFIX$eventId", encode(event).toString())
        if (database.keys(EVENT_PREFIX).size > MAX_EVENTS) {
            val all = allEvents()
            database.removeAll(
                all.drop(MAX_EVENTS).map { "$EVENT_PREFIX${it.eventId}" }
            )
        }
    }

    fun recent(limit: Int = 100): List<AgentRemoteProactiveEvent> =
        allEvents().take(limit.coerceIn(1, MAX_EVENTS))

    private fun allEvents(): List<AgentRemoteProactiveEvent> =
        database.entries(EVENT_PREFIX)
            .mapNotNull { (_, raw) -> decode(raw) }
            .sortedByDescending(AgentRemoteProactiveEvent::timestampMillis)

    private fun encode(value: AgentRemoteProactiveEvent) = JSONObject()
        .put("event_id", value.eventId)
        .put("desktop_id", value.desktopId)
        .put("desktop_name", value.desktopName)
        .put("task_id", value.taskId)
        .put("run_id", value.runId)
        .put("kind", value.kind)
        .put("status", value.status)
        .put("detail", value.detail)
        .put("timestamp_millis", value.timestampMillis)

    private fun decode(raw: String): AgentRemoteProactiveEvent? = runCatching {
        val json = JSONObject(raw)
        AgentRemoteProactiveEvent(
            eventId = json.getString("event_id"),
            desktopId = json.getString("desktop_id"),
            desktopName = json.optString("desktop_name"),
            taskId = json.optString("task_id"),
            runId = json.optString("run_id"),
            kind = json.optString("kind"),
            status = json.optString("status"),
            detail = json.optString("detail"),
            timestampMillis = json.optLong("timestamp_millis")
        )
    }.getOrNull()

    private companion object {
        const val DATABASE = "galaxyssi_remote_proactive_events_v1"
        const val EVENT_PREFIX = "event:"
        const val MAX_EVENTS = 500
    }
}

class AgentProactiveTaskStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun tasks(): List<AgentProactiveTask> = database.entries(TASK_PREFIX)
        .mapNotNull { (_, value) -> decodeTask(value) }
        .sortedByDescending { it.updatedAtMillis }

    @Synchronized
    fun task(taskId: String): AgentProactiveTask? =
        database.readString(taskKey(taskId), "").takeIf(String::isNotBlank)?.let(::decodeTask)

    @Synchronized
    fun upsert(task: AgentProactiveTask) {
        database.writeString(taskKey(task.taskId), encodeTask(task).toString())
        ConversationScheduleState.notifyChanged(task.taskId)
    }

    @Synchronized
    fun delete(taskId: String): Boolean {
        val key = taskKey(taskId)
        if (!database.contains(key)) return false
        database.remove(key)
        database.keys(RUN_PREFIX).forEach { runKey ->
            val run = decodeRun(database.readString(runKey, ""))
            if (run?.taskId == taskId) database.remove(runKey)
        }
        ConversationScheduleState.notifyChanged(taskId)
        return true
    }

    @Synchronized
    fun run(runId: String): AgentProactiveRun? =
        database.readString(runKey(runId), "").takeIf(String::isNotBlank)?.let(::decodeRun)

    @Synchronized
    fun createRun(run: AgentProactiveRun): Boolean {
        val key = runKey(run.runId)
        if (database.contains(key)) return false
        database.writeString(key, encodeRun(run).toString())
        trimRuns()
        ConversationScheduleState.notifyChanged(run.taskId)
        return true
    }

    @Synchronized
    fun upsertRun(run: AgentProactiveRun) {
        database.writeString(runKey(run.runId), encodeRun(run).toString())
        trimRuns()
        ConversationScheduleState.notifyChanged(run.taskId)
    }

    internal fun completeScheduledRun(result: AgentProactiveRun): Boolean = synchronized(AgentProactiveTaskScheduler) {
        val previous = run(result.runId) ?: return@synchronized false
        if (previous.status.terminal) return@synchronized false
        val task = task(result.taskId) ?: return@synchronized false
        val failures = if (result.status == AgentProactiveRunStatus.FAILED) task.consecutiveFailures + 1 else 0
        val updated = task.copy(lastRunAtMillis = result.completedAtMillis, lastStatus = result.status,
            runCount = task.runCount + 1, consecutiveFailures = failures, updatedAtMillis = result.completedAtMillis)
        database.mutateStrings(mapOf(taskKey(task.taskId) to encodeTask(updated).toString(),
            runKey(result.runId) to encodeRun(result).toString()))
        ConversationScheduleState.notifyChanged(task.taskId)
        true
    }

    internal fun updateScheduledPendingRun(value: AgentProactiveRun): Boolean = synchronized(AgentProactiveTaskScheduler) {
        val current = run(value.runId) ?: return@synchronized false
        val latest = task(value.taskId) ?: return@synchronized false
        if (current.status.terminal || !latest.enabled) return@synchronized false
        if (current.teamRunId.isBlank() && JSONObject(current.causeJson).optInt("task_revision", latest.revision) != latest.revision) {
            upsertRun(current.copy(status = AgentProactiveRunStatus.CANCELLED,
                completedAtMillis = System.currentTimeMillis(), errorCode = "schedule_updated", deliveryRecorded = true))
            return@synchronized false
        }
        upsertRun(value.copy(teamRunId = value.teamRunId.ifBlank { current.teamRunId }))
        true
    }

    @Synchronized
    fun runs(taskId: String = "", limit: Int = 100): List<AgentProactiveRun> =
        database.entries(RUN_PREFIX)
            .mapNotNull { (_, value) -> decodeRun(value) }
            .filter { taskId.isBlank() || it.taskId == taskId }
            .sortedByDescending { it.scheduledForMillis }
            .take(limit.coerceIn(1, 1_000))

    internal fun recoverableRuns(): List<AgentProactiveRun> = database.entries(RUN_PREFIX)
        .mapNotNull { (_, value) -> decodeRun(value) }
        .filter { !it.status.terminal || !it.deliveryRecorded }
        .sortedBy { it.scheduledForMillis }

    @Synchronized
    fun consumeRemoteEvent(taskId: String, eventId: String): Boolean {
        requireIdentifier(eventId, "Event id")
        val key = "$EVENT_PREFIX$taskId:$eventId"
        if (database.contains(key)) return false
        database.writeString(key, System.currentTimeMillis().toString())
        val keys = database.keys(EVENT_PREFIX)
        if (keys.size > MAX_EVENTS) database.removeAll(keys.take(keys.size - MAX_EVENTS))
        return true
    }

    @Synchronized
    fun clear() = database.clear()

    private fun trimRuns() {
        val values = database.entries(RUN_PREFIX)
            .mapNotNull { (key, value) -> decodeRun(value)?.let { key to it } }
            .sortedBy { it.second.scheduledForMillis }
        if (values.size > MAX_RUNS) database.removeAll(values.filter { (_, run) ->
            run.status.terminal && (run.status in setOf(AgentProactiveRunStatus.CANCELLED, AgentProactiveRunStatus.SKIPPED) ||
                run.deliveryRecorded || task(run.taskId)?.action?.conversationId.isNullOrBlank())
        }.take(values.size - MAX_RUNS).map { it.first })
    }

    private fun taskKey(taskId: String) = "$TASK_PREFIX$taskId"
    private fun runKey(runId: String) = "$RUN_PREFIX$runId"

    private fun encodeTask(task: AgentProactiveTask): JSONObject = JSONObject()
        .put("protocol", AGENT_PROACTIVE_PROTOCOL)
        .put("task_id", task.taskId)
        .put("name", task.name)
        .put("trigger", encodeTrigger(task.trigger))
        .put("action", encodeAction(task.action))
        .put("policy", encodePolicy(task.policy))
        .put("enabled", task.enabled)
        .put("next_run_at_millis", task.nextRunAtMillis)
        .put("last_run_at_millis", task.lastRunAtMillis)
        .put("last_status", task.lastStatus.name)
        .put("run_count", task.runCount)
        .put("consecutive_failures", task.consecutiveFailures)
        .put("revision", task.revision)
        .put("created_at_millis", task.createdAtMillis)
        .put("updated_at_millis", task.updatedAtMillis)

    private fun decodeTask(raw: String): AgentProactiveTask? = runCatching {
        val json = JSONObject(raw)
        require(json.optString("protocol") == AGENT_PROACTIVE_PROTOCOL)
        AgentProactiveTask(
            taskId = json.getString("task_id"),
            name = json.getString("name"),
            trigger = decodeTrigger(json.getJSONObject("trigger")),
            action = decodeAction(json.getJSONObject("action")),
            policy = decodePolicy(json.optJSONObject("policy") ?: JSONObject()),
            enabled = json.optBoolean("enabled", true),
            nextRunAtMillis = json.optLong("next_run_at_millis"),
            lastRunAtMillis = json.optLong("last_run_at_millis"),
            lastStatus = enumValue(
                json.optString("last_status"),
                AgentProactiveRunStatus.QUEUED
            ),
            runCount = json.optInt("run_count").coerceAtLeast(0),
            consecutiveFailures = json.optInt("consecutive_failures").coerceAtLeast(0),
            revision = json.optInt("revision", 1).coerceAtLeast(1),
            createdAtMillis = json.optLong("created_at_millis").coerceAtLeast(0L),
            updatedAtMillis = json.optLong("updated_at_millis").coerceAtLeast(0L)
        )
    }.getOrNull()

    private fun encodeTrigger(value: AgentProactiveTrigger): JSONObject = JSONObject()
        .put("kind", value.kind.name)
        .put("cron", value.cron)
        .put("time_zone", value.timeZone)
        .put("interval_seconds", value.intervalSeconds)
        .put("goal_id", value.goalId)
        .put("webhook_id", value.webhookId)
        .put("event_filter", JSONObject(value.eventFilter))

    private fun decodeTrigger(json: JSONObject) = AgentProactiveTrigger(
        kind = enumValue(json.optString("kind"), AgentProactiveTriggerKind.MANUAL),
        cron = json.optString("cron"),
        timeZone = json.optString("time_zone").ifBlank { "UTC" },
        intervalSeconds = json.optLong("interval_seconds"),
        goalId = json.optString("goal_id"),
        webhookId = json.optString("webhook_id"),
        eventFilter = json.optJSONObject("event_filter").toStringMap()
    )

    private fun encodeAction(value: AgentProactiveAction): JSONObject = JSONObject()
        .put("kind", value.kind.name)
        .put("target_id", value.targetId)
        .put("prompt", value.prompt)
        .put("arguments", JSONObject(value.argumentsJson))
        .put("team", JSONArray().apply {
            value.team.forEach { member ->
                put(JSONObject()
                    .put("agent_id", member.agentId)
                    .put("role", member.role.name)
                    .put("instructions", member.instructions))
            }
        })
        .put("delivery_mode", value.deliveryMode)
        .put("contact_id", value.contactId)
        .put("client_route_id", value.clientRouteId)
        .put("granted_permissions", JSONArray(value.grantedPermissions.toList()))
        .put("granted_consents", JSONArray(value.grantedConsents.toList()))
        .put("conversation_id", value.conversationId)
        .put("schedule_text", value.scheduleText)

    private fun decodeAction(json: JSONObject) = AgentProactiveAction(
        kind = enumValue(json.optString("kind"), AgentProactiveActionKind.AGENT),
        targetId = json.optString("target_id"),
        prompt = json.optString("prompt"),
        argumentsJson = (json.optJSONObject("arguments") ?: JSONObject()).toString(),
        team = json.optJSONArray("team").toObjectList().mapNotNull { member ->
            runCatching {
                AgentProactiveTeamMember(
                    member.getString("agent_id"),
                    enumValue(member.optString("role"), AgentProactiveTeamRole.OBSERVER),
                    member.optString("instructions")
                )
            }.getOrNull()
        },
        deliveryMode = json.optString("delivery_mode").ifBlank { "store" },
        contactId = json.optString("contact_id").ifBlank { "system" },
        clientRouteId = json.optString("client_route_id"),
        grantedPermissions = json.optJSONArray("granted_permissions").toStringSet(),
        grantedConsents = json.optJSONArray("granted_consents").toStringSet(),
        conversationId = json.optString("conversation_id"),
        scheduleText = json.optString("schedule_text")
    )

    private fun encodePolicy(value: AgentProactivePolicy): JSONObject = JSONObject()
        .put("misfire", value.misfire.name)
        .put("catch_up_limit", value.catchUpLimit)
        .put("jitter_seconds", value.jitterSeconds)
        .put("max_attempts", value.maxAttempts)
        .put("retry_backoff_seconds", value.retryBackoffSeconds)
        .put("max_concurrency", value.maxConcurrency)
        .put("max_consecutive_failures", value.maxConsecutiveFailures)
        .put("deadline_at_millis", value.deadlineAtMillis)
        .put("max_runs", value.maxRuns)
        .put("network", value.network)
        .put("requires_charging", value.requiresCharging)

    private fun decodePolicy(json: JSONObject) = AgentProactivePolicy(
        misfire = enumValue(json.optString("misfire"), AgentProactiveMisfirePolicy.FIRE_ONCE),
        catchUpLimit = json.optInt("catch_up_limit", 3),
        jitterSeconds = json.optInt("jitter_seconds"),
        maxAttempts = json.optInt("max_attempts", 3),
        retryBackoffSeconds = json.optInt("retry_backoff_seconds", 5),
        maxConcurrency = json.optInt("max_concurrency", 1),
        maxConsecutiveFailures = json.optInt("max_consecutive_failures", 5),
        deadlineAtMillis = json.optLong("deadline_at_millis"),
        maxRuns = json.optInt("max_runs"),
        network = json.optString("network").ifBlank { "any" },
        requiresCharging = json.optBoolean("requires_charging")
    )

    private fun encodeRun(run: AgentProactiveRun): JSONObject = JSONObject()
        .put("run_id", run.runId)
        .put("task_id", run.taskId)
        .put("scheduled_for_millis", run.scheduledForMillis)
        .put("status", run.status.name)
        .put("attempt", run.attempt)
        .put("cause", JSONObject(run.causeJson))
        .put("started_at_millis", run.startedAtMillis)
        .put("completed_at_millis", run.completedAtMillis)
        .put("result_summary", run.resultSummary)
        .put("error_code", run.errorCode)
        .put("linked_execution_id", run.linkedExecutionId)
        .put("team_run_id", run.teamRunId)
        .put("delivery_recorded", run.deliveryRecorded)
        .put("result_rich_output_json", run.resultRichOutputJson)

    private fun decodeRun(raw: String): AgentProactiveRun? = runCatching {
        val json = JSONObject(raw)
        AgentProactiveRun(
            runId = json.getString("run_id"),
            taskId = json.getString("task_id"),
            scheduledForMillis = json.getLong("scheduled_for_millis"),
            status = enumValue(json.optString("status"), AgentProactiveRunStatus.FAILED),
            attempt = json.optInt("attempt", 1).coerceAtLeast(1),
            causeJson = (json.optJSONObject("cause") ?: JSONObject()).toString(),
            startedAtMillis = json.optLong("started_at_millis"),
            completedAtMillis = json.optLong("completed_at_millis"),
            resultSummary = json.optString("result_summary").take(65_536),
            errorCode = json.optString("error_code").take(128),
            linkedExecutionId = json.optString("linked_execution_id"),
            teamRunId = json.optString("team_run_id"),
            deliveryRecorded = json.optBoolean("delivery_recorded"),
            resultRichOutputJson = json.optString("result_rich_output_json")
        )
    }.getOrNull()

    private companion object {
        const val DATABASE = "galaxyssi_proactive_tasks_v1"
        const val TASK_PREFIX = "task:"
        const val RUN_PREFIX = "run:"
        const val EVENT_PREFIX = "event:"
        const val MAX_RUNS = 2_000
        const val MAX_EVENTS = 2_000
    }
}

object AgentProactiveTaskScheduler {
    const val ACTION_RUN = "com.galaxyssi.chat.action.RUN_PROACTIVE_TASK"
    const val EXTRA_TASK_ID = "proactive_task_id"
    const val EXTRA_RUN_ID = "proactive_run_id"
    private const val WINDOW_MILLIS = 60_000L
    private val awakeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val awakeTimers = ConcurrentHashMap<String, Job>()
    private val awakeRunTimers = ConcurrentHashMap<String, Job>()

    internal fun wakeRunWhileAwake(context: Context, runId: String, atMillis: Long) {
        val app = context.applicationContext
        awakeRunTimers.remove(runId)?.cancel()
        awakeRunTimers[runId] = awakeScope.launch {
            delay((atMillis - System.currentTimeMillis()).coerceAtLeast(1L))
            awakeRunTimers.remove(runId)
            runCatching { resumeRun(app, runId) }
        }
    }

    @Synchronized
    fun save(context: Context, task: AgentProactiveTask, runImmediately: Boolean = false): AgentProactiveTask {
        require(!runImmediately || task.trigger.kind in setOf(AgentProactiveTriggerKind.INTERVAL,
            AgentProactiveTriggerKind.CRON, AgentProactiveTriggerKind.GOAL_CHECKPOINT))
        require(
            task.action.kind !in setOf(
                AgentProactiveActionKind.AGENT,
                AgentProactiveActionKind.SUBAGENT_TEAM
            ) || task.action.prompt.isNotBlank()
        ) {
            "Agent and sub-agent team actions require a goal or instructions"
        }
        val now = System.currentTimeMillis()
        awakeTimers.remove(task.taskId)?.cancel()
        alarmManager(context).cancel(taskPendingIntent(context, task.taskId))
        val next = task.copy(
            nextRunAtMillis = if (!task.enabled) 0L else if (runImmediately) now else initialNextRun(task, now),
            updatedAtMillis = now
        )
        AgentProactiveTaskStore(context).upsert(next)
        if (task.enabled && runImmediately) {
            // Use the durable occurrence path, including pending-run coalescing and recovery.
            handleAlarm(context, next.taskId)
            return AgentProactiveTaskStore(context).task(next.taskId) ?: next
        }
        register(context, next)
        return next
    }

    @Synchronized
    fun cancel(context: Context, taskId: String): Boolean {
        awakeTimers.remove(taskId)?.cancel()
        alarmManager(context).cancel(taskPendingIntent(context, taskId))
        val store = AgentProactiveTaskStore(context)
        store.runs(taskId, limit = 1_000)
            .filter { !it.status.terminal }
            .forEach { AgentProactiveTaskExecutor.cancel(context, it.runId) }
        return store.delete(taskId)
    }

    @Synchronized
    fun restoreAll(context: Context, conversationOnly: Boolean = false) {
        val store = AgentProactiveTaskStore(context)
        val now = System.currentTimeMillis()
        store.tasks().filter { it.enabled && (!conversationOnly || it.action.conversationId.isNotBlank()) }.forEach { task ->
            val next = if (task.nextRunAtMillis > 0L) task.nextRunAtMillis else initialNextRun(task, now)
            val updated = task.copy(nextRunAtMillis = next, updatedAtMillis = now)
            store.upsert(updated)
            register(context, updated)
        }
        if (!conversationOnly) reconcile(context)
        recoverPendingRuns(context, store, now, conversationOnly)
        store.recoverableRuns().filter { it.status in setOf(AgentProactiveRunStatus.COMPLETED, AgentProactiveRunStatus.UNVERIFIED,
            AgentProactiveRunStatus.FAILED) && !it.deliveryRecorded }.forEach { run ->
            val task = store.task(run.taskId)?.takeIf { it.action.conversationId.isNotBlank() } ?: return@forEach
            if (ConversationScheduledTasks.deliver(context, task, run))
                AgentProactiveTaskNotifier.deliver(context, task, run.resultSummary, run.status != AgentProactiveRunStatus.COMPLETED)
        }
    }

    fun triggerNow(
        context: Context,
        taskId: String,
        cause: JSONObject = JSONObject().put("type", "manual")
    ): AgentProactiveRun {
        val store = AgentProactiveTaskStore(context)
        val task = requireNotNull(store.task(taskId)?.takeIf { it.enabled }) {
            "Proactive task is missing or disabled"
        }
        return enqueue(context, store, task, System.currentTimeMillis(), cause)
    }

    fun acceptRemoteWebhook(
        context: Context,
        taskId: String,
        eventId: String,
        payload: JSONObject,
        sourceDesktopId: String
    ): AgentProactiveRun? {
        val trusted = GalaxySSILinkProtocol.allServerLinks(context).any {
            it.desktopId == sourceDesktopId && it.paired
        }
        if (!trusted) return null
        val store = AgentProactiveTaskStore(context)
        val task = store.task(taskId)?.takeIf {
            it.enabled && it.trigger.kind == AgentProactiveTriggerKind.WEBHOOK
        } ?: return null
        if (!eventMatches(task.trigger.eventFilter, payload)) return null
        if (!store.consumeRemoteEvent(taskId, eventId)) return store.run(stableRunId(taskId, eventId))
        return enqueue(
            context,
            store,
            task,
            System.currentTimeMillis(),
            JSONObject()
                .put("type", "webhook")
                .put("event_id", eventId)
                .put("source_desktop_id", sourceDesktopId)
                .put("payload", payload)
        )
    }

    @Synchronized
    fun handleAlarm(context: Context, taskId: String) {
        val store = AgentProactiveTaskStore(context)
        val task = store.task(taskId)?.takeIf { it.enabled } ?: return
        val now = System.currentTimeMillis()
        if (task.nextRunAtMillis <= 0L || now < task.nextRunAtMillis) return
        if (shouldDisable(task, now)) {
            store.upsert(task.copy(enabled = false, nextRunAtMillis = 0L, updatedAtMillis = now))
            return
        }
        val (occurrences, nextRun) = dueOccurrences(task, now)
        val updated = task.copy(nextRunAtMillis = nextRun, updatedAtMillis = now)
        store.upsert(updated)
        register(context, updated)
        occurrences.forEach { (scheduledFor, status) ->
            if (status == AgentProactiveRunStatus.SKIPPED) {
                val run = newRun(task, scheduledFor, JSONObject().put("type", "misfire"))
                    .copy(status = status, completedAtMillis = now)
                store.createRun(run)
            } else {
                val pending = if (task.action.conversationId.isNotBlank())
                    store.runs(taskId, 1_000).firstOrNull { !it.status.terminal } else null
                if (pending != null) {
                    // A repeating schedule never accumulates a backlog behind a slow/offline run.
                    if (pending.status != AgentProactiveRunStatus.RUNNING) resumeRun(context, pending.runId)
                    return@forEach
                }
                enqueue(
                    context,
                    store,
                    task,
                    scheduledFor,
                    JSONObject()
                        .put("type", task.trigger.kind.name.lowercase())
                        .put("scheduled_for_millis", scheduledFor)
                )
            }
        }
    }

    fun reconcile(context: Context) {
        val store = AgentProactiveTaskStore(context)
        val executionStore = AgentWorkflowExecutionHistoryStore(context)
        store.runs(limit = 500)
            .filter { !it.status.terminal && it.linkedExecutionId.isNotBlank() }
            .forEach { run ->
                val execution = executionStore.findById(run.linkedExecutionId) ?: return@forEach
                val status = execution.status.toProactiveStatus()
                val completed = if (status.terminal) {
                    execution.completedAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
                } else 0L
                if (run.status != status || run.completedAtMillis != completed) {
                    val updatedRun = run.copy(
                        status = status,
                        completedAtMillis = completed,
                        resultSummary = execution.resultSummary.take(4_096)
                    )
                    store.upsertRun(updatedRun)
                    if (status.terminal) {
                        AgentProactiveTaskExecutor.finalizeReconciled(
                            context,
                            store,
                            store.task(run.taskId),
                            updatedRun
                        )
                    }
                }
            }
    }

    internal fun initialNextRun(task: AgentProactiveTask, now: Long): Long = when (task.trigger.kind) {
        AgentProactiveTriggerKind.CRON ->
            AgentCronExpression.parse(task.trigger.cron).nextAfter(now, task.trigger.timeZone)
        AgentProactiveTriggerKind.INTERVAL,
        AgentProactiveTriggerKind.GOAL_CHECKPOINT -> now + task.trigger.intervalSeconds * 1_000L
        AgentProactiveTriggerKind.MANUAL,
        AgentProactiveTriggerKind.WEBHOOK -> 0L
    }.let { base -> base + deterministicJitter(task.taskId, base, task.policy.jitterSeconds) }

    internal fun dueOccurrences(
        task: AgentProactiveTask,
        now: Long
    ): Pair<List<Pair<Long, AgentProactiveRunStatus>>, Long> {
        val scheduled = task.nextRunAtMillis
        if (task.trigger.kind in setOf(
                AgentProactiveTriggerKind.INTERVAL,
                AgentProactiveTriggerKind.GOAL_CHECKPOINT
            )
        ) {
            val interval = task.trigger.intervalSeconds * 1_000L
            val count = (((now - scheduled) / interval) + 1L).coerceAtLeast(1L)
            val next = scheduled + count * interval
            if (now - scheduled <= 60_000L) {
                return listOf(scheduled to AgentProactiveRunStatus.QUEUED) to next
            }
            val retained = minOf(count, task.policy.catchUpLimit.toLong()).toInt()
            val first = count - retained
            val due = (first until count).map { scheduled + it * interval }
            return when (task.policy.misfire) {
                AgentProactiveMisfirePolicy.SKIP ->
                    due.map { it to AgentProactiveRunStatus.SKIPPED } to next
                AgentProactiveMisfirePolicy.FIRE_ONCE ->
                    listOf(due.last() to AgentProactiveRunStatus.QUEUED) to next
                AgentProactiveMisfirePolicy.CATCH_UP ->
                    due.map { it to AgentProactiveRunStatus.QUEUED } to next
            }
        }
        val cron = AgentCronExpression.parse(task.trigger.cron)
        val baseNext = cron.nextAfter(now, task.trigger.timeZone)
        val next = baseNext + deterministicJitter(task.taskId, baseNext, task.policy.jitterSeconds)
        if (now - scheduled <= 60_000L) {
            return listOf(scheduled to AgentProactiveRunStatus.QUEUED) to next
        }
        return when (task.policy.misfire) {
            AgentProactiveMisfirePolicy.SKIP ->
                listOf(scheduled to AgentProactiveRunStatus.SKIPPED) to next
            AgentProactiveMisfirePolicy.FIRE_ONCE ->
                listOf(now to AgentProactiveRunStatus.QUEUED) to next
            AgentProactiveMisfirePolicy.CATCH_UP -> {
                val values = mutableListOf<Long>()
                var cursor = now
                while (values.size < task.policy.catchUpLimit) {
                    val previous = cron.previousAtOrBefore(cursor, task.trigger.timeZone)
                    if (previous < scheduled) break
                    values += previous
                    cursor = previous - 60_000L
                }
                values.sorted().map { it to AgentProactiveRunStatus.QUEUED } to next
            }
        }
    }

    @Synchronized
    internal fun recordOutcome(
        store: AgentProactiveTaskStore,
        taskId: String,
        status: AgentProactiveRunStatus,
        completedAtMillis: Long
    ) {
        val task = store.task(taskId) ?: return
        val failures = when (status) {
            AgentProactiveRunStatus.COMPLETED -> 0
            AgentProactiveRunStatus.FAILED -> task.consecutiveFailures + 1
            else -> task.consecutiveFailures
        }
        val nextRunCount = task.runCount + 1
        val enabled = task.enabled &&
            (task.policy.maxConsecutiveFailures == 0 || failures < task.policy.maxConsecutiveFailures) &&
            (task.policy.maxRuns == 0 || nextRunCount < task.policy.maxRuns)
        store.upsert(
            task.copy(
                enabled = enabled,
                nextRunAtMillis = if (enabled) task.nextRunAtMillis else 0L,
                lastRunAtMillis = completedAtMillis,
                lastStatus = status,
                runCount = nextRunCount,
                consecutiveFailures = failures,
                updatedAtMillis = completedAtMillis
            )
        )
    }

    private fun enqueue(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        scheduledForMillis: Long,
        cause: JSONObject
    ): AgentProactiveRun {
        val stableCauseId = cause.optString("event_id").ifBlank { scheduledForMillis.toString() }
        val run = newRun(task, scheduledForMillis, cause, stableCauseId)
        if (store.createRun(run)) startRunService(context, run.runId)
        return store.run(run.runId) ?: run
    }

    private fun newRun(
        task: AgentProactiveTask,
        scheduledForMillis: Long,
        cause: JSONObject,
        stableCauseId: String = scheduledForMillis.toString()
    ) = AgentProactiveRun(
        runId = stableRunId(task.taskId, stableCauseId),
        taskId = task.taskId,
        scheduledForMillis = scheduledForMillis,
        status = AgentProactiveRunStatus.QUEUED,
        causeJson = JSONObject(cause.toString()).put("task_revision", task.revision).toString()
    )

    private fun register(context: Context, task: AgentProactiveTask) {
        if (!task.enabled || task.nextRunAtMillis <= 0L) return
        if (task.action.conversationId.isNotBlank()) {
            val app = context.applicationContext
            awakeTimers.remove(task.taskId)?.cancel()
            awakeTimers[task.taskId] = awakeScope.launch {
                delay((task.nextRunAtMillis - System.currentTimeMillis()).coerceAtLeast(1L))
                runCatching { handleAlarm(app, task.taskId) }
                    .onFailure { android.util.Log.w("GalaxySSISchedule", "Awake schedule wake failed; alarm remains registered", it) }
            }
        }
        alarmManager(context).setWindow(
            AlarmManager.RTC_WAKEUP,
            task.nextRunAtMillis.coerceAtLeast(System.currentTimeMillis() + 1_000L),
            WINDOW_MILLIS,
            taskPendingIntent(context, task.taskId)
        )
    }

    private fun startRunService(context: Context, runId: String) {
        val intent = Intent(context, MessageService::class.java)
            .setAction(ACTION_RUN)
            .putExtra(EXTRA_RUN_ID, runId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    internal fun resumeRun(context: Context, runId: String) {
        if (runId.isBlank()) return
        val run = AgentProactiveTaskStore(context).run(runId)?.takeIf { !it.status.terminal } ?: return
        startRunService(context, run.runId)
    }

    private fun taskPendingIntent(context: Context, taskId: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            taskId.hashCode(),
            Intent(context, AgentProactiveAlarmReceiver::class.java)
                .setAction(ACTION_RUN)
                .putExtra(EXTRA_TASK_ID, taskId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun alarmManager(context: Context): AlarmManager =
        context.applicationContext.getSystemService(AlarmManager::class.java)

    private fun shouldDisable(task: AgentProactiveTask, now: Long): Boolean =
        (task.policy.deadlineAtMillis > 0L && now > task.policy.deadlineAtMillis) ||
            (task.policy.maxRuns > 0 && task.runCount >= task.policy.maxRuns) ||
            (task.policy.maxConsecutiveFailures > 0 && task.consecutiveFailures >= task.policy.maxConsecutiveFailures)

    private fun recoverPendingRuns(
        context: Context,
        store: AgentProactiveTaskStore,
        now: Long,
        conversationOnly: Boolean = false
    ) {
        store.recoverableRuns()
            .filter { !it.status.terminal }
            .forEach { run ->
                if (conversationOnly && store.task(run.taskId)?.action?.conversationId.isNullOrBlank()) return@forEach
                when {
                    run.teamRunId.isNotBlank() && store.task(run.taskId)?.action?.conversationId?.isNotBlank() == true ->
                        startRunService(context, run.runId)
                    run.linkedExecutionId.isNotBlank() -> Unit
                    run.status == AgentProactiveRunStatus.WAITING ->
                        AgentProactiveTaskExecutor.scheduleWake(context, run.runId, now + 30_000L)
                    run.status == AgentProactiveRunStatus.RUNNING &&
                        now - run.startedAtMillis < RUN_RECOVERY_GRACE_MILLIS -> Unit
                    else -> {
                        store.upsertRun(
                            run.copy(
                                status = AgentProactiveRunStatus.RETRYING,
                                resultSummary = "Resuming interrupted proactive task"
                            )
                        )
                        AgentProactiveTaskExecutor.scheduleWake(context, run.runId, now + 1_000L)
                    }
                }
            }
    }

    private fun deterministicJitter(taskId: String, occurrence: Long, jitterSeconds: Int): Long {
        if (jitterSeconds <= 0 || occurrence <= 0L) return 0L
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$taskId:$occurrence".toByteArray(Charsets.UTF_8))
        val unsigned = ((bytes[0].toLong() and 0xff) shl 24) or
            ((bytes[1].toLong() and 0xff) shl 16) or
            ((bytes[2].toLong() and 0xff) shl 8) or
            (bytes[3].toLong() and 0xff)
        return unsigned % (jitterSeconds * 1_000L + 1L)
    }

    private fun stableRunId(taskId: String, occurrence: String): String =
        UUID.nameUUIDFromBytes("$taskId\u001f$occurrence".toByteArray(Charsets.UTF_8)).toString()

    private fun eventMatches(filter: Map<String, String>, payload: JSONObject): Boolean =
        filter.all { (path, expected) ->
            var cursor: Any? = payload
            for (segment in path.split(".")) {
                cursor = (cursor as? JSONObject)?.opt(segment)
                if (cursor == null || cursor == JSONObject.NULL) break
            }
            cursor?.toString() == expected
        }

    private const val RUN_RECOVERY_GRACE_MILLIS = 60_000L
}

class AgentProactiveAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AgentProactiveTaskScheduler.ACTION_RUN) return
        val pending = goAsync()
        scope.launch {
            try {
                val runId = intent.getStringExtra(AgentProactiveTaskScheduler.EXTRA_RUN_ID).orEmpty()
                if (runId.isNotBlank()) AgentProactiveTaskScheduler.resumeRun(context, runId)
                else intent.getStringExtra(AgentProactiveTaskScheduler.EXTRA_TASK_ID)?.takeIf(String::isNotBlank)
                    ?.let { AgentProactiveTaskScheduler.handleAlarm(context, it) }
            } catch (error: Exception) {
                android.util.Log.w("GalaxySSISchedule", "Schedule wake failed; persisted work remains recoverable", error)
            } finally { pending.finish() }
        }
    }
    private companion object { val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO) }
}

object AgentProactiveTaskExecutor {
    private val teamScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val activeTeamRuns = ConcurrentHashMap.newKeySet<String>()
    private val activeTeamHandles = ConcurrentHashMap<String, AgentTeamExecutionHandle>()
    private val activeTeamControllers = ConcurrentHashMap<String, AgentProductionTeamController>()

    fun execute(context: Context, runId: String) {
        if (runId in activeTeamRuns) return
        val store = AgentProactiveTaskStore(context)
        val run = store.run(runId)?.takeIf { !it.status.terminal } ?: return
        val task = store.task(run.taskId)?.takeIf { it.enabled } ?: run {
            store.upsertRun(
                run.copy(
                    status = AgentProactiveRunStatus.CANCELLED,
                    completedAtMillis = System.currentTimeMillis(),
                    errorCode = "task_disabled"
                )
            )
            return
        }
        if (task.action.conversationId.isNotBlank() && AgentTranscriptStore(context).conversation(task.action.conversationId) == null) {
            ConversationScheduledTasks.setEnabled(context, task.taskId, false)
            return
        }
        if (task.action.conversationId.isNotBlank() && run.teamRunId.isBlank() &&
            JSONObject(run.causeJson).optInt("task_revision", task.revision) != task.revision) {
            store.upsertRun(run.copy(status = AgentProactiveRunStatus.CANCELLED,
                completedAtMillis = System.currentTimeMillis(), errorCode = "schedule_updated"))
            return
        }
        // An explicit user schedule is independent work, not opportunistic background learning.
        // Actual phone actions still go through PhoneExecutionAuthority and its resource locks.
        if (task.action.conversationId.isBlank() && foregroundTurnBlocksBackground(context)) {
            updatePendingRun(store, task,
                run.copy(
                    status = AgentProactiveRunStatus.WAITING,
                    resultSummary = "Waiting for foreground chat"
                )
            )
            scheduleWake(
                context,
                run.runId,
                System.currentTimeMillis() + FOREGROUND_RECHECK_MILLIS
            )
            return
        }
        if (!constraintsSatisfied(context, task.policy)) {
            updatePendingRun(store, task,
                run.copy(
                    status = AgentProactiveRunStatus.WAITING,
                    resultSummary = "Waiting for task constraints"
                )
            )
            scheduleWake(context, run.runId, System.currentTimeMillis() + CONSTRAINT_RECHECK_MILLIS)
            return
        }
        val activeForTask = store.runs(task.taskId, limit = 1_000).count { candidate ->
            candidate.runId != run.runId && (
                candidate.status == AgentProactiveRunStatus.RUNNING ||
                    candidate.status == AgentProactiveRunStatus.WAITING &&
                    candidate.linkedExecutionId.isNotBlank()
                )
        }
        if (activeForTask >= task.policy.maxConcurrency) {
            updatePendingRun(store, task,
                run.copy(
                    status = AgentProactiveRunStatus.WAITING,
                    resultSummary = "Waiting for an execution slot"
                )
            )
            scheduleWake(context, run.runId, System.currentTimeMillis() + CONCURRENCY_RECHECK_MILLIS)
            return
        }
        val running = run.copy(
            status = if (run.attempt > 1) AgentProactiveRunStatus.RETRYING else AgentProactiveRunStatus.RUNNING,
            startedAtMillis = run.startedAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
        )
        if (task.action.conversationId.isNotBlank()) {
            if (!store.updateScheduledPendingRun(running)) return
        } else store.upsertRun(running)
        when (task.action.kind) {
            AgentProactiveActionKind.SUBAGENT_TEAM -> executeTeam(context, store, task, running)
            AgentProactiveActionKind.NATIVE_TOOL -> executeNativeTool(context, store, task, running)
            AgentProactiveActionKind.AGENT -> executeSingleAgent(context, store, task, running)
            AgentProactiveActionKind.WORKFLOW -> executeWorkflowGoal(context, store, task, running)
        }
    }

    fun cancel(context: Context, runId: String): Boolean {
        val store = AgentProactiveTaskStore(context)
        val run = store.run(runId)?.takeIf { !it.status.terminal } ?: return false
        val now = System.currentTimeMillis()
        val scheduled = store.task(run.taskId)?.action?.conversationId?.isNotBlank() == true
        val cancelled = run.copy(status = AgentProactiveRunStatus.CANCELLED, completedAtMillis = now,
            errorCode = "cancelled", resultSummary = "Proactive task cancelled", deliveryRecorded = true)
        if (scheduled && !store.completeScheduledRun(cancelled)) return false
        activeTeamHandles.remove(runId)?.cancel("Proactive task cancelled")
        if (run.teamRunId.isNotBlank()) {
            activeTeamControllers[runId]?.cancel(run.teamRunId)
                ?: AgentTeamDurableControl(context).set(run.teamRunId, AgentTeamUserControl.STOP)
        }
        if (run.linkedExecutionId.isNotBlank()) {
            runCatching { MobileNativeAgent(context).cancelCurrentTask() }
        }
        if (scheduled) return true
        store.upsertRun(
            run.copy(
                status = AgentProactiveRunStatus.CANCELLED,
                completedAtMillis = now,
                errorCode = "cancelled",
                resultSummary = "Proactive task cancelled"
            )
        )
        AgentProactiveTaskScheduler.recordOutcome(
            store,
            run.taskId,
            AgentProactiveRunStatus.CANCELLED,
            now
        )
        return true
    }

    private fun updatePendingRun(store: AgentProactiveTaskStore, task: AgentProactiveTask, run: AgentProactiveRun) {
        if (task.action.conversationId.isNotBlank()) store.updateScheduledPendingRun(run)
        else store.upsertRun(run)
    }

    private fun executeWorkflowGoal(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun
    ) {
        val goal = SharedPreferencesAgentWorkflowStore(context).findById(task.action.targetId)?.goal
            ?: return failOrRetry(context, store, task, run, "workflow_not_found", "Workflow is missing")
        val executionStore = AgentWorkflowExecutionHistoryStore(context)
        val execution = AgentWorkflowExecutionRecord(
            workflowId = task.taskId,
            workflowName = task.name,
            source = AgentWorkflowExecutionSource.PROACTIVE,
            status = AgentWorkflowExecutionStatus.RUNNING
        )
        executionStore.upsert(execution)
        val agent = MobileNativeAgent(context)
        agent.attachWorkflowExecution(execution.id)
        val state = runCatching {
            agent.submitGoal(goalCheckpointPrompt(task, goal))
        }.getOrElse { error ->
            return failOrRetry(
                context,
                store,
                task,
                run,
                "agent_execution_failed",
                error.message.orEmpty()
            )
        }
        val status = when (state.phase) {
            AgentPhase.COMPLETED -> AgentProactiveRunStatus.COMPLETED
            AgentPhase.FAILED, AgentPhase.BLOCKED -> AgentProactiveRunStatus.FAILED
            AgentPhase.CANCELLED -> AgentProactiveRunStatus.CANCELLED
            else -> AgentProactiveRunStatus.WAITING
        }
        val now = System.currentTimeMillis()
        val summary = state.lastActionResult?.message.orEmpty()
        val linkedRun = run.copy(linkedExecutionId = execution.id)
        when (status) {
            AgentProactiveRunStatus.COMPLETED ->
                finishCompleted(context, store, task, linkedRun, summary)
            AgentProactiveRunStatus.FAILED ->
                failOrRetry(context, store, task, linkedRun, "workflow_failed", summary)
            AgentProactiveRunStatus.CANCELLED -> {
                store.upsertRun(
                    linkedRun.copy(
                        status = status,
                        completedAtMillis = now,
                        resultSummary = summary.take(4_096)
                    )
                )
                AgentProactiveTaskScheduler.recordOutcome(store, task.taskId, status, now)
            }
            else -> store.upsertRun(
                linkedRun.copy(
                    status = status,
                    completedAtMillis = 0L,
                    resultSummary = summary.take(4_096)
                )
            )
        }
    }

    private fun executeSingleAgent(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun
    ) {
        val scheduled = task.action.conversationId.isNotBlank()
        if (scheduled && run.teamRunId.isBlank()) {
            val local = runCatching { ConversationScheduleExecution.localAction(context, task) }
                .getOrElse { return failOrRetry(context, store, task, run, "local_route_failed", it.message.orEmpty()) }
            if (local != null) {
                if (!activeTeamRuns.add(run.runId)) return
                try {
                    val outcome = runCatching { ConversationScheduleExecution.executeLocal(context, task, run, local) }
                        .getOrElse { ConversationScheduleOutcome(AgentProactiveRunStatus.FAILED,
                            it.message.orEmpty(), "local_execution_failed") }
                    android.util.Log.i("GalaxySSISchedule", "Local occurrence=${run.runId} status=${outcome.status} error=${outcome.errorCode}")
                    finishScheduledOutcome(context, store, task, run, outcome)
                } finally { activeTeamRuns.remove(run.runId) }
                return
            }
        }
        val resolved = if (scheduled) runCatching { ConversationScheduledTasks.resolve(context, task) }.getOrElse {
            return failOrRetry(context, store, task, run, "scheduled_agent_unavailable", it.message.orEmpty())
        } else task.action.targetId to emptyMap()
        executeManagedTeam(
            context = context,
            store = store,
            task = task,
            run = run,
            definition = AgentTeamDefinition(
                teamId = if (scheduled) ConversationScheduledTasks.TEAM_PREFIX + task.taskId else task.taskId,
                primaryAgentId = resolved.first,
                members = listOf(
                    AgentTeamMember(
                        agentId = resolved.first,
                        deliveryMode = AgentDeliveryMode.RESPOND,
                        role = "lead",
                        objective = task.action.prompt,
                        context = resolved.second
                    )
                ),
                visibilityMode = AgentTeamVisibilityMode.BACKGROUND
            ),
            goal = goalCheckpointPrompt(task, if (scheduled) buildString {
                append("Execute this scheduled occurrence now, not a new schedule. Verify actual tool outcomes before claiming success. ")
                append("Report partial failures accurately; continue independent requested actions when possible.\n\n")
                append("Keep routine outcome wording stable when the verified state is unchanged; omit timestamps unless relevant.\n\n")
                append(ConversationScheduleExecution.REMOTE_CONTRACT).append("\n\n")
                append(task.action.prompt)
                append("\n\n").append(AgentTranscriptStore(context).context(
                    conversationId = task.action.conversationId).asTransportBlock(maximumTokens = 4_000))
                val prior = store.runs(task.taskId, 1_000).firstOrNull { it.runId != run.runId && it.status.terminal }
                if (prior != null) append("\n\nPrevious occurrence (context, not proof of current success):\n").append(prior.resultSummary)
            } else task.action.prompt)
        )
    }

    private fun executeNativeTool(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun
    ) {
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context.applicationContext,
            screenProvider = { AndroidScreenPerceptionProvider(context).capture() }
        )
        val input = JSONObject(task.action.argumentsJson).toNativeMap()
        val descriptor = registry.lookup(task.action.targetId)?.descriptor
        val result = registry.invoke(
            task.action.targetId,
            input,
            AgentNativeToolInvocationContext(
                invocationId = run.runId,
                sessionId = task.taskId,
                conversationId = "proactive:${task.taskId}",
                turnId = run.runId,
                callerId = "galaxyssi.mobile.proactive",
                idempotencyKey = run.runId,
                grantedPermissions = task.action.grantedPermissions +
                    descriptor?.requiredPermissions.orEmpty().filter { it.required }.map { it.id },
                grantedConsents = task.action.grantedConsents +
                    descriptor?.requiredConsents.orEmpty().filter { it.required }.map { it.id },
                attributes = mapOf(
                    "proactive_task_id" to task.taskId,
                    "permission_mode" to "full_access"
                )
            )
        )
        if (!result.isSuccess) {
            return failOrRetry(
                context,
                store,
                task,
                run,
                result.error?.code.orEmpty().ifBlank { result.status.wireValue },
                result.error?.message.orEmpty().ifBlank { result.message }
            )
        }
        finishCompleted(
            context,
            store,
            task,
            run,
            result.message.ifBlank { AgentNativeJsonCodec.stringify(result.output) }
        )
    }

    private fun executeTeam(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun
    ) {
        val lead = task.action.team.single { it.role == AgentProactiveTeamRole.LEAD }
        val members = task.action.team.map { member ->
            AgentTeamMember(
                agentId = member.agentId,
                deliveryMode = if (member.role == AgentProactiveTeamRole.LEAD) {
                    AgentDeliveryMode.RESPOND
                } else {
                    AgentDeliveryMode.OBSERVE
                },
                role = member.role.name.lowercase(),
                objective = member.instructions.ifBlank { task.action.prompt }
            )
        }
        executeManagedTeam(
            context = context,
            store = store,
            task = task,
            run = run,
            definition = AgentTeamDefinition(
                teamId = task.taskId,
                primaryAgentId = lead.agentId,
                members = members,
                visibilityMode = AgentTeamVisibilityMode.BACKGROUND
            ),
            goal = goalCheckpointPrompt(task, task.action.prompt)
        )
    }

    private fun executeManagedTeam(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun,
        definition: AgentTeamDefinition,
        goal: String
    ) {
        if (!activeTeamRuns.add(run.runId)) return
        val controller = AgentProductionTeamController(context.applicationContext)
        activeTeamControllers[run.runId] = controller
        if (task.action.conversationId.isNotBlank() && run.teamRunId.isNotBlank() &&
            controller.snapshot(run.teamRunId) != null) {
            // Reattach to the persisted execution, never start its external effects a second time.
            teamScope.launch {
                try {
                    controller.resume(run.teamRunId)
                    while (store.run(run.runId)?.status?.terminal == false) {
                        val snapshot = controller.snapshot(run.teamRunId)
                        if (snapshot?.state?.isTerminal == true && snapshot.state != AgentTeamExecutionState.INTERRUPTED) {
                            completeScheduledTeam(context, store, task, run, snapshot)
                            break
                        }
                        delay(5_000L)
                    }
                } finally { activeTeamRuns.remove(run.runId); activeTeamControllers.remove(run.runId); controller.close() }
            }
            return
        }
        if (task.action.conversationId.isNotBlank()) {
            val current = store.task(task.taskId)
            if (current?.enabled != true || store.run(run.runId)?.status?.terminal == true) {
                activeTeamRuns.remove(run.runId); activeTeamControllers.remove(run.runId); controller.close()
                return
            }
            if (!store.updateScheduledPendingRun(run.copy(teamRunId = run.runId))) {
                activeTeamRuns.remove(run.runId); activeTeamControllers.remove(run.runId); controller.close()
                return
            }
        }
        val handle = runCatching {
            controller.start(
                definition,
                AgentRunRequest(
                    conversationId = "proactive:${task.taskId}",
                    messageId = run.runId,
                    taskId = if (task.action.conversationId.isNotBlank()) run.runId else task.taskId,
                    runId = run.runId,
                    goal = goal,
                    context = mapOf(
                        "proactive_task_id" to task.taskId,
                        "proactive_trigger" to task.trigger.kind.name.lowercase(),
                        "proactive_cause" to run.causeJson
                    ),
                    idempotencyKey = run.runId,
                    deliveryMode = AgentDeliveryMode.RESPOND
                )
            )
        }.getOrElse { error ->
            activeTeamRuns.remove(run.runId)
            activeTeamControllers.remove(run.runId)
            controller.close()
            return failOrRetry(
                context,
                store,
                task,
                run,
                "team_start_failed",
                error.message.orEmpty()
            )
        }
        activeTeamHandles[run.runId] = handle
        if (store.run(run.runId)?.status == AgentProactiveRunStatus.CANCELLED || store.task(task.taskId)?.enabled != true) {
            controller.cancel(handle.supervisorRunId)
        } else if (task.action.conversationId.isNotBlank()) {
            if (!store.updateScheduledPendingRun(run.copy(teamRunId = handle.supervisorRunId)))
                controller.cancel(handle.supervisorRunId)
        } else store.upsertRun(run.copy(teamRunId = handle.supervisorRunId))
        teamScope.launch {
            try {
                val result = handle.await()
                if (store.run(run.runId)?.status == AgentProactiveRunStatus.CANCELLED) return@launch
                if (task.action.conversationId.isNotBlank()) {
                    completeScheduledTeam(context, store, task, run.copy(teamRunId = handle.supervisorRunId), result.snapshot)
                    return@launch
                }
                val status = when (result.snapshot.state) {
                    AgentTeamExecutionState.SUCCEEDED,
                    AgentTeamExecutionState.COMPLETED_WITH_FAILURES ->
                        AgentProactiveRunStatus.COMPLETED
                    AgentTeamExecutionState.CANCELLED -> AgentProactiveRunStatus.CANCELLED
                    else -> AgentProactiveRunStatus.FAILED
                }
                val finishedRun = run.copy(teamRunId = handle.supervisorRunId,
                    resultRichOutputJson = result.snapshot.finalRichOutputJson)
                when (status) {
                    AgentProactiveRunStatus.COMPLETED ->
                        finishCompleted(context, store, task, finishedRun, result.finalOutput)
                    AgentProactiveRunStatus.CANCELLED -> {
                        val now = System.currentTimeMillis()
                        store.upsertRun(
                            finishedRun.copy(
                                status = status,
                                completedAtMillis = now,
                                resultSummary = result.finalOutput.take(4_096)
                            )
                        )
                        AgentProactiveTaskScheduler.recordOutcome(store, task.taskId, status, now)
                    }
                    else -> failOrRetry(
                        context,
                        store,
                        task,
                        finishedRun,
                        "team_execution_failed",
                        result.finalOutput
                    )
                }
            } catch (error: Throwable) {
                failOrRetry(
                    context,
                    store,
                    task,
                    run,
                    "team_execution_failed",
                    error.message.orEmpty()
                )
            } finally {
                activeTeamHandles.remove(run.runId)
                activeTeamRuns.remove(run.runId)
                activeTeamControllers.remove(run.runId)
                controller.close()
            }
        }
    }

    internal fun finalizeReconciled(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask?,
        run: AgentProactiveRun
    ) {
        val currentTask = task ?: return
        if (run.status == AgentProactiveRunStatus.COMPLETED) {
            finishCompleted(context, store, currentTask, run, run.resultSummary)
        } else {
            AgentProactiveTaskScheduler.recordOutcome(
                store,
                currentTask.taskId,
                run.status,
                run.completedAtMillis.takeIf { it > 0L } ?: System.currentTimeMillis()
            )
        }
    }

    private fun completeScheduledTeam(context: Context, store: AgentProactiveTaskStore,
        task: AgentProactiveTask, run: AgentProactiveRun, snapshot: AgentTeamExecutionSnapshot) {
        if (snapshot.state == AgentTeamExecutionState.CANCELLED) {
            store.completeScheduledRun(run.copy(status = AgentProactiveRunStatus.CANCELLED,
                completedAtMillis = System.currentTimeMillis(), deliveryRecorded = true))
            return
        }
        val output = snapshot.finalOutput.ifBlank {
            snapshot.members.firstNotNullOfOrNull { it.errorMessage.takeIf(String::isNotBlank) }.orEmpty()
        }
        val outcome = ConversationScheduleExecution.remoteOutcome(output, snapshot.state == AgentTeamExecutionState.SUCCEEDED,
            ConversationScheduleExecution.expectsPhone(task.action.prompt))
        finishScheduledOutcome(context, store, task, run.copy(resultRichOutputJson =
            ConversationScheduleExecution.remoteRichOutput(snapshot.finalRichOutputJson, outcome.summary)), outcome)
    }

    private fun finishScheduledOutcome(context: Context, store: AgentProactiveTaskStore,
        task: AgentProactiveTask, run: AgentProactiveRun, outcome: ConversationScheduleOutcome) {
        val finished = run.copy(status = outcome.status, completedAtMillis = System.currentTimeMillis(),
            resultSummary = outcome.summary.take(65_536), errorCode = outcome.errorCode)
        if (store.completeScheduledRun(finished) && ConversationScheduledTasks.deliver(context, task, finished))
            AgentProactiveTaskNotifier.deliver(context, task, finished.resultSummary,
                outcome.status != AgentProactiveRunStatus.COMPLETED)
    }

    @Synchronized
    private fun finishCompleted(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun,
        rawSummary: String
    ) {
        if (store.run(run.runId)?.status == AgentProactiveRunStatus.CANCELLED) return
        val now = System.currentTimeMillis()
        if (task.action.conversationId.isNotBlank()) {
            val completed = run.copy(status = AgentProactiveRunStatus.COMPLETED, completedAtMillis = now,
                resultSummary = rawSummary.trim().take(65_536), errorCode = "")
            if (store.completeScheduledRun(completed) && ConversationScheduledTasks.deliver(context, task, completed))
                AgentProactiveTaskNotifier.deliver(context, task, completed.resultSummary, false)
            return
        }
        val goalState = if (task.trigger.kind == AgentProactiveTriggerKind.GOAL_CHECKPOINT) {
            goalState(rawSummary)
        } else ""
        val summary = stripGoalState(rawSummary).take(4_096)
        store.upsertRun(
            run.copy(
                status = AgentProactiveRunStatus.COMPLETED,
                completedAtMillis = now,
                resultSummary = summary,
                errorCode = ""
            )
        )
        AgentProactiveTaskScheduler.recordOutcome(
            store,
            task.taskId,
            AgentProactiveRunStatus.COMPLETED,
            now
        )
        if (goalState == "complete") {
            store.task(task.taskId)?.let { current ->
                AgentProactiveTaskScheduler.save(
                    context,
                    current.copy(enabled = false, nextRunAtMillis = 0L)
                )
            }
        }
        if (ConversationScheduledTasks.deliver(context, task, requireNotNull(store.run(run.runId))))
            AgentProactiveTaskNotifier.deliver(context, task, summary, failed = false)
    }

    private fun goalCheckpointPrompt(task: AgentProactiveTask, prompt: String): String {
        if (task.trigger.kind != AgentProactiveTriggerKind.GOAL_CHECKPOINT) return prompt
        return buildString {
            append(prompt.trim())
            append("\n\nEnd with exactly one machine-readable line: ")
            append("GALAXYSSI_GOAL_STATUS: complete, continue, or blocked.")
        }
    }

    private fun goalState(value: String): String {
        val lowered = value.lowercase(Locale.ROOT)
        return listOf("complete", "continue", "blocked").firstOrNull {
            "galaxyssi_goal_status: $it" in lowered
        } ?: "continue"
    }

    private fun stripGoalState(value: String): String = value.lineSequence()
        .filterNot { it.trim().startsWith("GALAXYSSI_GOAL_STATUS:", ignoreCase = true) }
        .joinToString("\n")
        .trim()

    @Synchronized
    private fun failOrRetry(
        context: Context,
        store: AgentProactiveTaskStore,
        task: AgentProactiveTask,
        run: AgentProactiveRun,
        errorCode: String,
        message: String
    ) {
        if (store.run(run.runId)?.status?.terminal == true) return
        val now = System.currentTimeMillis()
        if (run.attempt < task.policy.maxAttempts &&
            (task.action.conversationId.isBlank() || store.run(run.runId)?.teamRunId.isNullOrBlank())) {
            val retry = run.copy(
                status = AgentProactiveRunStatus.RETRYING,
                attempt = run.attempt + 1,
                errorCode = errorCode.take(128),
                resultSummary = message.take(4_096)
            )
            updatePendingRun(store, task, retry)
            val delaySeconds = task.policy.retryBackoffSeconds *
                (1L shl (run.attempt - 1).coerceIn(0, 20))
            scheduleWake(context, retry.runId, now + delaySeconds * 1_000L)
            return
        }
        if (task.action.conversationId.isNotBlank()) {
            val failed = (store.run(run.runId) ?: run).copy(status = AgentProactiveRunStatus.FAILED,
                completedAtMillis = now, errorCode = errorCode, resultSummary = message.ifBlank { errorCode }.take(65_536))
            if (store.completeScheduledRun(failed) && ConversationScheduledTasks.deliver(context, task, failed))
                AgentProactiveTaskNotifier.deliver(context, task, failed.resultSummary, true)
            return
        }
        store.upsertRun(
            run.copy(
                status = AgentProactiveRunStatus.FAILED,
                completedAtMillis = now,
                errorCode = errorCode.take(128),
                resultSummary = message.take(4_096)
            )
        )
        AgentProactiveTaskScheduler.recordOutcome(
            store,
            task.taskId,
            AgentProactiveRunStatus.FAILED,
            now
        )
        if (!ConversationScheduledTasks.deliver(context, task, requireNotNull(store.run(run.runId)))) return
        AgentProactiveTaskNotifier.deliver(
            context,
            task,
            message.ifBlank { errorCode },
            failed = true
        )
    }

    internal fun scheduleWake(context: Context, runId: String, atMillis: Long) {
        val store = AgentProactiveTaskStore(context)
        if (store.run(runId)?.let { store.task(it.taskId)?.action?.conversationId?.isNotBlank() } == true)
            AgentProactiveTaskScheduler.wakeRunWhileAwake(context, runId, atMillis)
        val pending = PendingIntent.getBroadcast(
            context,
            runId.hashCode(),
            Intent(context, AgentProactiveAlarmReceiver::class.java)
                .setAction(AgentProactiveTaskScheduler.ACTION_RUN)
                .putExtra(AgentProactiveTaskScheduler.EXTRA_RUN_ID, runId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        context.getSystemService(AlarmManager::class.java).setWindow(
            AlarmManager.RTC_WAKEUP,
            atMillis,
            30_000L,
            pending
        )
    }

    private fun constraintsSatisfied(context: Context, policy: AgentProactivePolicy): Boolean {
        if (policy.requiresCharging) {
            val battery = context.registerReceiver(
                null,
                android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            if (status != BatteryManager.BATTERY_STATUS_CHARGING &&
                status != BatteryManager.BATTERY_STATUS_FULL
            ) return false
        }
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val connected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        return when (policy.network) {
            "offline" -> !connected
            "unmetered" -> connected &&
                capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true
            else -> true
        }
    }

    private const val CONSTRAINT_RECHECK_MILLIS = 60_000L
    private const val CONCURRENCY_RECHECK_MILLIS = 15_000L
    private const val FOREGROUND_RECHECK_MILLIS = 1_000L

    private fun foregroundTurnBlocksBackground(context: Context): Boolean {
        if (AgentForegroundWorkCoordinator.hasForegroundWork) return true
        return runCatching {
            AgentTaskRuntime.supervisor(context).recoverableTasks().any { workspace ->
                workspace.status == AgentWorkspaceStatus.WAITING_RESPONSE ||
                    workspace.status == AgentWorkspaceStatus.WAITING_CONFIRMATION
            }
        }.getOrDefault(false)
    }
}

private object AgentProactiveTaskNotifier {
    private const val CHANNEL_ID = "galaxyssi.proactive.tasks"

    fun deliver(
        baseContext: Context,
        task: AgentProactiveTask,
        summary: String,
        failed: Boolean
    ) {
        if (task.action.deliveryMode !in setOf("notify", "mobile")) return
        val context = AppLanguage.wrap(baseContext.applicationContext)
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(context, manager)
        val title = context.getString(
            R.string.automation_proactive_notification_title,
            task.name
        )
        val safeSummary = summary.trim().ifBlank { task.name }.take(4_096)
        val contentIntent = PendingIntent.getActivity(
            context,
            task.taskId.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (task.action.conversationId.isNotBlank())
                    putExtra(AgentConversationWindows.CONVERSATION, task.action.conversationId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val publicNotification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(context.getString(R.string.automation_proactive_notification_channel))
            .build()
        manager.notify(
            task.taskId.hashCode(),
            builder
                .setSmallIcon(R.drawable.ic_tab_chat_filled)
                .setContentTitle(title)
                .setContentText(safeSummary.take(160))
                .setStyle(Notification.BigTextStyle().bigText(safeSummary))
                .setContentIntent(contentIntent)
                .setPublicVersion(publicNotification)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setCategory(if (failed) Notification.CATEGORY_ERROR else Notification.CATEGORY_STATUS)
                .setOnlyAlertOnce(true)
                .setAutoCancel(true)
                .build()
        )
    }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.automation_proactive_notification_channel),
                NotificationManager.IMPORTANCE_DEFAULT
            )
        )
    }
}

private fun AgentWorkflowExecutionStatus.toProactiveStatus(): AgentProactiveRunStatus = when (this) {
    AgentWorkflowExecutionStatus.COMPLETED -> AgentProactiveRunStatus.COMPLETED
    AgentWorkflowExecutionStatus.FAILED,
    AgentWorkflowExecutionStatus.BLOCKED -> AgentProactiveRunStatus.FAILED
    AgentWorkflowExecutionStatus.CANCELLED -> AgentProactiveRunStatus.CANCELLED
    AgentWorkflowExecutionStatus.SKIPPED -> AgentProactiveRunStatus.SKIPPED
    AgentWorkflowExecutionStatus.RUNNING,
    AgentWorkflowExecutionStatus.WAITING_CONFIRMATION,
    AgentWorkflowExecutionStatus.WAITING_RESPONSE -> AgentProactiveRunStatus.WAITING
}

private fun JSONObject?.toStringMap(): Map<String, String> {
    val source = this ?: return emptyMap()
    return source.keys().asSequence().associateWith { source.opt(it)?.toString().orEmpty() }
}

private fun JSONArray?.toObjectList(): List<JSONObject> {
    val source = this ?: return emptyList()
    return buildList {
        for (index in 0 until source.length()) source.optJSONObject(index)?.let(::add)
    }
}

private fun JSONArray?.toStringSet(): Set<String> {
    val source = this ?: return emptySet()
    return buildSet {
        for (index in 0 until source.length()) {
            source.optString(index).takeIf(String::isNotBlank)?.let(::add)
        }
    }
}

private fun JSONObject.toNativeMap(): AgentNativeJsonObject =
    keys().asSequence().associateWith { key -> opt(key).toNativeValue() }

private fun Any?.toNativeValue(): Any? = when (this) {
    JSONObject.NULL, null -> null
    is JSONObject -> toNativeMap()
    is JSONArray -> buildList {
        for (index in 0 until length()) add(opt(index).toNativeValue())
    }
    is String, is Boolean, is Int, is Long, is Double -> this
    is Number -> toDouble()
    else -> toString()
}

private inline fun <reified T : Enum<T>> enumValue(value: String, default: T): T =
    runCatching { enumValueOf<T>(value) }.getOrDefault(default)

private fun requireIdentifier(value: String, label: String) {
    require(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}").matches(value)) {
        "$label is invalid"
    }
}
