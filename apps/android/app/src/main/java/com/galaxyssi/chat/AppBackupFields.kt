package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Versioned field names bound metadata, not the number of memory records. */
internal object AppBackupFields {
    private enum class Kind { OBJECT, ARRAY, STRING, NUMBER }
    private val app = mapOf("identity" to Kind.OBJECT, "profile" to Kind.OBJECT, "privacy_manifest" to Kind.OBJECT,
        "contacts" to Kind.ARRAY, "friend_requests" to Kind.ARRAY, "messages" to Kind.OBJECT)
    private val agent = buildMap {
        put("version", Kind.NUMBER)
        listOf("interface_language", "agent_preference_mode", "active_agent_conversation").forEach { put(it, Kind.STRING) }
        listOf("knowledge", "tasks", "transcript", "agent_conversations", "workflows", "workflow_schedules",
            "workflow_triggers", "workflow_execution_history", "custom_device_connectors").forEach { put(it, Kind.ARRAY) }
        listOf("safety", "task_budget", "global_super_agent", "agent_self_model", "model_planner", "voice_assistant",
            "home_assistant").forEach { put(it, Kind.OBJECT) }
    }

    fun requireKnown(section: String, key: String) { kind(section, key) }

    fun validate(section: String, key: String, value: Any) {
        val valid = when (kind(section, key)) {
            Kind.OBJECT -> value is JSONObject
            Kind.ARRAY -> value is JSONArray
            Kind.STRING -> value is String
            Kind.NUMBER -> value is Number && value.toLong() == 33L && value.toDouble() == 33.0
        }
        require(valid) { "Invalid backup field: $section/$key" }
    }

    fun expected(contacts: Boolean, messages: Boolean): Set<Pair<String, String>> = buildSet {
        app.keys.filter { (contacts || it !in setOf("contacts", "friend_requests")) && (messages || it != "messages") }
            .forEach { add("app-field" to it) }
        agent.keys.forEach { add("agent-field" to it) }
    }

    private fun kind(section: String, key: String): Kind = when (section) {
        "app-field" -> app[key]
        "agent-field" -> agent[key]
        else -> null
    } ?: error("Unknown backup field: $section/$key")
}
