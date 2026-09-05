package com.galaxyssi.chat

import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

internal object AgentPendingDeliveryCodec {
    fun encode(delivery: AgentPendingDelivery): String = JSONObject()
        .put("source_message_id", delivery.sourceMessageId)
        .put("conversation_id", delivery.conversationId).put("turn_id", delivery.turnId)
        .put("task_id", delivery.taskId).put("contact_id", delivery.contactId)
        .put("recovery_successor_source_message_id", delivery.recoverySuccessorSourceMessageId).toString()

    fun decode(raw: String, source: Long): AgentPendingDelivery {
        val value = JSONObject(raw)
        val conversation = value.getString("conversation_id")
        val turn = value.getString("turn_id")
        require(source > 0 && value.optLong("source_message_id", source) == source)
        require(conversation.isNotBlank() && turn.isNotBlank())
        return AgentPendingDelivery(source, conversation, turn, value.optString("task_id").ifBlank { turn },
            value.optString("contact_id"), value.optLong("recovery_successor_source_message_id"))
    }

    fun turnKey(conversation: String, turn: String): String = hash(JSONArray(listOf(conversation, turn)).toString())
    fun legacyTurnKey(conversation: String, turn: String): String = "turn:${conversation.trim()}:${turn.trim()}"
    fun hash(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') }
    fun sameTurn(delivery: AgentPendingDelivery, conversation: String, turn: String): Boolean =
        delivery.conversationId == conversation && delivery.turnId == turn
}
