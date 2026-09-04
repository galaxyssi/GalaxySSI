package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

data class AgentModelPlannerSettings(
    val enabled: Boolean = false,
    val shareScreenText: Boolean = false,
    val maxActions: Int = 8,
    val cloudContactId: String = "",
    val dynamicReplanning: Boolean = true,
    val maxReplans: Int = 3,
    val multiAgentCoordination: Boolean = true,
    val shareAgentOutputsWithPlanner: Boolean = false,
    val maxAgentHops: Int = 4,
    val maxToolCalls: Int = 16,
    val maxLoopIterations: Int = 8,
    val maxPhaseRetries: Int = 2,
    val noProgressTimeoutSeconds: Int = 180
)

class AgentModelPlannerSettingsStore(context: Context) {
    private val preferences = AgentEncryptedPreferences(context.applicationContext, PREFS)

    fun load(): AgentModelPlannerSettings {
        val json = runCatching { JSONObject(preferences.readString(KEY_SETTINGS, "{}")) }
            .getOrDefault(JSONObject())
        return AgentModelPlannerSettings(
            enabled = json.optBoolean("enabled", false),
            shareScreenText = json.optBoolean("share_screen_text", false),
            maxActions = json.optInt("max_actions", DEFAULT_MAX_ACTIONS).coerceIn(1, MAX_ACTIONS),
            cloudContactId = json.optString("cloud_contact_id").trim().take(120),
            dynamicReplanning = json.optBoolean("dynamic_replanning", true),
            maxReplans = json.optInt("max_replans", DEFAULT_MAX_REPLANS).coerceIn(1, MAX_REPLANS),
            multiAgentCoordination = json.optBoolean("multi_agent_coordination", true),
            shareAgentOutputsWithPlanner = json.optBoolean("share_agent_outputs_with_planner", false),
            maxAgentHops = json.optInt("max_agent_hops", DEFAULT_MAX_AGENT_HOPS).coerceIn(1, MAX_AGENT_HOPS),
            maxToolCalls = json.optInt("max_tool_calls", DEFAULT_MAX_TOOL_CALLS).coerceIn(MIN_TOOL_CALLS, MAX_TOOL_CALLS),
            maxLoopIterations = json.optInt("max_loop_iterations", DEFAULT_MAX_LOOP_ITERATIONS)
                .coerceIn(MIN_LOOP_ITERATIONS, MAX_LOOP_ITERATIONS),
            maxPhaseRetries = json.optInt("max_phase_retries", DEFAULT_MAX_PHASE_RETRIES)
                .coerceIn(MIN_PHASE_RETRIES, MAX_PHASE_RETRIES),
            noProgressTimeoutSeconds = json.optInt(
                "no_progress_timeout_seconds",
                DEFAULT_NO_PROGRESS_TIMEOUT_SECONDS
            ).coerceIn(MIN_NO_PROGRESS_TIMEOUT_SECONDS, MAX_NO_PROGRESS_TIMEOUT_SECONDS)
        )
    }

    fun save(settings: AgentModelPlannerSettings) {
        preferences.writeString(
            KEY_SETTINGS,
            JSONObject()
                .put("version", 5)
                .put("enabled", settings.enabled)
                .put("share_screen_text", settings.shareScreenText)
                .put("max_actions", settings.maxActions.coerceIn(1, MAX_ACTIONS))
                .put("cloud_contact_id", settings.cloudContactId.trim().take(120))
                .put("dynamic_replanning", settings.dynamicReplanning)
                .put("max_replans", settings.maxReplans.coerceIn(1, MAX_REPLANS))
                .put("multi_agent_coordination", settings.multiAgentCoordination)
                .put("share_agent_outputs_with_planner", settings.shareAgentOutputsWithPlanner)
                .put("max_agent_hops", settings.maxAgentHops.coerceIn(1, MAX_AGENT_HOPS))
                .put("max_tool_calls", settings.maxToolCalls.coerceIn(MIN_TOOL_CALLS, MAX_TOOL_CALLS))
                .put(
                    "max_loop_iterations",
                    settings.maxLoopIterations.coerceIn(MIN_LOOP_ITERATIONS, MAX_LOOP_ITERATIONS)
                )
                .put(
                    "max_phase_retries",
                    settings.maxPhaseRetries.coerceIn(MIN_PHASE_RETRIES, MAX_PHASE_RETRIES)
                )
                .put(
                    "no_progress_timeout_seconds",
                    settings.noProgressTimeoutSeconds.coerceIn(
                        MIN_NO_PROGRESS_TIMEOUT_SECONDS,
                        MAX_NO_PROGRESS_TIMEOUT_SECONDS
                    )
                )
                .toString()
        )
    }

    fun clear() = preferences.clear()

    private companion object {
        const val PREFS = "galaxyssi_agent_model_planner"
        const val KEY_SETTINGS = "settings"
        const val DEFAULT_MAX_ACTIONS = 8
        const val MAX_ACTIONS = 12
        const val DEFAULT_MAX_REPLANS = 3
        const val MAX_REPLANS = 5
        const val DEFAULT_MAX_AGENT_HOPS = 4
        const val MAX_AGENT_HOPS = 8
        const val DEFAULT_MAX_TOOL_CALLS = 16
        const val MIN_TOOL_CALLS = 4
        const val MAX_TOOL_CALLS = 32
        const val DEFAULT_MAX_LOOP_ITERATIONS = 8
        const val MIN_LOOP_ITERATIONS = 1
        const val MAX_LOOP_ITERATIONS = 24
        const val DEFAULT_MAX_PHASE_RETRIES = 2
        const val MIN_PHASE_RETRIES = 0
        const val MAX_PHASE_RETRIES = 5
        const val DEFAULT_NO_PROGRESS_TIMEOUT_SECONDS = 180
        const val MIN_NO_PROGRESS_TIMEOUT_SECONDS = 60
        const val MAX_NO_PROGRESS_TIMEOUT_SECONDS = 3_600
    }
}
