package com.galaxyssi.chat

import android.app.AlertDialog
import androidx.work.WorkManager

internal fun MainActivity.handleConversationGoal(chat: AgentConversation, text: String, hasExtras: Boolean): Boolean {
    val command = GoalCommand.parse(text) ?: return false
    fun here() = !isDestroyed && !isFinishing && !runtimePlaintextCleared &&
        agentTranscriptStore.activeConversation().id == chat.id && agentGoalInput.text.toString().trim() == text
    fun notice(message: String) {
        if (here()) AlertDialog.Builder(this).setTitle(R.string.goal_title).setMessage(message)
            .setPositiveButton(android.R.string.ok, null).show()
    }
    fun background(block: () -> Unit) {
        agentSubmissionExecutor.execute {
            try { block() } catch (_: Exception) { runOnUiThread { notice(getString(R.string.goal_save_error)) } }
        }
    }
    if (hasExtras) { notice(getString(R.string.goal_chat_unavailable)); return true }
    val ctx = applicationContext
    background {
        if (!ConversationGoalRunner.eligible(ctx, chat)) {
            runOnUiThread { notice(getString(R.string.goal_chat_unavailable)) }; return@background
        }
        val store = ConversationGoalStore(ctx)
        val old = synchronized(ConversationGoalStore.lock) { store.get(chat.id) }
        fun details(g: ConversationGoal): String = listOf(g.objective,
            getString(R.string.goal_round, g.rounds, getString(g.phase.label())), g.route.label,
            g.checkpoints.lastOrNull()?.take(1500).orEmpty(), g.next, g.issue).filter(String::isNotBlank).joinToString("\n\n")
        fun change(make: (ConversationGoal?) -> ConversationGoal) {
            background {
                synchronized(ConversationGoalStore.lock) {
                    val actual = store.get(chat.id)
                    // A confirmation belongs to one run, not to a newer goal in the same conversation.
                    check(actual?.id == old?.id && actual?.generation == old?.generation &&
                        ConversationGoalRunner.eligible(ctx, agentTranscriptStore.conversation(chat.id)))
                    val new = make(actual)
                    if (new.phase == GoalPhase.RUNNING) ConversationGoalRunner.schedule(ctx, new)
                    store.put(new)
                    if (actual != null && actual.phase == GoalPhase.RUNNING && actual.generation != new.generation)
                        WorkManager.getInstance(ctx).cancelUniqueWork(ConversationGoalRunner.name(actual))
                    val key = "goal-command:${new.id}:${new.generation}"
                    agentTranscriptStore.append(AgentTranscriptRole.USER, text, "$key:user", conversationId = chat.id)
                    agentTranscriptStore.append(AgentTranscriptRole.ASSISTANT,
                        getString(R.string.goal_command_receipt, getString(new.phase.label()), new.route.label),
                        "$key:receipt", conversationId = chat.id)
                }
                runOnUiThread {
                    if (here()) agentGoalInput.setText("")
                    if (!isDestroyed && agentRenderedConversationId == chat.id) refreshAgentTranscriptWindow(chat.id)
                }
            }
        }
        fun confirm(route: GoalRoute, objective: String, action: () -> Unit) {
            if (here()) AlertDialog.Builder(this).setTitle(R.string.goal_title)
                .setMessage(getString(R.string.goal_confirm, objective, route.label, ConversationGoal.BUDGET))
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.goal_run) { _, _ -> if (here()) action() }.show()
        }
        when (command) {
            is GoalCommand.Start -> {
                if (old != null && !old.terminal) {
                    runOnUiThread { notice(details(old) + "\n\n" + getString(R.string.goal_existing)) }; return@background
                }
                val routes = ConversationGoalRunner.routes(ctx, chat.id)
                runOnUiThread {
                    if (!here()) return@runOnUiThread
                    fun pick(r: GoalRoute) = confirm(r, command.text) {
                        change { current ->
                            check(current == null || current.terminal)
                            ConversationGoal(chat.id, command.text, r)
                        }
                    }
                    when (routes.size) {
                        0 -> notice(getString(R.string.goal_no_provider))
                        1 -> pick(routes.single())
                        else -> AlertDialog.Builder(this).setTitle(R.string.goal_choose)
                            .setItems(routes.map(GoalRoute::label).toTypedArray()) { _, i -> pick(routes[i]) }
                            .setNegativeButton(android.R.string.cancel, null).show()
                    }
                }
            }
            is GoalCommand.Resume -> if (old != null && old.phase in setOf(GoalPhase.PAUSED, GoalPhase.BLOCKED)) {
                runOnUiThread { confirm(old.route, old.objective) {
                    change { g ->
                        checkNotNull(g); check(g.phase == GoalPhase.PAUSED || g.phase == GoalPhase.BLOCKED)
                        g.copy(phase = GoalPhase.RUNNING, generation = g.generation + 1, allowance = g.rounds + ConversationGoal.BUDGET,
                            inFlight = false, issue = "", note = command.note.ifEmpty { g.note })
                    }
                } }
            } else runOnUiThread { notice(getString(R.string.goal_not_resumable)) }
            GoalCommand.Pause, GoalCommand.Stop -> {
                if (old == null || old.terminal || command == GoalCommand.Pause && old.phase != GoalPhase.RUNNING) {
                    runOnUiThread { notice(old?.let(::details) ?: getString(R.string.goal_help)) }
                } else change { g ->
                    checkNotNull(g); check(!g.terminal && (command == GoalCommand.Stop || g.phase == GoalPhase.RUNNING))
                    g.copy(phase = if (command == GoalCommand.Pause) GoalPhase.PAUSED else GoalPhase.STOPPED,
                        generation = g.generation + 1, inFlight = false)
                }
            }
            else -> runOnUiThread { notice(listOfNotNull(old?.let(::details), getString(R.string.goal_help)).joinToString("\n\n")) }
        }
    }
    return true
}
