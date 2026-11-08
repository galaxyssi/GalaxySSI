package com.galaxyssi.chat

import android.content.Context
import java.time.ZoneId
import java.util.UUID

/** Models decide intent; the host validates structured operations and owns durable scheduling. */
internal object AgentScheduleNativeTools {
    const val LIST = "galaxyssi.schedules.list"
    const val MANAGE = "galaxyssi.schedules.manage"
    val toolIds = setOf(LIST, MANAGE)
    const val INTENT_CONTRACT = "Models decide recurring intent; habits/questions are not schedules. " +
        "Use phone galaxyssi.schedules tools, not Desktop cron."
    const val MODEL_CONTRACT = "Recurring task intent is a semantic decision for you, not a keyword rule. " +
        "Words such as daily/every day in a question, habit or symptom report do not request automation. " +
        "Answer those normally. Only when the user asks you to arrange future repeated execution, use " +
        "galaxyssi.schedules.manage on the phone, never Desktop cron or an unrelated reminder app. " +
        "Use galaxyssi.schedules.list for this conversation's schedules and timezone; inspect the tool schema as needed. " +
        "Resolve follow-ups from conversation context; use the observed task_id and expected_revision to update, pause or resume. " +
        "If intent is genuinely ambiguous, clarify instead of creating a task. Do not claim scheduling without a successful " +
        "receipt. Creating/updating a schedule requests one immediate run followed by repetition; that receipt proves " +
        "the schedule was saved, not that its action succeeded. During a scheduled execution perform the assigned work, " +
        "do not create another schedule."

    fun definitions(context: Context): List<AgentNativeToolDefinition> = listOf(
        AgentNativeToolDefinition(
            descriptor = AgentNativeToolDescriptor(
                id = LIST, version = "1.0.0", title = "List this conversation's recurring tasks",
                description = "Read saved schedules and the phone timezone before changing a task. Returns exact IDs and revisions.",
                location = AgentNativeToolLocation.APPLICATION,
                inputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = false),
                outputSchema = AgentNativeJsonSchema.objectSchema(), risk = AgentNativeToolRisk.LOW,
                idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
                concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY, effect = AgentNativeToolEffect.READ_ONLY),
            executorId = "galaxyssi.schedules.local",
            executor = AgentNativeToolExecutor { invocation ->
                invocation.checkpoint()
                val id = invocation.context.conversationId
                if (id.isBlank()) failure("schedule_context_missing", "An originating conversation is required.")
                else AgentNativeToolExecutionResult.success(mapOf(
                    "time_zone" to ZoneId.systemDefault().id,
                    "tasks" to ConversationScheduledTasks.tasks(context, id).map(::value)), "Read saved schedules")
            }),
        AgentNativeToolDefinition(
            descriptor = AgentNativeToolDescriptor(
                id = MANAGE, version = "1.0.0", title = "Create, update, pause or resume a recurring task",
                description = MODEL_CONTRACT,
                location = AgentNativeToolLocation.APPLICATION,
                inputSchema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
                    "operation" to AgentNativeJsonSchema.string(enumValues = listOf("create", "update", "pause", "resume")),
                    "task_id" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 128,
                        description = "Observed task ID; required except for create."),
                    "expected_revision" to AgentNativeJsonSchema.integer(minimum = 1,
                        description = "Revision from list; required except for create. Refresh after a conflict."),
                    "prompt" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 65_536,
                        description = "Work to execute each time, not instructions to create another schedule."),
                    "schedule_label" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 200,
                        description = "Concise user-language description matching the structured schedule."),
                    "schedule" to AgentNativeJsonSchema.objectSchema(properties = mapOf(
                        "kind" to AgentNativeJsonSchema.string(enumValues = listOf("interval", "cron")),
                        "interval_seconds" to AgentNativeJsonSchema.integer(AgentProactiveTrigger.MIN_INTERVAL_SECONDS,
                            AgentProactiveTrigger.MAX_INTERVAL_SECONDS),
                        "cron" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 128,
                            description = "Five fields: minute hour day-of-month month day-of-week."),
                        "time_zone" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 100,
                            description = "IANA timezone; defaults to the phone timezone.")),
                        required = setOf("kind"), additionalProperties = false)),
                    required = setOf("operation"), additionalProperties = false),
                outputSchema = AgentNativeJsonSchema.objectSchema(), risk = AgentNativeToolRisk.MEDIUM,
                idempotency = AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED,
                effect = AgentNativeToolEffect.MUTATION),
            executorId = "galaxyssi.schedules.local",
            executor = AgentNativeToolExecutor { invocation ->
                invocation.checkpoint()
                apply(context, invocation.context, invocation.input)
            })
    )

    internal fun apply(context: Context, scope: AgentNativeToolInvocationContext,
        input: AgentNativeJsonObject): AgentNativeToolExecutionResult = synchronized(AgentProactiveTaskScheduler) {
        if (scope.conversationId.isBlank() || scope.turnId.isBlank()) return@synchronized failure(
            "schedule_context_missing", "An originating conversation and turn are required.")
        if (scope.conversationId.startsWith("proactive:") || scope.attributes["proactive_task_id"].orEmpty().isNotBlank())
            return@synchronized failure("nested_schedule_rejected", "Execute this occurrence instead of creating another schedule.")
        val request = try { AgentScheduleToolRequest.parse(input) } catch (error: IllegalArgumentException) {
            return@synchronized failure("invalid_schedule_arguments", error.message.orEmpty())
        }
        val store = AgentProactiveTaskStore(context)
        val existing = if (request.operation == "create") null else {
            store.task(request.taskId)?.takeIf { it.action.conversationId == scope.conversationId }
                ?: return@synchronized failure("schedule_not_found", "List this conversation's tasks and use an observed task_id.")
        }
        if (existing != null && existing.revision != request.expectedRevision) return@synchronized failure(
            "schedule_revision_conflict", "The task changed. List its latest state before deciding the next action.")
        val saved = if (request.operation in setOf("pause", "resume")) {
            requireNotNull(ConversationScheduledTasks.setEnabled(context, request.taskId, request.operation == "resume"))
        } else {
            val command = ConversationScheduleCommand(ConversationScheduleOperation.SAVE,
                prompt = request.prompt ?: requireNotNull(existing).action.prompt,
                trigger = request.trigger ?: existing?.trigger,
                scheduleText = request.label ?: requireNotNull(existing).action.scheduleText,
                createNew = request.operation == "create")
            val creationId = if (existing == null) creationId(scope, input) else null
            ConversationScheduledTasks.save(context, scope.conversationId, command, existing?.taskId, creationId)
        }
        val card = ConversationScheduledTasks.richCard(context, saved)
        AgentTranscriptStore(context).append(AgentTranscriptRole.ASSISTANT,
            AppLanguage.wrap(context).getString(when (request.operation) {
                "pause" -> R.string.schedule_stopped
                "resume" -> R.string.schedule_resumed
                "update" -> R.string.schedule_updated
                else -> R.string.schedule_saved
            }), dedupeKey = "schedule-tool:${saved.taskId}:${saved.revision}", conversationId = scope.conversationId,
            turnId = scope.turnId, taskId = saved.taskId, richOutputJson = card)
        AgentNativeToolExecutionResult.success(mapOf("task" to value(saved), "schedule_saved" to true,
            "execution_verified" to false), "Schedule state persisted; occurrence execution is reported separately")
    }

    internal fun creationId(scope: AgentNativeToolInvocationContext, input: AgentNativeJsonObject): String =
        UUID.nameUUIDFromBytes(("schedule:${scope.conversationId}:${scope.turnId}:" +
            AgentNativeJsonCodec.sha256(input)).toByteArray(Charsets.UTF_8)).toString()

    private fun value(task: AgentProactiveTask): AgentNativeJsonObject = mapOf(
        "task_id" to task.taskId, "revision" to task.revision, "enabled" to task.enabled,
        "prompt" to task.action.prompt, "schedule_label" to task.action.scheduleText,
        "schedule" to mapOf("kind" to task.trigger.kind.name.lowercase(), "cron" to task.trigger.cron,
            "interval_seconds" to task.trigger.intervalSeconds, "time_zone" to task.trigger.timeZone),
        "next_run_at_millis" to task.nextRunAtMillis, "last_status" to task.lastStatus.name.lowercase())

    private fun failure(code: String, message: String) = AgentNativeToolExecutionResult.failure(code, message,
        retryable = false, details = mapOf("schedule_changed" to false))
}

internal data class AgentScheduleToolRequest(val operation: String, val taskId: String,
    val expectedRevision: Int?, val prompt: String?, val label: String?, val trigger: AgentProactiveTrigger?) {
    companion object {
        fun parse(input: AgentNativeJsonObject): AgentScheduleToolRequest {
            val operation = input["operation"] as? String
            require(operation in setOf("create", "update", "pause", "resume")) { "operation must be create, update, pause or resume." }
            val id = input["task_id"] as? String ?: ""
            val revision = input["expected_revision"] as? Number
            if (operation != "create") {
                require(id.isNotBlank()) { "task_id is required for $operation." }
                require(revision != null && revision.toLong() in 1..Int.MAX_VALUE && revision.toDouble() == revision.toLong().toDouble()) {
                    "expected_revision must be the positive integer returned by list."
                }
            } else require(id.isEmpty() && revision == null) { "create does not accept an existing task_id or revision." }
            val prompt = input["prompt"] as? String
            val label = input["schedule_label"] as? String
            require(prompt == null || prompt.isNotBlank()) { "prompt must not be blank." }
            require(label == null || label.isNotBlank()) { "schedule_label must not be blank." }
            val schedule = input["schedule"] as? Map<*, *>
            val trigger = schedule?.let {
                val zone = it["time_zone"] as? String ?: ZoneId.systemDefault().id
                when (it["kind"]) {
                    "interval" -> {
                        require(!it.containsKey("cron")) { "interval cannot include cron." }
                        val seconds = it["interval_seconds"] as? Number
                        require(seconds != null && seconds.toDouble() == seconds.toLong().toDouble()) {
                            "interval_seconds must be an integer."
                        }
                        AgentProactiveTrigger(AgentProactiveTriggerKind.INTERVAL, timeZone = zone, intervalSeconds = seconds.toLong())
                    }
                    "cron" -> {
                        require(!it.containsKey("interval_seconds")) { "cron cannot include interval_seconds." }
                        AgentProactiveTrigger(AgentProactiveTriggerKind.CRON, cron = it["cron"] as? String ?: "", timeZone = zone)
                    }
                    else -> throw IllegalArgumentException("schedule.kind must be interval or cron.")
                }
            }
            if (operation == "create") require(prompt != null && label != null && trigger != null) {
                "create requires prompt, schedule_label and a structured schedule."
            }
            if (operation == "update") {
                require(prompt != null || trigger != null) { "update requires a prompt or schedule change." }
                require((trigger == null) == (label == null)) { "schedule and schedule_label must be updated together." }
            }
            if (operation in setOf("pause", "resume")) require(prompt == null && label == null && schedule == null) {
                "$operation only accepts task_id and expected_revision."
            }
            return AgentScheduleToolRequest(requireNotNull(operation), id, revision?.toInt(), prompt, label, trigger)
        }
    }
}
