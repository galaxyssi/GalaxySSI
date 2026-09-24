package com.galaxyssi.watch

internal enum class WatchConversationStatus(val animated: Boolean = false) {
    QUEUED(true), SENT(true), ACCEPTED(true), RUNNING(true), DELIVERING(true),
    STOP_REQUESTED(true), WAITING_APPROVAL, COMPLETE_UNREAD, READ, FAILED, CANCELLED;

    fun label(): Int = when (this) {
        QUEUED -> R.string.state_queued
        SENT -> R.string.state_sent
        ACCEPTED -> R.string.state_accepted
        RUNNING -> R.string.state_running
        DELIVERING -> R.string.conversation_delivering
        STOP_REQUESTED -> R.string.state_stop_requested
        WAITING_APPROVAL -> R.string.state_waiting_approval
        COMPLETE_UNREAD -> R.string.conversation_complete_unread
        READ -> R.string.conversation_read
        FAILED -> R.string.state_failed
        CANCELLED -> R.string.state_cancelled
    }

    companion object {
        fun latest(turns: List<WatchTask>): WatchTask = turns.maxBy { it.sourceId }

        fun resolve(task: WatchTask, unread: Boolean): WatchConversationStatus = when (task.state) {
            TaskState.QUEUED -> QUEUED
            TaskState.SENT -> SENT
            TaskState.ACCEPTED -> ACCEPTED
            TaskState.RUNNING -> RUNNING
            TaskState.STOP_REQUESTED -> STOP_REQUESTED
            TaskState.WAITING_APPROVAL -> WAITING_APPROVAL
            TaskState.FAILED -> FAILED
            TaskState.CANCELLED -> CANCELLED
            TaskState.COMPLETED -> when {
                task.reply.isBlank() -> DELIVERING
                unread -> COMPLETE_UNREAD
                else -> READ
            }
        }
    }
}
