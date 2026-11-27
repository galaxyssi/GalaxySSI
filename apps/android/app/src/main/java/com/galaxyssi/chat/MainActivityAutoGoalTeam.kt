package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import java.util.WeakHashMap

// One main-thread counter per composer. Even editing and retyping the same text invalidates consent.
private class TeamDraftRevision : TextWatcher {
    var value = 0L
    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { value++ }
    override fun afterTextChanged(s: Editable?) = Unit
}
private val teamDraftRevisions = WeakHashMap<EditText, TeamDraftRevision>()

private fun teamRoutes(ctx: Context, chatId: String): List<GoalRoute> {
    val selection = AgentModelSelectionSettings.selection(ctx, chatId)
    return ConversationGoalRunner.routes(ctx, chatId).filter { route ->
        route.model.isNotBlank() && (route.target == "local-llm" || route.host.isNotBlank()) &&
            (selection.mode != AgentModelSelectionMode.MANUAL ||
                route.target == selection.targetId && (selection.modelId.isBlank() || route.model == selection.modelId))
    }
}

internal fun MainActivity.handleAutoGoalTeam(chat: AgentConversation, text: String, hasExtras: Boolean): Boolean {
    val command = AutoGoalTeamCommand.parse(text) ?: return false
    val revision = teamDraftRevisions.getOrPut(agentGoalInput) {
        TeamDraftRevision().also(agentGoalInput::addTextChangedListener)
    }
    val submitted = ++revision.value
    val ctx = applicationContext
    fun inChat() = !isFinishing && !isDestroyed && !runtimePlaintextCleared && activeMainTab == PAGE_AGENT &&
        agentTranscriptStore.activeConversation().id == chat.id
    fun sameDraft() = inChat() && revision.value == submitted && agentGoalInput.text.toString().trim() == text.trim()
    fun extras() = hasExtras || agentInputAttachments.isNotEmpty() || AgentMentionText.selections(agentGoalInput.text).isNotEmpty()
    fun notice(resource: Int) {
        if (sameDraft()) AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_title)
            .setMessage(resource).setPositiveButton(android.R.string.ok, null).show()
    }
    fun ready(): Boolean {
        if (!sameDraft()) return false
        if (!extras()) return true
        notice(R.string.auto_goal_team_extras)
        return false
    }
    fun background(block: () -> Unit) {
        agentSubmissionExecutor.execute {
            try { block() } catch (_: Exception) {
                runOnUiThread { notice(R.string.auto_goal_team_error) }
            }
        }
    }
    fun completed(changed: Boolean, unchanged: Int) = runOnUiThread {
        if (!changed) notice(unchanged) else {
            if (sameDraft() && !extras()) agentGoalInput.setText("")
            if (inChat() && agentRenderedConversationId == chat.id) refreshAgentTranscriptWindow(chat.id)
        }
    }

    if (!ready()) return true
    when (command) {
        AutoGoalTeamCommand.Help -> notice(R.string.auto_goal_team_help)
        AutoGoalTeamCommand.TooLong -> notice(R.string.auto_goal_team_limit)
        AutoGoalTeamCommand.PrivateObjective -> notice(R.string.auto_goal_team_health)
        AutoGoalTeamCommand.Stop -> background {
            completed(AutoGoalTeamJobs.stop(ctx, chat.id), R.string.auto_goal_team_inactive)
        }
        is AutoGoalTeamCommand.Start -> background {
            fun eligibleChat() = agentTranscriptStore.conversation(chat.id)?.takeIf { ConversationGoalRunner.eligible(ctx, it) }
            if (eligibleChat() == null) {
                runOnUiThread { notice(R.string.auto_goal_team_chat) }
                return@background
            }
            if (HealthAgentLab.intent(command.objective, false) != null) {
                runOnUiThread { notice(R.string.auto_goal_team_health) }
                return@background
            }
            val routes = teamRoutes(ctx, chat.id)
            runOnUiThread {
                if (!ready()) return@runOnUiThread
                fun host(route: GoalRoute) = if (route.target == "local-llm") getString(R.string.auto_goal_team_device) else route.host
                fun confirm(route: GoalRoute) {
                    if (!ready()) return
                    AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_title)
                        .setMessage(getString(R.string.auto_goal_team_confirm, route.model, host(route), command.objective))
                        .setNegativeButton(android.R.string.cancel, null)
                        .setPositiveButton(R.string.auto_goal_team_run) { _, _ ->
                            if (ready()) background dispatch@{
                                val current = eligibleChat()
                                if (current == null) {
                                    runOnUiThread { notice(R.string.auto_goal_team_chat) }
                                    return@dispatch
                                }
                                // Compare the endpoint fingerprint too, not just the displayed model/host.
                                if (route !in teamRoutes(ctx, chat.id)) {
                                    runOnUiThread { notice(R.string.auto_goal_team_route_changed) }
                                    return@dispatch
                                }
                                completed(AutoGoalTeamJobs.start(ctx, current, command.objective, route), R.string.auto_goal_team_active)
                            }
                        }.show()
                }
                when (routes.size) {
                    0 -> notice(R.string.auto_goal_team_no_route)
                    1 -> confirm(routes.single())
                    else -> AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_choose)
                        .setItems(routes.map { getString(R.string.auto_goal_team_route, it.model, host(it)) }.toTypedArray()) { _, i ->
                            confirm(routes[i])
                        }.setNegativeButton(android.R.string.cancel, null).show()
                }
            }
        }
    }
    return true
}
