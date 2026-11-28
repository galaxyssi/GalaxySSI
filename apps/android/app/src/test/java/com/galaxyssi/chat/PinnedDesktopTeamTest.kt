package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PinnedDesktopTeamTest {
    private val route = PinnedDesktopTeam.Route("desktop_a:codex", "fixture-model", AgentModelReasoningEffort.HIGH, "A", "pin")
    private val selection = AgentModelSelection(AgentModelSelectionMode.MANUAL, route.target, route.model,
        reasoningEffort = route.effort)

    @Test fun onlyTheExactCapabilityInTheCurrentAgentListCounts() {
        val key = PinnedDesktopTeam.CAPABILITY
        val status = JSONObject().put("capabilities", JSONArray().put(key))
        assertTrue(PinnedDesktopTeam.advertised(status))
        assertNull(PinnedDesktopTeam.routingCapabilities(status))
        status.put("capabilities", JSONArray().put("code").put(key))
        assertEquals(listOf("code"), PinnedDesktopTeam.routingCapabilities(status)!!.let { caps ->
            (0 until caps.length()).map { caps.getString(it) }
        })
        for (bad in listOf(JSONArray(), JSONArray().put(key.uppercase()), key, true)) {
            status.put("capabilities", bad)
            assertFalse(PinnedDesktopTeam.advertised(status))
        }
        status.remove("capabilities")
        assertFalse(PinnedDesktopTeam.advertised(status.put(key, true)))
    }

    @Test fun onlyExplicitSupportedModelAndEffortAreEligible() {
        val profile = AgentInvocationProfile(models = listOf(AgentModelOption(route.model)),
            reasoningEfforts = listOf(route.effort))
        assertTrue(PinnedDesktopTeam.supports(selection, profile))
        assertTrue(PinnedDesktopTeam.supports(selection.copy(reasoningEffort = AgentModelReasoningEffort.AUTO), profile))
        for (changed in listOf(selection.copy(mode = AgentModelSelectionMode.AUTO), selection.copy(modelId = ""),
            selection.copy(modelId = "unknown"), selection.copy(targetId = "desktop_a:other"),
            selection.copy(reasoningEffort = AgentModelReasoningEffort.LOW))) {
            assertFalse(PinnedDesktopTeam.supports(changed, profile))
        }
    }

    @Test fun oldDesktopGetsUpdateNoticeAndRepairOrClientRouteChangeBreaksPin() {
        val profile = AgentInvocationProfile(models = listOf(AgentModelOption(route.model)), reasoningEfforts = listOf(route.effort))
        fun bind(advertised: Boolean, key: String, client: String) =
            PinnedDesktopTeam.bind(selection, profile, advertised, "fixture", key, client, "Desktop")
        val old = bind(false, "key", "client")
        assertNull(old.route)
        assertEquals(R.string.desktop_team_update, old.notice)
        val confirmed = requireNotNull(bind(true, "key", "client").route)
        assertNotEquals(confirmed.digest, bind(true, "other-key", "client").route?.digest)
        assertNotEquals(confirmed.digest, bind(true, "key", "other-client").route?.digest)
    }

    @Test fun confirmationIsOneShotAndBindsWindowRevisionTextAndExactRoute() {
        fun review() = PinnedDesktopTeam.Review("chat", 1, "draft", route)
        val ok = review()
        assertTrue(ok.claim("chat", 1, "draft", route))
        assertFalse(ok.claim("chat", 1, "draft", route))
        assertFalse(review().claim("other", 1, "draft", route))
        assertFalse(review().claim("chat", 2, "draft", route))
        assertFalse(review().claim("chat", 1, "edited", route))
        for (stale in listOf(null, route.copy(digest = "repaired"), route.copy(model = "other"),
                route.copy(effort = AgentModelReasoningEffort.AUTO))) {
            val ticket = review()
            assertFalse(ticket.claim("chat", 1, "draft", stale))
            assertFalse(ticket.claim("chat", 1, "draft", route))
        }
    }

    @Test fun noPrivateOrNamespacedChatCanLaunch() {
        val chat = AgentConversation("11111111-1111-4111-8111-111111111111", "Fixture", 1, 1)
        assertTrue(PinnedDesktopTeam.ordinary(chat))
        for (bad in listOf(null, chat.copy(privateMode = true), chat.copy(trackingPaused = true),
                chat.copy(globalTopicKey = "topic"), chat.copy(parentConversationId = "parent"),
                chat.copy(id = "special:fixture"), chat.copy(mergedIntoConversationId = "destination"),
                chat.copy(status = AgentConversationStatus.ARCHIVED))) assertFalse(PinnedDesktopTeam.ordinary(bad))
    }

    @Test fun ordinaryTeamOptInIsAllowedButPrivateRecordFieldsAreNot() {
        val request = "Have a team compare two sorting algorithms."
        assertEquals(AutoGoalTeamCommand.Start(request), AutoGoalTeamCommand.parse(request))
        assertTrue(PinnedDesktopTeam.eligibleObjective(request))
        assertFalse(PinnedDesktopTeam.eligibleObjective("Review this chart: MRN=FIXTURE"))
        assertFalse(PinnedDesktopTeam.eligibleObjective("研究。病历号：TEST"))
        assertFalse(PinnedDesktopTeam.eligibleObjective("研究。住院號：TEST"))
        assertFalse(PinnedDesktopTeam.eligibleObjective("Review my medical records."))
    }

    @Test fun sendRequiresTheReviewedContactModelEffortAndWorkspaceContract() {
        val params = mapOf("connector_id" to route.target, "manual_target_locked" to "true",
            "agent_model_id" to route.model, "manual_model_id" to route.model, "agent_reasoning_effort" to "high",
            PinnedDesktopTeam.PIN to route.digest, INTERNAL_CONVERSATION_ID to "chat",
            "team_id" to PinnedDesktopTeam.teamId("chat"), "agent_instance_id" to "member",
            MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true") + CollaborationResultContract.assignment("chat")
        val action = AgentAction("member-action", AgentActionKind.CALL_CONNECTOR, route.target, AgentRisk.LOW,
            AgentActionStatus.RUNNING, "Fixture", parameters = params, requiresConfirmation = false)
        assertTrue(PinnedDesktopTeam.matches(action, route, route.target))
        assertFalse(PinnedDesktopTeam.matches(action, route, "desktop_b:codex"))
        assertFalse(PinnedDesktopTeam.matches(action.copy(parameters = params + ("agent_instance_id" to "x".repeat(97))),
            route, route.target))
        for (key in params.keys) {
            assertFalse(key, PinnedDesktopTeam.matches(action.copy(parameters = params - key), route, route.target))
        }
    }
}
