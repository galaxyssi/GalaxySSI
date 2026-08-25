package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

internal class AgentConnectorContactSnapshot private constructor(
    val contacts: List<JSONObject>,
    private val contactsById: Map<String, JSONObject>
) {
    fun contactById(contactId: String): JSONObject? = contactsById[contactId]

    fun matchingContactIds(targetId: String): List<String> {
        val aliases = when (targetId) {
            "claude-code" -> setOf("claude-code", "claude")
            "home-assistant" -> setOf("home-assistant", "home_hub", "home-hub", "living-room-hub")
            else -> setOf(targetId)
        }
        return contacts.mapNotNull { contact ->
            if (contact.optBoolean("deleted", false)) return@mapNotNull null
            val id = contact.optString("id")
            val agentId = contact.optString("agent_id")
            val signalasiId = contact.signalasiId()
            if (id !in aliases && agentId !in aliases && signalasiId !in aliases) return@mapNotNull null
            id.ifBlank { signalasiId.ifBlank { agentId } }.takeIf(String::isNotBlank)
        }.distinct()
    }

    fun preferredMatchingContactId(
        targetId: String,
        canSend: (String) -> Boolean
    ): String? {
        val candidates = matchingContactIds(targetId)
        if (candidates.isEmpty()) return null
        candidates.firstOrNull { it == targetId && canSend(it) }?.let { return it }
        return candidates
            .filter(canSend)
            .maxByOrNull(::contactFreshness)
            ?: candidates.firstOrNull { it == targetId }
            ?: candidates.maxByOrNull(::contactFreshness)
    }

    fun contactForAgent(agentId: String): JSONObject? =
        contactById(agentId) ?: matchingContactIds(agentId).firstNotNullOfOrNull(::contactById)

    fun selectedCloudModel(contact: JSONObject): JSONObject {
        val selectedContact = JSONObject(contact.toString())
        val models = selectedContact.optJSONArray("cloud_models") ?: return selectedContact
        val selectedId = selectedContact.optString("selected_cloud_model")
        val model = (0 until models.length())
            .asSequence()
            .mapNotNull(models::optJSONObject)
            .firstOrNull { it.optString("model_id") == selectedId }
            ?: models.optJSONObject(0)
            ?: return selectedContact
        selectedContact.put("selected_cloud_model", model.optString("model_id"))
        selectedContact.put("cloud_model", model.optString("model_id"))
        selectedContact.put("cloud_endpoint", model.optString("endpoint"))
        selectedContact.put("cloud_api_key", model.optString("api_key"))
        selectedContact.put("cloud_api_style", model.optString("api_style", "openai"))
        return selectedContact
    }

    companion object {
        fun from(source: JSONArray): AgentConnectorContactSnapshot {
            val contacts = buildList {
                for (index in 0 until source.length()) {
                    source.optJSONObject(index)?.let(::add)
                }
            }
            val byId = buildMap {
                contacts.forEach { contact ->
                    contact.signalasiId().takeIf(String::isNotBlank)?.let { put(it, contact) }
                    contact.optString("id").takeIf(String::isNotBlank)?.let { put(it, contact) }
                }
            }
            return AgentConnectorContactSnapshot(contacts, byId)
        }

        private fun JSONObject.signalasiId(): String =
            optString("signalasi_id").ifBlank { optString("hermes_id") }.ifBlank { optString("id") }
    }

    private fun contactFreshness(contactId: String): Long {
        val contact = contactById(contactId) ?: return Long.MIN_VALUE
        return maxOf(
            contact.optLong("setup_updated_at", 0L),
            contact.optLong("paired_at", 0L),
            contact.optLong("profile_updated_at", 0L),
            contact.optLong("created_at", 0L)
        )
    }
}
