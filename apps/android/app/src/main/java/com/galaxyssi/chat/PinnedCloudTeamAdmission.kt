package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.net.URI

internal object PinnedCloudTeamAdmission {
    data class Invitation(val pin: GoalRoute, val offer: () -> Unit)
    fun matches(selection: AgentModelSelection?, target: String, model: String) =
        selection?.mode == AgentModelSelectionMode.MANUAL && target.isNotBlank() && model.isNotBlank() &&
            selection.targetId == target && selection.modelId == model

    // This runner cannot meter a custom resource ceiling. Decline instead of overriding it.
    fun permits(budget: AgentTaskBudget) = budget.profile != AgentTaskBudgetProfile.PRIVATE &&
        budget == AgentTaskBudget(profile = budget.profile)

    fun route(target: String, model: JSONObject): GoalRoute? {
        if (target.isBlank() || model.optString("delivery_mode") != "cloud_api" ||
            model.optString("cloud_api_style", "openai") != "openai" || !CloudModelCredentialPolicy.isAutoRoutable(model)) return null
        val uri = runCatching { URI(model.getString("cloud_endpoint")) }.getOrNull() ?: return null
        if (uri.userInfo != null || uri.host.isNullOrBlank()) return null
        return GoalRoute(target, model.getString("cloud_model"), ConversationGoalRunner.fingerprint(model), uri.host)
    }

    fun selectedRoute(ctx: Context, selection: AgentModelSelection): GoalRoute? {
        if (!matches(selection, selection.targetId, selection.modelId)) return null
        val config = AppStore.selectedCloudModelContact(ctx, selection.targetId) ?: return null
        return route(selection.targetId, CloudModelRequestRoutingPolicy.resolve(config, selection.modelId, false))
            ?.takeIf { it.model == selection.modelId }
    }

    fun current(ctx: Context, chat: String, pinned: GoalRoute): Boolean {
        if (selectedRoute(ctx, AgentModelSelectionSettings.selection(ctx, chat)) != pinned ||
            !permits(AgentTaskBudgetStore(ctx).load()) ||
            pinned.target in EncryptedAgentDataDisclosureStore(ctx).blockedDestinationIds()) return false
        return AppStoreAgentConnectorRegistry(ctx).availableTargets().any {
            it.id == pinned.target && it.status == AgentConnectorStatus.AVAILABLE
        }
    }

    fun ordinary(p: Map<String, String>, target: String, model: String): Boolean =
        target.isNotBlank() && model.isNotBlank() && p["manual_target_locked"] == "true" &&
            p["connector_id"] == target && p["manual_model_id"] == model &&
            (p["connector_task_mode"].isNullOrBlank() ||
                (p["connector_task_mode"] == PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE &&
                    p["supervised_iteration"] == "0" && p[INTERNAL_TASK_EXECUTION_MODE] == AgentTaskExecutionMode.PLAN_ONLY.wireValue &&
                    p[SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER].isNullOrBlank() &&
                    p["depends_on"].isNullOrBlank() && p["use_outputs_from"].isNullOrBlank())) &&
            p["request_kind"].isNullOrBlank() &&
            !p[MANAGED_AGENT_TEAM_ACTION_PARAMETER].toBoolean() && !p["agent_team_message"].toBoolean() &&
            p["routing_requires_live_data"] != "true" && p["routing_local_only"] != "true" &&
            p[AgentResearchCheckpoint.RECOVERY].isNullOrBlank() && p["task_budget"].isNullOrBlank()

    fun invitation(ctx: Context, action: AgentAction, chat: String, turn: String, target: String,
        model: JSONObject): Invitation? {
        if (!ordinary(action.parameters, target, model.optString("cloud_model")) || action.outputSourceIds().isNotEmpty() ||
            PhoneAssistantTaskControl.isBound(turn) || AgentTurnAttachmentRegistry.get(turn).isNotEmpty()) return null
        val pin = route(target, model) ?: return null
        val offer = AgentConversationWindows.modelTeamReview(chat, turn, pin) ?: return null
        // Only an original, self-contained user turn can advertise an invitation. No context is copied.
        val store = AgentTranscriptStore(ctx)
        val source = store.firstEntryForTurn(chat, turn)?.takeIf { it.role == AgentTranscriptRole.USER } ?: return null
        val conversation = store.conversation(chat) ?: return null
        if (AgentTaskRequirementAnalyzer.analyze(source.text).liveDataRequired ||
            AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(source.text, false) ||
            !allowsModelTeamTurn(conversation, source.text, false, false) ||
            !ConversationGoalRunner.eligible(ctx, conversation) || !current(ctx, chat, pin)) return null
        return Invitation(pin, offer)
    }
}
