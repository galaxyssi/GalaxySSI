package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.widget.Toast
import java.util.UUID

internal fun MainActivity.reviewDesktopTeam(source: AgentConversation, text: String, objective: String, hasExtras: Boolean) {
    val review = conversationWindow.teamReview
    val revision = review.revision
    val selected = AgentModelSelectionSettings.selection(this, source.id)
    fun ownsDraft() = !isFinishing && !isDestroyed && !runtimePlaintextCleared && conversationWindow.visible &&
        activeMainTab == PAGE_AGENT && this !is ScreenAssistantChatActivity &&
        getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == false &&
        review.revision == revision && agentTranscriptStore.activeConversation().id == source.id &&
        agentGoalInput.text.toString().trim() == text && !initialAgentHydrationPending
    fun notice(id: Int) {
        if (!ownsDraft()) return
        if (id != R.string.desktop_team_update) {
            Toast.makeText(this, id, Toast.LENGTH_LONG).show()
            return
        }
        val dialog = AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_title).setMessage(id)
            .setPositiveButton(android.R.string.ok, null).create()
        review.dialog = dialog
        dialog.setOnDismissListener { if (review.dialog === dialog) review.dialog = null }
        dialog.show()
    }
    fun eligible(): Boolean {
        if (!ownsDraft()) return false
        if (hasExtras || agentInputAttachments.isNotEmpty() || AgentMentionText.selections(agentGoalInput.text).isNotEmpty()) {
            notice(R.string.auto_goal_team_extras); return false
        }
        if (!PinnedDesktopTeam.ordinary(agentTranscriptStore.conversation(source.id))) {
            notice(R.string.auto_goal_team_chat); return false
        }
        if (AgentModelSelectionSettings.selection(this, source.id) != selected) {
            notice(R.string.auto_goal_team_route_changed); return false
        }
        return true
    }
    if (!eligible()) return
    if (!PinnedDesktopTeam.eligibleObjective(objective)) {
        notice(R.string.auto_goal_team_health); return
    }
    fun inspect(done: (PinnedDesktopTeam.Admission) -> Unit) {
        agentSubmissionExecutor.execute {
            val admission = runCatching { PinnedDesktopTeam.inspect(applicationContext, source.id) }
                .getOrDefault(PinnedDesktopTeam.Admission())
            runOnUiThread { if (eligible()) done(admission) }
        }
    }
    inspect { admission ->
        val route = admission.route
        if (route == null) { notice(admission.notice); return@inspect }
        val consent = PinnedDesktopTeam.Review(source.id, revision, text, route)
        val dialog = AlertDialog.Builder(this).setTitle(R.string.auto_goal_team_title)
            .setMessage(getString(R.string.desktop_team_confirm, route.desktop, route.model,
                getString(route.effort.labelResource()), objective))
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.auto_goal_team_run) { _, _ ->
                if (eligible()) inspect confirm@{ checked ->
                    if (!consent.claim(agentTranscriptStore.activeConversation().id, review.revision,
                            agentGoalInput.text.toString().trim(), checked.route)) { notice(checked.notice); return@confirm }
                    runCatching { launchConfirmedDesktopTeam(route, objective) }.onFailure {
                        Toast.makeText(this, R.string.auto_goal_team_error, Toast.LENGTH_LONG).show()
                    }
                }
            }.create()
        review.dialog = dialog
        dialog.setOnDismissListener { if (review.dialog === dialog) review.dialog = null }
        dialog.show()
    }
}

private fun MainActivity.launchConfirmedDesktopTeam(route: PinnedDesktopTeam.Route, objective: String) {
    // A fresh group has no historical workspace, prior turn, or active member to steer.
    val selection = AgentModelSelection(AgentModelSelectionMode.MANUAL, route.target, route.model,
        route.desktop, route.effort)
    val chat = agentTranscriptStore.createAgentConversation(getString(R.string.desktop_team_name), initialSelection = selection)
    val turn = UUID.randomUUID().toString()
    val group = CollaborationGroupStore(this).create(
        PinnedDesktopTeam.newGroup(chat.id, turn, route, CollaborationGroupStore.names(this)))
    val members = group.requested(emptyList())
    val seed = requireNotNull(CollaborationRoutingPolicy.seed(turn, members)).let {
        it.copy(parameters = it.parameters + mapOf(PinnedDesktopTeam.PIN to route.digest,
            "manual_target_locked" to "true", "manual_model_id" to route.model,
            "agent_model_id" to route.model, "agent_reasoning_effort" to route.effort.wireValue))
    }
    agentGoalInput.setText("")
    openAgentConversation(chat.id)
    AgentTurnReceipt.begin(this, chat.id, turn, AgentModelSelectionSettings.selection(this, chat.id), voice = false)
    agentTranscriptStore.append(AgentTranscriptRole.USER, objective, "desktop-team:$turn",
        conversationId = chat.id, turnId = turn, taskId = turn)
    agentTurnGoals[turn] = objective
    agentSubmissionExecutor.execute {
        executeConcurrentAgentGoal(objective, AgentConversationContext(chat.id, "", emptyList(), false),
            chat.id, turn, deterministicAction = seed, confirmedGroupMembers = members)
    }
    refreshCollaborationStrip()
    refreshAgentTranscriptWindow(chat.id)
}
