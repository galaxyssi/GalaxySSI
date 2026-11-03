package com.galaxyssi.chat

import android.content.Context

/** Host-owned schedules, separate from model prompts and the background learning switch. */
internal object ConversationScheduledTasks {
    const val TEAM_PREFIX = "schedule:"

    fun tasks(context: Context, conversationId: String? = null): List<AgentProactiveTask> =
        AgentProactiveTaskStore(context).tasks().filter {
            it.action.conversationId.isNotBlank() && (conversationId == null || it.action.conversationId == conversationId)
        }

    @Synchronized
    fun save(context: Context, conversationId: String, command: ConversationScheduleCommand,
        existingId: String? = null): AgentProactiveTask = synchronized(AgentProactiveTaskScheduler) {
        require(command.operation == ConversationScheduleOperation.SAVE && command.prompt.isNotBlank())
        val existing = existingId?.let { AgentProactiveTaskStore(context).task(it) }
            ?: if (existingId == null && !command.createNew) tasks(context, conversationId).singleOrNull() else null
        require(existingId == null || existing?.action?.conversationId == conversationId)
        val task = (existing ?: AgentProactiveTask(name = command.prompt.take(120),
            trigger = requireNotNull(command.trigger),
            action = AgentProactiveAction(AgentProactiveActionKind.AGENT, targetId = "conversation",
                prompt = command.prompt, deliveryMode = "notify", conversationId = conversationId),
            policy = AgentProactivePolicy(maxConsecutiveFailures = 0))).copy(
            name = command.prompt.take(120), trigger = command.trigger ?: requireNotNull(existing).trigger,
            action = (existing?.action ?: AgentProactiveAction(AgentProactiveActionKind.AGENT,
                targetId = "conversation", conversationId = conversationId, deliveryMode = "notify")).copy(
                prompt = command.prompt,
                scheduleText = command.scheduleText.ifBlank { existing?.action?.scheduleText.orEmpty() }),
            enabled = true, consecutiveFailures = 0, revision = (existing?.revision ?: 0) + 1)
        AgentProactiveTaskScheduler.save(context, task, runImmediately = true)
    }

    @Synchronized
    fun setEnabled(context: Context, taskId: String, enabled: Boolean): AgentProactiveTask? = synchronized(AgentProactiveTaskScheduler) {
        val store = AgentProactiveTaskStore(context)
        val task = store.task(taskId)?.takeIf { it.action.conversationId.isNotBlank() } ?: return@synchronized null
        val saved = AgentProactiveTaskScheduler.save(context, task.copy(enabled = enabled,
            consecutiveFailures = 0, revision = task.revision + 1))
        if (!enabled) store.runs(taskId, 1_000).filter { !it.status.terminal }.forEach {
            AgentProactiveTaskExecutor.cancel(context, it.runId)
        }
        saved
    }

    fun richCard(context: Context, task: AgentProactiveTask): String = AgentRichContentCodec.encode(listOf(
        AgentRichBlock("schedule:${task.taskId}", AgentRichBlockType.ACTIONS,
            title = task.name, text = ConversationScheduleState.text(context, task, null, includeSchedule = true),
            actions = listOf(AgentRichAction("edit", context.getString(R.string.schedule_edit),
                "edit_scheduled_task", task.taskId)))))

    fun resultShouldPublish(previous: AgentProactiveRun?, summary: String, failed: Boolean): Boolean =
        previous == null || previous.resultSummary.trim() != summary.trim() ||
            (previous.status == AgentProactiveRunStatus.FAILED) != failed

    fun deliver(context: Context, task: AgentProactiveTask, run: AgentProactiveRun): Boolean {
        val conversationId = task.action.conversationId
        if (conversationId.isBlank()) return true
        if (run.deliveryRecorded) return false
        val store = AgentProactiveTaskStore(context)
        if (run.status == AgentProactiveRunStatus.UNVERIFIED && run.errorCode in setOf(
                "foreground_observer_unavailable", "foreground_not_verified", "configuration_not_verified") &&
            run.resultRichOutputJson.isBlank()) {
            store.upsertRun(run.copy(deliveryRecorded = true))
            return false
        }
        val previous = store.runs(task.taskId, 1_000).firstOrNull {
            it.runId != run.runId && it.completedAtMillis > 0L && it.scheduledForMillis < run.scheduledForMillis &&
                it.status in setOf(AgentProactiveRunStatus.COMPLETED, AgentProactiveRunStatus.UNVERIFIED, AgentProactiveRunStatus.FAILED)
        }
        val failed = run.status == AgentProactiveRunStatus.FAILED
        if (previous?.status == run.status && !resultShouldPublish(previous, run.resultSummary, failed) && previous.resultRichOutputJson == run.resultRichOutputJson) {
            store.upsertRun(run.copy(deliveryRecorded = true))
            return false
        }
        val transcript = AgentTranscriptStore(context)
        if (transcript.conversation(conversationId) == null) {
            store.upsertRun(run.copy(deliveryRecorded = true))
            return false
        }
        val text = context.getString(if (failed) R.string.schedule_failed_result else R.string.schedule_result,
            task.name, run.resultSummary.ifBlank { context.getString(R.string.schedule_empty_result) })
        val inserted = transcript.append(AgentTranscriptRole.ASSISTANT, text,
            dedupeKey = "scheduled-result:${run.runId}", conversationId = conversationId,
            turnId = ConversationScheduledReplyPolicy.turnId(conversationId, run.runId),
            taskId = run.runId, richOutputJson = run.resultRichOutputJson)
        store.upsertRun(run.copy(deliveryRecorded = true))
        return inserted
    }

    fun isQuietLegacyStatus(context: Context, entry: AgentTranscriptEntry): Boolean {
        if (entry.role != AgentTranscriptRole.ASSISTANT || !entry.dedupeKey.startsWith("scheduled-result:") ||
            entry.richOutputJson.isNotBlank()) return false
        val name = entry.text.substringBefore("\n\n").substringAfter(" · ", "")
        if (name.isBlank()) return false
        return listOf(R.string.schedule_local_unverified, R.string.schedule_local_configuration_unverified).any {
            entry.text == context.getString(R.string.schedule_unverified_result, name, context.getString(it))
        }
    }

    fun resolve(context: Context, task: AgentProactiveTask): Pair<String, Map<String, String>> {
        val selection = AgentModelSelectionSettings.selection(context, task.action.conversationId)
        val snapshot = AppStoreAgentConnectorRegistry(context).planningSnapshot()
        val target = if (selection.mode == AgentModelSelectionMode.MANUAL) {
            requireNotNull(snapshot.targets.firstOrNull { it.id == selection.targetId }) {
                context.getString(R.string.schedule_agent_unavailable)
            }
        } else {
            val routing = AgentResourceRouter(context).route(task.action.prompt, snapshot.targets,
                snapshot.registrations, preferredTargetId = AgentStableAutoRouteStore.target(
                    context, task.action.conversationId, snapshot.targets)?.id.orEmpty())
            requireNotNull(AgentStableAutoRoutePolicy.select(snapshot.targets, routing)?.target) {
                context.getString(R.string.schedule_agent_unavailable)
            }
        }
        val configuration = if (selection.mode == AgentModelSelectionMode.MANUAL)
            AgentTargetConfiguration(selection.modelId, selection.reasoningEffort)
        else AgentModelSelectionSettings.configurationForTarget(context, task.action.conversationId, target.id)
        return target.id to mapOf("scheduled_model_id" to configuration?.modelId.orEmpty(),
            "scheduled_reasoning_effort" to (configuration?.reasoningEffort?.wireValue ?: "auto"))
    }
}
