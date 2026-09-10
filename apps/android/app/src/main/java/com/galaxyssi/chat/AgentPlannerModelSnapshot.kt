package com.galaxyssi.chat

import org.json.JSONObject

/** Non-secret task configuration. Credentials are resolved from the original contact at execution time. */
data class AgentPlannerModelSnapshot(val settings: AgentModelPlannerSettings, val route: AgentPlannerProviderRoute?) {
    internal fun toJson(): JSONObject = JSONObject().put("settings", JSONObject()
        .put("enabled", settings.enabled).put("screen", settings.shareScreenText).put("actions", settings.maxActions)
        .put("contact", settings.cloudContactId).put("dynamic", settings.dynamicReplanning).put("replans", settings.maxReplans)
        .put("coordination", settings.multiAgentCoordination).put("outputs", settings.shareAgentOutputsWithPlanner)
        .put("hops", settings.maxAgentHops).put("tools", settings.maxToolCalls).put("iterations", settings.maxLoopIterations)
        .put("retries", settings.maxPhaseRetries).put("timeout", settings.noProgressTimeoutSeconds))
        .put("route", route?.toJson())

    companion object {
        internal fun fromJson(json: JSONObject): AgentPlannerModelSnapshot {
            val s = json.getJSONObject("settings")
            return AgentPlannerModelSnapshot(AgentModelPlannerSettings(s.getBoolean("enabled"), s.getBoolean("screen"),
                s.getInt("actions"), s.getString("contact"), s.getBoolean("dynamic"), s.getInt("replans"),
                s.getBoolean("coordination"), s.getBoolean("outputs"), s.getInt("hops"), s.getInt("tools"),
                s.getInt("iterations"), s.getInt("retries"), s.getInt("timeout")),
                json.optJSONObject("route")?.let(AgentPlannerProviderRoute::fromJson))
        }
    }
}

data class AgentPlannerProviderRoute(val contactId: String, val provider: String, val endpoint: String,
    val model: String, val apiStyle: String) {
    internal fun toJson() = JSONObject().put("contact", contactId).put("provider", provider).put("endpoint", endpoint)
        .put("model", model).put("style", apiStyle)

    internal fun resolve(current: JSONObject?): JSONObject {
        if (current == null || current.optBoolean("deleted", false)) {
            throw AgentModelLoopRecoveryException("planner_provider_contact_unavailable")
        }
        val actualId = current.optString("id").ifBlank { current.optString("galaxyssi_id") }
        val resolved = JSONObject(current.toString())
        current.optJSONArray("cloud_models")?.let { models ->
            val entry = (0 until models.length()).mapNotNull(models::optJSONObject)
                .firstOrNull { it.optString("model_id") == model }
                ?: throw AgentModelLoopRecoveryException("planner_provider_model_unavailable")
            // Do not borrow the currently selected model's credential when this entry was revoked.
            resolved.put("cloud_endpoint", entry.optString("endpoint"))
                .put("cloud_api_key", entry.optString("api_key"))
                .put("cloud_api_style", entry.optString("api_style").ifBlank { "openai" })
        }
        if (actualId != contactId || current.optString("delivery_mode") != "cloud_api" ||
            current.optString("cloud_provider") != provider || resolved.optString("cloud_endpoint") != endpoint ||
            resolved.optString("cloud_api_style").ifBlank { "openai" } != apiStyle) {
            throw AgentModelLoopRecoveryException("planner_provider_route_changed")
        }
        return resolved.put("cloud_model", model).put("selected_cloud_model", model).also {
            if (!CloudModelCredentialPolicy.isAutoRoutable(it)) {
                throw AgentModelLoopRecoveryException("planner_provider_credentials_unavailable")
            }
        }
    }

    companion object {
        internal fun capture(contact: JSONObject) = AgentPlannerProviderRoute(
            contact.optString("id").ifBlank { contact.optString("galaxyssi_id") }, contact.getString("cloud_provider"),
            contact.getString("cloud_endpoint"), contact.getString("cloud_model"),
            contact.optString("cloud_api_style").ifBlank { "openai" })
        internal fun fromJson(json: JSONObject) = AgentPlannerProviderRoute(json.getString("contact"),
            json.getString("provider"), json.getString("endpoint"), json.getString("model"), json.getString("style"))
    }
}

internal fun AgentPlannerRecoverySpec.toJson(codec: SharedPreferencesAgentSessionStore) = JSONObject()
    .put("kind", kind.name).put("configuration", configurationSha256)
    .put("action", action?.let(codec::encodeExecutableAction)).put("model_snapshot", modelSnapshot?.toJson())

internal fun decodePlannerRecoverySpec(json: JSONObject, codec: SharedPreferencesAgentSessionStore) =
    AgentPlannerRecoverySpec(AgentPlannerRecoveryKind.valueOf(json.getString("kind")),
        json.optJSONObject("action")?.let(codec::decodeAction), json.getString("configuration"),
        json.optJSONObject("model_snapshot")?.let(AgentPlannerModelSnapshot::fromJson))

internal fun MobileNativeAgent.taskScopedPlanner(): AgentPlanner {
    val saved = taskPlannerSpec
    if (saved != null) return planner.takeIf { it.recoverySpec() == saved }
        ?: saved.restore(appContext) { nativeToolRegistry }
    val selected = (planner as? GuardedModelAgentPlanner)?.freezeForTask() ?: planner
    taskPlannerSpec = selected.recoverySpec()?.takeIf { it.modelSnapshot != null }
    return selected
}
