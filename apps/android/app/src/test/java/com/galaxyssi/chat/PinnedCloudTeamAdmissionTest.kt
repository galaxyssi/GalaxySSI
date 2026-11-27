package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PinnedCloudTeamAdmissionTest {
    private val contact = "fixture"
    private val model = "selected-model"
    private val selected = AgentModelSelection(AgentModelSelectionMode.MANUAL, contact, model)
    private val parameters = mapOf("connector_id" to contact, "manual_model_id" to model, "manual_target_locked" to "true")

    @Test fun bothTheManualSelectionAndActualDispatchMustMatch() {
        assertTrue(PinnedCloudTeamAdmission.matches(selected, contact, model))
        assertFalse(PinnedCloudTeamAdmission.matches(selected.copy(mode = AgentModelSelectionMode.AUTO), contact, model))
        assertFalse(PinnedCloudTeamAdmission.matches(selected.copy(modelId = ""), contact, model))
        assertTrue(PinnedCloudTeamAdmission.ordinary(parameters, contact, model))
        assertFalse(PinnedCloudTeamAdmission.ordinary(parameters, "fallback", model))
        assertFalse(PinnedCloudTeamAdmission.ordinary(parameters, contact, "replacement"))
        for ((key, value) in mapOf("manual_target_locked" to "false", "connector_task_mode" to "planner",
            "request_kind" to "screen_analysis", MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
            "agent_team_message" to "true", "routing_requires_live_data" to "true", "routing_local_only" to "true",
            AgentResearchCheckpoint.RECOVERY to "prior", "task_budget" to "{}")) {
            assertFalse(key, PinnedCloudTeamAdmission.ordinary(parameters + (key to value), contact, model))
        }
    }

    @Test fun nonMeteringRunnerCannotOverridePerTaskOrPrivacyLimits() {
        val unrestricted = AgentTaskBudget()
        assertTrue(PinnedCloudTeamAdmission.permits(unrestricted))
        for (restricted in listOf(unrestricted.copy(allowCloud = false), unrestricted.copy(allowPaidProviders = false),
            unrestricted.copy(maxCostMicros = 100), unrestricted.copy(maxInputTokens = 20),
            unrestricted.copy(networkPolicy = AgentTaskNetworkPolicy.UNMETERED_ONLY),
            AgentTaskBudget.forProfile(AgentTaskBudgetProfile.PRIVATE))) assertFalse(PinnedCloudTeamAdmission.permits(restricted))
    }

    @Test fun routeRequiresReadyDirectCloudAndPinsPathNotOnlyHost() {
        fun fixture() = JSONObject().put("delivery_mode", "cloud_api").put("cloud_model", model)
            .put("cloud_api_style", "openai").put("cloud_provider", "custom").put("cloud_api_key", "fixture-only")
            .put("cloud_endpoint", "https://fixture.invalid/v1/chat/completions")
        val pin = requireNotNull(PinnedCloudTeamAdmission.route(contact, fixture()))
        assertEquals("fixture.invalid", pin.host)
        assertNotEquals(pin, PinnedCloudTeamAdmission.route(contact, fixture().put("cloud_endpoint", "https://fixture.invalid/v2")))
        for ((key, value) in listOf("cloud_api_style" to "gemini", "cloud_api_style" to "anthropic",
            "cloud_api_style" to "unknown", "delivery_mode" to "desktop", "cloud_api_key" to "", "setup_status" to "offline",
            "cloud_endpoint" to "http://fixture.invalid", "cloud_endpoint" to "https://user@fixture.invalid")) {
            assertNull(key, PinnedCloudTeamAdmission.route(contact, fixture().put(key, value)))
        }
    }
}
