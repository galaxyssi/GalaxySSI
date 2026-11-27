package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context

// Only turn IDs cross threads; the original text and dialog belong to the submitting window.
internal class TeamReviewDraft {
    @Volatile var revision = 0L
        private set
    @Volatile var modelTurn: Pair<String, String>? = null
        private set
    var dialog: AlertDialog? = null

    fun invalidate() {
        revision++
        modelTurn = null
        dialog?.dismiss()
        dialog = null
    }

    fun bind(revisionAtSend: Long, chat: String, turn: String) {
        if (revision == revisionAtSend) modelTurn = chat to turn
    }

    fun claim(chat: String, turn: String): Boolean {
        if (modelTurn != (chat to turn)) return false
        modelTurn = null
        return true
    }
}

internal fun eligibleTeamRoutes(selection: AgentModelSelection, routes: List<GoalRoute>): List<GoalRoute> =
    routes.filter { route ->
        route.model.isNotBlank() && (route.target == "local-llm" || route.host.isNotBlank()) &&
            (selection.mode != AgentModelSelectionMode.MANUAL ||
                route.target == selection.targetId && (selection.modelId.isBlank() || route.model == selection.modelId))
    }

private fun teamRoutes(ctx: Context, chatId: String) = eligibleTeamRoutes(
    AgentModelSelectionSettings.selection(ctx, chatId), ConversationGoalRunner.routes(ctx, chatId))

internal fun allowsModelTeamTurn(chat: AgentConversation, goal: String, hasAttachments: Boolean, grouped: Boolean) =
    !hasAttachments && !grouped && chat.globalTopicKey.isEmpty() && !chat.privateMode && !chat.trackingPaused &&
        chat.status == AgentConversationStatus.ACTIVE && chat.mergedIntoConversationId.isEmpty() &&
        AutoGoalTeamCommand.allowsModelReview(goal)

internal fun MainActivity.handleAutoGoalTeam(chat: AgentConversation, text: String, hasExtras: Boolean): Boolean {
    val command = AutoGoalTeamCommand.parse(text) ?: return false
    reviewAutoGoalTeam(chat, command, text, hasExtras, fromModel = false)
    return true
}

internal fun MainActivity.offerModelTeamReview(chatId: String, turn: String) {
    if (!conversationWindow.teamReview.claim(chatId, turn)) return
    val chat = agentTranscriptStore.activeConversation()
    val text = agentTurnGoals[turn] ?: return
    if (chat.id != chatId || !AutoGoalTeamCommand.allowsModelReview(text)) return
    reviewAutoGoalTeam(chat, AutoGoalTeamCommand.Start(text), "", hasExtras = false, fromModel = true, sourceTurn = turn)
}

private fun MainActivity.reviewAutoGoalTeam(chat: AgentConversation, command: AutoGoalTeamCommand,
    draftText: String, hasExtras: Boolean, fromModel: Boolean, sourceTurn: String? = null) {
    val draft = conversationWindow.teamReview
    val submitted = draft.revision
    val ctx = applicationContext
    fun modelWindowValid() = !fromModel || (draft.revision == submitted &&
        getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == false)
    fun inChat() = !isFinishing && !isDestroyed && !runtimePlaintextCleared && activeMainTab == PAGE_AGENT &&
        agentTranscriptStore.activeConversation().id == chat.id &&
        (!fromModel || conversationWindow.visible && modelWindowValid())
    fun sameDraft() = inChat() && draft.revision == submitted && agentGoalInput.text.toString().trim() == draftText.trim()
    fun extras() = hasExtras || agentInputAttachments.isNotEmpty() || AgentMentionText.selections(agentGoalInput.text).isNotEmpty()
    fun show(builder: AlertDialog.Builder) {
        val dialog = builder.create()
        if (fromModel) {
            draft.dialog = dialog
            dialog.setOnDismissListener { if (draft.dialog === dialog) draft.dialog = null }
        }
        dialog.show()
    }
    fun notice(resource: Int) {
        if (sameDraft()) show(AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_title)
            .setMessage(resource).setPositiveButton(android.R.string.ok, null))
    }
    fun ready(): Boolean {
        if (!sameDraft()) return false
        if (!extras()) return true
        if (!fromModel) notice(R.string.auto_goal_team_extras)
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
            if (!fromModel && sameDraft() && !extras()) agentGoalInput.setText("")
            if (inChat() && agentRenderedConversationId == chat.id) refreshAgentTranscriptWindow(chat.id)
        }
    }

    if (!ready()) return
    when (command) {
        AutoGoalTeamCommand.Help -> notice(R.string.auto_goal_team_help)
        AutoGoalTeamCommand.TooLong -> notice(R.string.auto_goal_team_limit)
        AutoGoalTeamCommand.PrivateObjective -> notice(R.string.auto_goal_team_health)
        AutoGoalTeamCommand.Stop -> background {
            completed(AutoGoalTeamJobs.stop(ctx, chat.id), R.string.auto_goal_team_inactive)
        }
        is AutoGoalTeamCommand.Start -> background {
            fun eligibleChat() = agentTranscriptStore.conversation(chat.id)?.takeIf {
                (!fromModel || !it.trackingPaused) && ConversationGoalRunner.eligible(ctx, it)
            }
            if (eligibleChat() == null) {
                if (!fromModel) runOnUiThread { notice(R.string.auto_goal_team_chat) }
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
                    show(AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_title)
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
                                if (!modelWindowValid()) return@dispatch
                                completed(AutoGoalTeamJobs.start(ctx, current, command.objective, route, sourceTurn), R.string.auto_goal_team_active)
                            }
                        })
                }
                when (routes.size) {
                    0 -> if (!fromModel) notice(R.string.auto_goal_team_no_route) else Unit
                    1 -> confirm(routes.single())
                    else -> show(AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_choose)
                        .setItems(routes.map { getString(R.string.auto_goal_team_route, it.model, host(it)) }.toTypedArray()) { _, i ->
                            confirm(routes[i])
                        }.setNegativeButton(android.R.string.cancel, null))
                }
            }
        }
    }
}
