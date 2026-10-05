package com.galaxyssi.chat

import org.json.JSONObject

/** Explicit text-only pilot profile. It never mutates the user's saved provider settings. */
internal data class CollaborationTrialProfile(val maxOutputTokens: Int, val temperature: Double, val thinkingMode: String) {
    init {
        require(maxOutputTokens > 0 && temperature.isFinite() && temperature in 0.0..2.0)
        require(thinkingMode == "disabled") { "This pilot profile requires explicit non-thinking mode" }
    }

    fun json() = JSONObject().put("format", "galaxyssi.trial-text-profile.v1")
        .put("max_output_tokens", maxOutputTokens).put("temperature", temperature).put("thinking_mode", thinkingMode)
        .put("external_tools", false).put("model_summarization", false)

    fun contact(source: JSONObject) = JSONObject(source.toString()).put("cloud_context_model_summary", false)

    fun apply(body: JSONObject) {
        listOf("tools", "tool_choice", "parallel_tool_calls", "top_p", "reasoning_effort", "max_completion_tokens").forEach(body::remove)
        body.put("max_tokens", maxOutputTokens).put("temperature", temperature)
            .put("thinking", JSONObject().put("type", thinkingMode))
    }

    fun requireControls(receipt: JSONObject) {
        val controls = receipt.optJSONObject("request_controls")
            ?: CollaborationTrialPolicy.deny("trial_request_controls_missing")
        val output = controls.opt("max_tokens")
        val temperatureValue = controls.opt("temperature")
        val toolCount = controls.opt("tool_definitions")
        if (controls.opt("types_valid") != true || output !is Number || output.toLong() != maxOutputTokens.toLong() || output.toDouble() != maxOutputTokens.toDouble() ||
            temperatureValue !is Number || temperatureValue.toDouble() != temperature ||
            controls.opt("thinking_mode") != thinkingMode || toolCount !is Int || toolCount != 0 ||
            !controls.isNull("top_p") || !controls.isNull("reasoning_effort"))
            CollaborationTrialPolicy.deny("trial_request_controls_changed")
    }

    companion object {
        fun from(value: JSONObject): CollaborationTrialProfile {
            require(value.getString("format") == "galaxyssi.trial-text-profile.v1")
            require(value.opt("external_tools") == false && value.opt("model_summarization") == false)
            val output = CollaborationTrialPolicy.strictLong(value.get("max_output_tokens"))
            require(output in 1..Int.MAX_VALUE.toLong())
            val temperature = value.get("temperature")
            require(temperature is Number)
            return CollaborationTrialProfile(output.toInt(), temperature.toDouble(), value.getString("thinking_mode"))
        }
    }
}
