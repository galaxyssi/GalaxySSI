package com.galaxyssi.chat

import android.content.Context

/** Old chat-prefix parsing was not evidence that a user requested recurring execution. */
internal object ConversationScheduleProvenance {
    const val EDITOR = "editor"
    const val MODEL_TOOL = "model_tool"
    const val REVIEW = "legacy_review_required"

    fun requiresReview(task: AgentProactiveTask): Boolean = task.action.scheduleOrigin == REVIEW

    fun reconcile(context: Context, task: AgentProactiveTask): AgentProactiveTask =
        synchronized(AgentProactiveTaskScheduler) {
            val store = AgentProactiveTaskStore(context)
            val current = store.task(task.taskId) ?: return@synchronized task.copy(enabled = false)
            if (current.action.conversationId.isBlank() || current.action.scheduleOrigin.isNotBlank()) return@synchronized current
            val transcript = AgentTranscriptStore(context)
            val origin = savedOrigin(transcript, current)
            val classified = current.copy(action = current.action.copy(scheduleOrigin = origin))
            if (origin != REVIEW) {
                store.upsert(classified)
                return@synchronized classified
            }
            // Persist the disabled state before cancelling alarms, runs, or late deliveries.
            store.upsert(classified.copy(enabled = false, nextRunAtMillis = 0L, revision = current.revision + 1))
            val paused = requireNotNull(ConversationScheduledTasks.setEnabled(context, current.taskId, false))
            transcript.refreshScheduledMessagePreview(current.action.conversationId)
            paused
        }

    private fun savedOrigin(transcript: AgentTranscriptStore, task: AgentProactiveTask): String {
        var before: Long? = null
        do {
            val page = transcript.page(task.action.conversationId, before, pageSize = 50)
            for (entry in page.entries.asReversed()) {
                val origin = receiptOrigin(task, entry) ?: continue
                return origin
            }
            before = page.nextBeforeSequence
        } while (page.hasMore && before != null)
        return REVIEW
    }

    internal fun receiptOrigin(task: AgentProactiveTask, entry: AgentTranscriptEntry): String? {
        if (entry.role != AgentTranscriptRole.ASSISTANT || entry.conversationId != task.action.conversationId) return null
        val origin = when {
            entry.dedupeKey.startsWith("schedule-editor:") -> EDITOR
            entry.dedupeKey.startsWith("schedule-tool:${task.taskId}:") -> MODEL_TOOL
            else -> return null
        }
        return origin.takeIf {
            AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
                block.title == task.name && (block.text == task.action.scheduleText ||
                    block.text.startsWith(task.action.scheduleText + " · ")) &&
                    block.actions.any { it.verb == "edit_scheduled_task" && it.value == task.taskId }
            }
        }
    }

    fun previewText(context: Context, entry: AgentTranscriptEntry): String {
        if (entry.role != AgentTranscriptRole.ASSISTANT ||
            !entry.dedupeKey.startsWith(ConversationScheduledReplyPolicy.RESULT_PREFIX)) return entry.text
        val store = AgentProactiveTaskStore(context)
        val run = store.run(entry.dedupeKey.removePrefix(ConversationScheduledReplyPolicy.RESULT_PREFIX)) ?: return entry.text
        val task = store.task(run.taskId) ?: return entry.text
        if (task.action.conversationId != entry.conversationId || !requiresReview(task)) return entry.text
        // Only the list preview changes. The original delivery label and answer remain in history.
        return entry.text.substringAfter("\n\n", entry.text)
    }
}
