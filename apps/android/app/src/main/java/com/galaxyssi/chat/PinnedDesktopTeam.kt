package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Only host-created collaboration seeds carry PIN. Never infer it from prompt text or a provider name. */
internal object PinnedDesktopTeam {
    const val CAPABILITY = "pinned_team_codex_v1"
    const val PIN = "_galaxyssi_pinned_desktop_team"
    const val PERSON = "_galaxyssi_pinned_desktop_person"
    data class Route(val target: String, val model: String, val effort: AgentModelReasoningEffort,
        val desktop: String, val digest: String)
    data class Admission(val route: Route? = null, val notice: Int = R.string.auto_goal_team_route_changed)

    class Review(private val source: String, private val revision: Long, private val text: String,
        private val route: Route) {
        private val consumed = AtomicBoolean()
        fun claim(chat: String, currentRevision: Long, draft: String, current: Route?): Boolean =
            consumed.compareAndSet(false, true) && chat == source && revision == currentRevision &&
                draft == text && route == current
    }

    fun advertised(agent: JSONObject): Boolean {
        val capabilities = agent.optJSONArray("capabilities") ?: return false
        return (0 until capabilities.length()).any { capabilities.opt(it) == CAPABILITY }
    }

    fun routingCapabilities(agent: JSONObject): JSONArray? {
        val adapter = agent.optJSONObject("adapter")
        val list = agent.optJSONArray("capabilities") ?: return adapter?.optJSONArray("capabilities")
        if (!advertised(agent)) return list
        val rest = JSONArray()
        for (i in 0 until list.length()) if (list.opt(i) != CAPABILITY) rest.put(list.opt(i))
        // Compact presence carries the pin marker alone, not a replacement inventory.
        return rest.takeUnless { it.length() == 0 && adapter == null }
    }

    fun ordinary(chat: AgentConversation?) = chat != null && chat.globalTopicKey.isEmpty() &&
        chat.parentConversationId.isEmpty() && !chat.privateMode && !chat.trackingPaused &&
        chat.status == AgentConversationStatus.ACTIVE && chat.mergedIntoConversationId.isEmpty() &&
        runCatching { UUID.fromString(chat.id).toString() == chat.id }.getOrDefault(false)

    fun manualCodex(s: AgentModelSelection) = s.mode == AgentModelSelectionMode.MANUAL &&
        (s.targetId == "codex" || s.targetId.endsWith(":codex"))


    fun eligibleObjective(text: String) = AutoGoalTeamCommand.allowsModelReview(text) &&
        !teamClinicalIdentifierField.containsMatchIn(text) && !AgentTaskRequirementAnalyzer.analyze(text).localOnly

    fun supports(s: AgentModelSelection, profile: AgentInvocationProfile) =
        manualCodex(s) && s.modelId.isNotBlank() && profile.models.any { it.id == s.modelId } &&
            !RetiredAgentModelPolicy.isRetired(s.modelId) &&
            (s.reasoningEffort == AgentModelReasoningEffort.AUTO || s.reasoningEffort in profile.reasoningEfforts)

    fun inspect(ctx: Context, chat: String): Admission {
        val s = AgentModelSelectionSettings.selection(ctx, chat)
        if (!manualCodex(s)) return Admission()
        val id = if (s.targetId != "codex") s.targetId else {
            val contacts = AgentConnectorContactSnapshot.from(AppStore.contacts(ctx))
            contacts.matchingContactIds("codex").filter { contacts.contactById(it)?.optString("delivery_mode") == "pc_connector" }
                .singleOrNull() ?: return Admission()
        }
        val raw = AppStore.contactById(ctx, id) ?: return Admission()
        if (raw.optString("id") != id || raw.optString("agent_id") != "codex" ||
            !AppStore.usesPcConnectorTunnel(ctx, id) || !AppStore.canCommunicateWith(ctx, id)) return Admission()
        val desktop = raw.optString("desktop_id")
        val link = GalaxySSILinkProtocol.serverLink(ctx, desktop)?.takeIf { it.paired } ?: return Admission()
        val fingerprint = raw.optString("desktop_fingerprint")
        if (fingerprint.isBlank() || !fingerprint.equals(link.desktopFingerprint, true) ||
            link.routes.clientRouteId.isBlank()) return Admission()
        val target = AppStoreAgentConnectorRegistry(ctx).availableTargets().singleOrNull {
            it.id == id && it.kind == AgentConnectorKind.AGENT && it.status == AgentConnectorStatus.AVAILABLE
        } ?: return Admission()
        if (id in EncryptedAgentDataDisclosureStore(ctx).blockedDestinationIds() ||
            AgentTaskBudgetStore(ctx).load().profile == AgentTaskBudgetProfile.PRIVATE) return Admission()
        return bind(s.copy(targetId = id), target.invocationProfile, raw.opt(CAPABILITY) == true,
            desktop, fingerprint, link.routes.clientRouteId, link.desktopName.ifBlank { desktop })
    }

    fun bind(s: AgentModelSelection, profile: AgentInvocationProfile, advertised: Boolean, desktop: String,
        fingerprint: String, clientRoute: String, name: String): Admission {
        if (!advertised) return Admission(notice = R.string.desktop_team_update)
        if (!supports(s, profile) || desktop.isBlank() || fingerprint.isBlank() || clientRoute.isBlank()) return Admission()
        val digest = AgentNativeJsonCodec.sha256(listOf(s.targetId, desktop, fingerprint, clientRoute,
            s.modelId, s.reasoningEffort.wireValue).joinToString("\u001f"))
        return Admission(Route(s.targetId, s.modelId, s.reasoningEffort, name, digest))
    }

    fun teamId(chat: String) = "$chat:desktop-team"

    fun newGroup(id: String, turn: String, route: Route, names: List<String>): CollaborationGroup {
        require(names.size >= 2 && turn.isNotBlank())
        return CollaborationGroup(id, names.take(2).map { name ->
            CollaborationMember(name = name, agentId = route.target, providerLabel = route.desktop, modelId = route.model)
        }, workflow = CollaborationWorkflow.RESEARCH, confirmedDesktopTurn = turn).validate()
    }

    fun memberMatches(group: CollaborationGroup?, person: String?, route: Route): Boolean =
        group?.members?.singleOrNull { it.id == person }?.let { it.agentId == route.target && it.modelId == route.model &&
            it.observeMessages && it.participation != CollaborationParticipation.MENTION_ONLY } == true

    fun ownsSpec(group: CollaborationGroup?, spec: AgentTeamDispatchSpec, turn: String, route: Route): Boolean {
        if (group == null || group.workflow != CollaborationWorkflow.RESEARCH ||
            group.confirmedDesktopTurn != turn || turn.isBlank() || spec.definition.teamId != teamId(group.conversationId) ||
            spec.supervisorRunId != AgentTeamDispatchIds.supervisorRunId(spec.definition.teamId) ||
            spec.definition.primaryMemberId != group.coordinatorId) return false
        val members = spec.definition.members
        return members.size == 2 && members.map { it.memberId }.toSet() == group.members.map { it.id }.toSet() &&
            CollaborationResearchWorkflow.isResearch(members) && members.all {
                it.agentId == route.target && it.context["collaboration_model_id"] == route.model &&
                    it.context["collaboration_group_id"] == group.conversationId &&
                    it.context[CollaborationResearchWorkflow.PERSON] == it.memberId && memberMatches(group, it.memberId, route)
            }
    }

    fun current(ctx: Context, chat: String, digest: String): Route? =
        if (!ordinary(AgentTranscriptStore(ctx).conversation(chat))) null
        else inspect(ctx, chat).route?.takeIf { it.digest == digest }

    fun matches(action: AgentAction, route: Route, contact: String): Boolean = action.parameters.let { p ->
        contact == route.target && p[PIN] == route.digest && p["connector_id"] == route.target &&
            p["manual_target_locked"] == "true" && p["manual_model_id"] == route.model &&
            p["agent_model_id"] == route.model && p["agent_reasoning_effort"] == route.effort.wireValue &&
            CollaborationResultContract.encodable(p["team_id"].orEmpty(), p["agent_instance_id"].orEmpty()) &&
            p["team_id"] == teamId(p[INTERNAL_CONVERSATION_ID].orEmpty()) && CollaborationResultContract.forAction(action) ==
            CollaborationResultContract.WORKSPACE
    }

    fun sendAllowed(ctx: Context, action: AgentAction, contact: String): Boolean {
        val chat = action.parameters[INTERNAL_CONVERSATION_ID] ?: return false
        val route = current(ctx, chat, action.parameters[PIN].orEmpty()) ?: return false
        val group = CollaborationGroupStore(ctx).load(chat) ?: return false
        return matches(action, route, contact) && group.confirmedDesktopTurn.isNotBlank() &&
            group.confirmedDesktopTurn == action.parameters["_galaxyssi_task_id"] &&
            memberMatches(group, action.parameters[PERSON], route) &&
            AgentTeamDurableControl(ctx).get(AgentTeamDispatchIds.supervisorRunId(teamId(chat))) == AgentTeamUserControl.RUN &&
            AgentTurnAttachmentRegistry.get(action.parameters[INTERNAL_TURN_ID].orEmpty()).isEmpty()
    }
}
