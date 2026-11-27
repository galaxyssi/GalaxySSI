package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

// No prompt or provider credentials cross threads with a review invitation.
internal class TeamReviewDraft {
    @Volatile var revision = 0L
        private set
    private class Binding(val ids: Pair<String, String>, val pin: GoalRoute?, var supervised: SupervisedTeamReview? = null)
    @Volatile private var binding: Binding? = null
    var dialog: AlertDialog? = null

    @Synchronized fun invalidate() {
        revision++
        binding?.supervised?.forgetDelivery()
        binding = null
        dialog?.dismiss()
        dialog = null
    }

    @Synchronized fun bind(revisionAtSend: Long, chat: String, turn: String, pin: GoalRoute? = null) {
        if (revision == revisionAtSend) {
            binding?.supervised?.forgetDelivery()
            binding = Binding(chat to turn, pin)
        }
    }

    @Synchronized fun owns(chat: String, turn: String, pin: GoalRoute? = null): Boolean =
        binding?.let { it.ids == (chat to turn) && it.pin == pin } == true

    @Synchronized fun arm(chat: String, turn: String, pin: GoalRoute, answer: String, runtime: Any): Boolean {
        val current = binding ?: return false
        if (!owns(chat, turn, pin) || current.supervised != null || answer.isBlank()) return false
        val ticket = SupervisedTeamReview(chat, turn, pin, answer, runtime)
        if (!ticket.registerDelivery()) return false
        current.supervised = ticket
        return true
    }

    @Synchronized fun takeFresh(response: AgentConnectorResponse, runtime: Any): SupervisedTeamReview? =
        binding?.supervised?.takeIf { it.takeFresh(response, runtime) }

    @Synchronized fun claim(chat: String, turn: String, pin: GoalRoute? = null, receipt: SupervisedTeamReview? = null): Boolean {
        if (!owns(chat, turn, pin) || binding?.supervised !== receipt ||
            (receipt != null && !receipt.persisted)) return false
        binding = null
        return true
    }
}

internal class SupervisedTeamReview(val chat: String, val turn: String, val pin: GoalRoute, answer: String, runtime: Any) {
    companion object {
        private val awaitingDelivery = ConcurrentHashMap<String, SupervisedTeamReview>()
        fun hasPendingDelivery(turn: String) = awaitingDelivery.containsKey(turn)
        fun markDelivery(response: AgentConnectorResponse): Boolean =
            awaitingDelivery[response.turnId]?.markFresh(response) == true
    }

    fun registerDelivery() = awaitingDelivery.putIfAbsent(turn, this) == null
    fun forgetDelivery() { awaitingDelivery.remove(turn, this) }
    private val origin = WeakReference(runtime)
    private val answerDigest = digest(answer)
    private fun digest(body: String) = MessageDigest.getInstance("SHA-256").digest(body.toByteArray(Charsets.UTF_8))
    private fun matches(body: String) = answerDigest.contentEquals(digest(body))
    private var fresh: WeakReference<AgentConnectorResponse>? = null
    private var waitingConnector: Pair<Long, String>? = null
    @Volatile var persisted = false
        private set

    @Synchronized private fun markFresh(response: AgentConnectorResponse): Boolean {
        if (fresh != null || response.conversationId != chat || response.turnId != turn ||
            response.executionContactId != pin.target || response.sourceMessageId <= 0 || !response.success ||
            response.remoteFailure || response.deliveryFailureCode.isNotBlank() || response.richOutputJson.isNotBlank()) return false
        fresh = WeakReference(response)
        forgetDelivery()
        return true
    }

    @Synchronized fun takeFresh(response: AgentConnectorResponse, runtime: Any): Boolean {
        if (fresh?.get() !== response) return false
        fresh?.clear()
        return origin.get() === runtime
    }

    fun awaiting(phase: AgentPhase, result: AgentActionResult?, action: AgentAction?, source: Long): Boolean {
        if (action == null || result == null) return false
        if (phase != AgentPhase.WAITING_RESPONSE || result.metadata["awaiting_response"] != "true" ||
            result.metadata["source_message_id"]?.toLongOrNull() != source || result.actionId != action.id ||
            !originalConnector(action)) return false
        waitingConnector = source to action.id
        return true
    }

    private fun originalConnector(action: AgentAction) = action.isSupervisedProjectConnector() &&
        PinnedCloudTeamAdmission.ordinary(action.parameters, pin.target, pin.model)

    fun completed(state: AgentUiState?, source: Long): Boolean {
        val result = state?.lastActionResult ?: return false
        val meta = result.metadata
        if (state.phase != AgentPhase.COMPLETED || !result.success || !state.plan?.artifactRichOutputJson.isNullOrBlank() ||
            !meta["rich_output"].isNullOrBlank() || !matches(result.message)) return false
        if (meta["supervised_direct_response"] == "true") {
            return meta["source_message_id"]?.toLongOrNull() == source && meta["awaiting_response"] == "false" &&
                meta["recovered_after_timeout"] == "false"
        }

        // An executable completion replaces the connector result with the local marker's result.
        // The connector moves to actionHistory; the marker does not inherit its source receipt.
        val plan = state.plan ?: return false
        val connector = plan.actionHistory.singleOrNull() ?: return false
        val marker = plan.actions.singleOrNull() ?: return false
        return waitingConnector == (source to connector.id) && plan.plannerProfile == PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE &&
            connector.status == AgentActionStatus.COMPLETED && originalConnector(connector) &&
            marker.isTaskCompleteMarker() && marker.status == AgentActionStatus.COMPLETED && marker.id == result.actionId &&
            marker.description == result.message && marker.result == result.message &&
            meta["awaiting_response"] != "true" && meta["recovered_after_timeout"] != "true" &&
            meta["action_effect_replayed"] != "true" && meta["cancelled"] != "true" &&
            "source_message_id" !in meta && "supervised_direct_response" !in meta
    }

    fun finalized(original: AgentPlan?, accepted: AgentUiState?, finalized: AgentUiState, source: Long): Boolean {
        val acceptedPlan = accepted?.plan ?: return false
        val finalPlan = finalized.plan ?: return false
        if (original == null || original.planId != acceptedPlan.planId || accepted.sessionId != finalized.sessionId ||
            acceptedPlan.planId != finalPlan.planId || acceptedPlan.revision != finalPlan.revision ||
            accepted.lastActionResult?.actionId != finalized.lastActionResult?.actionId) return false
        val marker = acceptedPlan.actions.singleOrNull()?.isTaskCompleteMarker() == true
        return (!marker || acceptedPlan.revision == original.revision + 1) &&
            completed(accepted, source) && completed(finalized, source)
    }

    fun finalBody(writtenChat: String, writtenTurn: String, body: String) {
        persisted = writtenChat == chat && writtenTurn == turn && matches(body)
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

internal fun MainActivity.offerModelTeamReview(chatId: String, turn: String, pin: GoalRoute? = null,
    receipt: SupervisedTeamReview? = null, cancellation: AgentTaskCancellationSource? = null) {
    if (!conversationWindow.teamReview.claim(chatId, turn, pin, receipt)) return
    val chat = agentTranscriptStore.activeConversation()
    val text = agentTurnGoals[turn] ?: return
    if (chat.id != chatId || !AutoGoalTeamCommand.allowsModelReview(text)) return
    reviewAutoGoalTeam(chat, AutoGoalTeamCommand.Start(text), "", hasExtras = false, fromModel = true,
        sourceTurn = turn, pin = pin, cancellation = cancellation)
}

private fun MainActivity.reviewAutoGoalTeam(chat: AgentConversation, command: AutoGoalTeamCommand,
    draftText: String, hasExtras: Boolean, fromModel: Boolean, sourceTurn: String? = null, pin: GoalRoute? = null,
    cancellation: AgentTaskCancellationSource? = null) {
    val draft = conversationWindow.teamReview
    val submitted = draft.revision
    val ctx = applicationContext
    fun modelWindowValid() = !fromModel || (draft.revision == submitted && cancellation?.isCancellationRequested != true &&
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
            fun routesNow() = if (pin == null) teamRoutes(ctx, chat.id)
                else listOf(pin).filter { PinnedCloudTeamAdmission.current(ctx, chat.id, it) }
            val routes = routesNow()
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
                                if (route !in routesNow()) {
                                    runOnUiThread { notice(R.string.auto_goal_team_route_changed) }
                                    return@dispatch
                                }
                                if (!modelWindowValid()) return@dispatch
                                completed(AutoGoalTeamJobs.start(ctx, current, command.objective, route, sourceTurn,
                                    pinnedCloud = pin != null), R.string.auto_goal_team_active)
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
