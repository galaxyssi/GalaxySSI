package com.galaxyssi.chat

import android.app.AlertDialog
import android.graphics.Color
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import java.util.UUID

internal fun MainActivity.showScheduledTasksPage() {
    showFeaturePage(getString(R.string.schedule_title))
    val marker = Any()
    featureContent.tag = marker
    featureContent.setPadding(0, 0, 0, dp(24))
    findViewById<TextView>(R.id.featureAction).apply {
        text = "+"
        textSize = 28f
        visibility = View.VISIBLE
        contentDescription = getString(R.string.schedule_new)
        setOnClickListener { showScheduledTaskEditor() }
    }
    navigationContentExecutor.execute {
        val tasks = ConversationScheduledTasks.tasks(applicationContext)
        runOnUiThread {
            if (isDestroyed || featureContent.tag !== marker) return@runOnUiThread
            if (tasks.isEmpty()) featureContent.addView(TextView(this).apply {
                text = getString(R.string.schedule_empty)
                setTextColor(getColorCompat(R.color.text_secondary))
                gravity = Gravity.CENTER
                setPadding(dp(24), dp(48), dp(24), dp(48))
            })
            tasks.forEach { task ->
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    minimumHeight = dp(88)
                    setPadding(dp(20), dp(14), dp(8), dp(14))
                }
                row.addView(LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(TextView(this@showScheduledTasksPage).apply {
                        text = task.name; textSize = 16f; maxLines = 2
                        setTextColor(getColorCompat(R.color.text_primary))
                    })
                    addView(TextView(this@showScheduledTasksPage).apply {
                        text = task.action.scheduleText
                        textSize = 13f; setPadding(0, dp(6), 0, 0)
                        setTextColor(getColorCompat(R.color.text_secondary))
                    })
                    addView(ConversationScheduleStatusView(this@showScheduledTasksPage, task.taskId).apply {
                        setPadding(0, dp(6), 0, 0)
                    })
                    setOnClickListener { hideFeaturePage(); openAgentConversation(task.action.conversationId) }
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                row.addView(ImageButton(this).apply {
                    setImageResource(R.drawable.ic_more_horizontal)
                    setBackgroundColor(Color.TRANSPARENT)
                    contentDescription = getString(R.string.schedule_edit) + " " + task.name
                    setOnClickListener { showScheduledTaskMenu(this, task) }
                }, LinearLayout.LayoutParams(dp(48), dp(48)))
                featureContent.addView(row)
                featureContent.addView(View(this).apply { setBackgroundColor(0x14777777) },
                    LinearLayout.LayoutParams(-1, dp(1)))
            }
        }
    }
}

private fun MainActivity.showScheduledTaskMenu(anchor: View, task: AgentProactiveTask) {
    PopupMenu(this, anchor).apply {
        menu.add(0, 1, 0, R.string.schedule_edit)
        menu.add(0, 2, 1, if (task.enabled) R.string.schedule_pause else R.string.schedule_resume)
        menu.add(0, 3, 2, R.string.schedule_delete)
        setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> showScheduledTaskEditor(task)
                2 -> navigationContentExecutor.execute {
                    ConversationScheduledTasks.setEnabled(applicationContext, task.taskId, !task.enabled)
                    runOnUiThread { showScheduledTasksPage() }
                }
                3 -> AlertDialog.Builder(this@showScheduledTaskMenu)
                    .setMessage(R.string.schedule_delete_confirm).setNegativeButton(android.R.string.cancel, null)
                    .setPositiveButton(R.string.schedule_delete) { _, _ -> navigationContentExecutor.execute {
                        AgentProactiveTaskScheduler.cancel(applicationContext, task.taskId)
                        runOnUiThread { showScheduledTasksPage() }
                    } }.show()
            }
            true
        }
    }.show()
}

internal fun MainActivity.editScheduledTask(taskId: String, conversationId: String) {
    navigationContentExecutor.execute {
        val task = AgentProactiveTaskStore(applicationContext).task(taskId)
            ?.takeIf { it.action.conversationId == conversationId }
        runOnUiThread {
            if (task == null) Toast.makeText(this, R.string.schedule_not_found, Toast.LENGTH_SHORT).show()
            else showScheduledTaskEditor(task, returnToList = false)
        }
    }
}

internal fun MainActivity.showScheduledTaskEditor(task: AgentProactiveTask? = null, returnToList: Boolean = true) {
    val conversationId = task?.action?.conversationId ?: agentTranscriptStore.activeConversation().id
    val content = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(8))
    }
    val prompt = EditText(this).apply {
        hint = getString(R.string.schedule_prompt); minLines = 2; maxLines = 5
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        setText(task?.action?.prompt.orEmpty())
    }
    val time = EditText(this).apply {
        hint = getString(R.string.schedule_time_hint)
        inputType = InputType.TYPE_CLASS_TEXT
        setText(task?.action?.scheduleText.orEmpty())
    }
    content.addView(prompt)
    content.addView(TextView(this).apply { text = getString(R.string.schedule_time); setPadding(0, dp(16), 0, 0) })
    content.addView(time)
    content.addView(TextView(this).apply {
        text = getString(R.string.schedule_execution_note); textSize = 12f
        setTextColor(getColorCompat(R.color.text_secondary)); setPadding(0, dp(12), 0, 0)
    })
    val dialog = AlertDialog.Builder(this).setTitle(if (task == null) R.string.schedule_new else R.string.schedule_edit)
        .setView(content).setNegativeButton(android.R.string.cancel, null).setPositiveButton(R.string.common_save, null).create()
    dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
        val label = time.text.toString().trim()
        val parsed = ConversationScheduleParser.parseTime(label)
        if (parsed == null || parsed.second != label.length) {
            time.error = getString(R.string.schedule_time_invalid); return@setOnClickListener
        }
        if (prompt.text.isNullOrBlank()) { prompt.error = getString(R.string.schedule_prompt); return@setOnClickListener }
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
        val command = ConversationScheduleCommand(ConversationScheduleOperation.SAVE,
            prompt.text.toString().trim(), parsed.first, label, createNew = task == null)
        navigationContentExecutor.execute {
            val result = runCatching {
                val saved = ConversationScheduledTasks.save(applicationContext, conversationId, command, task?.taskId)
                agentTranscriptStore.append(AgentTranscriptRole.ASSISTANT, getString(R.string.schedule_saved),
                    dedupeKey = "schedule-editor:${UUID.randomUUID()}", conversationId = conversationId,
                    richOutputJson = ConversationScheduledTasks.richCard(this, saved))
            }
            runOnUiThread {
                result.onSuccess {
                    dialog.dismiss()
                    if (returnToList) showScheduledTasksPage() else refreshAgentTranscriptWindow(conversationId)
                }.onFailure {
                    dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                    Toast.makeText(this, getString(R.string.schedule_failed, it.message.orEmpty()), Toast.LENGTH_LONG).show()
                }
            }
        }
    } }
    dialog.show()
}

internal fun MainActivity.handleConversationSchedule(goal: String, conversationId: String, turnId: String): Boolean {
    val command = ConversationScheduleParser.parse(goal) ?: return false
    val tasks = ConversationScheduledTasks.tasks(this, conversationId)
    if (!ConversationScheduleFollowupPolicy.hasExplicitTarget(goal, command)) {
        val context = agentContextBeforeTurn[turnId] ?: agentTranscriptStore.context(conversationId, excludeTurnId = turnId)
        if (!ConversationScheduleFollowupPolicy.ownsLatestResult(context, tasks.mapTo(hashSetOf()) { it.taskId })) return false
    }
    if (command.operation == ConversationScheduleOperation.SAVE && command.trigger == null && tasks.isEmpty()) return false
    if (command.operation in setOf(ConversationScheduleOperation.PAUSE, ConversationScheduleOperation.RESUME) && tasks.isEmpty()) return false
    fun apply(selected: AgentProactiveTask?) {
        agentRoutingExecutor.execute {
            val response = runCatching {
                val updated = when (command.operation) {
                    ConversationScheduleOperation.SAVE -> ConversationScheduledTasks.save(this, conversationId, command, selected?.taskId)
                    ConversationScheduleOperation.PAUSE -> ConversationScheduledTasks.setEnabled(this, requireNotNull(selected).taskId, false)
                    ConversationScheduleOperation.RESUME -> ConversationScheduledTasks.setEnabled(this, requireNotNull(selected).taskId, true)
                    ConversationScheduleOperation.LIST -> null
                }
                val message = when (command.operation) {
                    ConversationScheduleOperation.SAVE -> if (selected == null) R.string.schedule_saved else R.string.schedule_updated
                    ConversationScheduleOperation.PAUSE -> R.string.schedule_stopped
                    ConversationScheduleOperation.RESUME -> R.string.schedule_resumed
                    ConversationScheduleOperation.LIST -> R.string.schedule_open_list
                }
                getString(message) to updated?.let { ConversationScheduledTasks.richCard(this, it) }.orEmpty()
            }.getOrElse { getString(R.string.schedule_failed, it.message.orEmpty()) to "" }
            agentTranscriptStore.append(AgentTranscriptRole.ASSISTANT, response.first,
                dedupeKey = "schedule-command:$turnId", conversationId = conversationId, turnId = turnId,
                taskId = turnId, richOutputJson = response.second)
            runOnUiThread {
                pendingAgentReplyIndicators.remove(turnId)
                refreshAgentTranscriptWindow(conversationId)
                if (command.operation == ConversationScheduleOperation.LIST) showScheduledTasksPage()
            }
        }
    }
    if (command.operation == ConversationScheduleOperation.LIST || command.createNew || tasks.isEmpty()) apply(null)
    else if (tasks.size == 1) apply(tasks.single())
    else runOnUiThread {
        AlertDialog.Builder(this).setTitle(R.string.schedule_choose)
            .setItems(tasks.map { it.name }.toTypedArray()) { _, index -> apply(tasks[index]) }
            .setOnCancelListener { pendingAgentReplyIndicators.remove(turnId); refreshAgentTranscriptWindow(conversationId) }.show()
    }
    return true
}
