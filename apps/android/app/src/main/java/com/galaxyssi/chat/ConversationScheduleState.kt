package com.galaxyssi.chat

import android.content.Context
import android.widget.TextView
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import org.json.JSONObject

internal object ConversationScheduleState {
    private val listeners = CopyOnWriteArraySet<(String) -> Unit>()
    val reader = Executors.newSingleThreadExecutor()
    fun add(listener: (String) -> Unit) { listeners.add(listener) }
    fun remove(listener: (String) -> Unit) { listeners.remove(listener) }
    fun notifyChanged(taskId: String) { listeners.forEach { it(taskId) } }

    fun text(context: Context, task: AgentProactiveTask?, lastRun: AgentProactiveRun?, includeSchedule: Boolean = false): String {
        if (task == null) return context.getString(R.string.schedule_not_found)
        val frequency = task.action.scheduleText.takeIf { includeSchedule }.orEmpty()
        if (!task.enabled) return listOf(frequency, context.getString(R.string.schedule_paused))
            .filter(String::isNotBlank).joinToString(if (includeSchedule) " · " else "\n")
        if (includeSchedule) return frequency
        val run = lastRun?.takeUnless {
            it.status in setOf(AgentProactiveRunStatus.CANCELLED, AgentProactiveRunStatus.SKIPPED) ||
                it.status.terminal && JSONObject(it.causeJson).optInt("task_revision", task.revision) != task.revision
        }
        val label = context.getString(when (run?.status) {
            null -> R.string.schedule_pending
            AgentProactiveRunStatus.QUEUED -> R.string.agent_task_status_queued
            AgentProactiveRunStatus.RUNNING -> R.string.automation_run_status_running
            AgentProactiveRunStatus.RETRYING -> R.string.schedule_retrying
            AgentProactiveRunStatus.WAITING -> R.string.cc_global_status_waiting
            AgentProactiveRunStatus.COMPLETED -> R.string.automation_run_status_completed
            AgentProactiveRunStatus.UNVERIFIED -> R.string.schedule_unverified
            AgentProactiveRunStatus.FAILED -> R.string.automation_run_status_failed
            AgentProactiveRunStatus.CANCELLED -> R.string.automation_run_status_cancelled
            AgentProactiveRunStatus.SKIPPED -> R.string.automation_run_status_skipped
        })
        val state = if (run?.status?.terminal == true) context.getString(R.string.schedule_last_execution, label) else label
        val next = context.getString(R.string.schedule_next,
            DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.MEDIUM).format(Date(task.nextRunAtMillis)))
        val detail = run?.resultSummary?.takeIf { run.status in setOf(AgentProactiveRunStatus.FAILED, AgentProactiveRunStatus.UNVERIFIED) }.orEmpty()
        return listOf(frequency, state, detail.take(240), next).filter(String::isNotBlank).joinToString("\n")
    }
}

/** Updates only this status label on persisted transitions; no timer or transcript redraw. */
internal class ConversationScheduleStatusView(context: Context, private val taskId: String,
    private val includeSchedule: Boolean = false, private val cardTitle: String = "") : TextView(context) {
    private var revision = 0
    private val reload = Runnable { refresh() }
    private val listener: (String) -> Unit = { changed ->
        if (changed == taskId) { removeCallbacks(reload); post(reload) }
    }
    init {
        textSize = 13f
        setTextColor(context.getColor(R.color.text_secondary))
    }
    fun cardSpeechText(): String? = if (includeSchedule)
        ConversationScheduleCardPresentation.speechText(cardTitle, text.toString()) else null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ConversationScheduleState.add(listener)
        refresh()
    }
    override fun onDetachedFromWindow() {
        ConversationScheduleState.remove(listener)
        removeCallbacks(reload)
        revision++
        super.onDetachedFromWindow()
    }
    private fun refresh() {
        val expected = ++revision
        ConversationScheduleState.reader.execute {
            val value = runCatching {
                val store = AgentProactiveTaskStore(context.applicationContext)
                ConversationScheduleState.text(context, store.task(taskId),
                    if (includeSchedule) null else store.runs(taskId, 1).firstOrNull(), includeSchedule)
            }.getOrElse { context.getString(R.string.schedule_status_unavailable) }
            post { if (isAttachedToWindow && revision == expected && text.toString() != value) text = value }
        }
    }
}
