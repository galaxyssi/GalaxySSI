package com.signalasi.chat

import org.json.JSONObject
import java.util.Locale

internal object SignalASITransportPrivacyPolicy {
    private val localOnlyTypePrefixes = listOf(
        "evolution_",
        "self_evolution",
        "memory_evolution",
        "global_agent",
        "global_memory",
        "global_cognition",
        "global_research"
    )
    private val localOnlyConversationPrefixes = listOf(
        "global-cognition:",
        "global-research:",
        "global-run:",
        "global-replan:",
        "self-evolution:",
        "memory-evolution:"
    )
    private val delegatableBackgroundConversationPrefixes = listOf(
        "global-cognition:",
        "global-research:",
        "global-run:",
        "global-replan:"
    )

    fun isLocalOnly(
        payload: JSONObject,
        trustedBackgroundCognitionAuthorized: Boolean = false
    ): Boolean {
        val type = payload.optString("type").trim().lowercase(Locale.ROOT)
        val conversationId = payload.optString("conversation_id").trim().lowercase(Locale.ROOT)
        if (trustedBackgroundCognitionAuthorized &&
            type == "text" &&
            delegatableBackgroundConversationPrefixes.any(conversationId::startsWith)
        ) {
            return false
        }
        if (localOnlyTypePrefixes.any(type::startsWith)) return true
        if (localOnlyConversationPrefixes.any(conversationId::startsWith)) return true
        val taskKind = payload.optString("task_kind").trim().lowercase(Locale.ROOT)
        return taskKind in setOf("self_evolution", "memory_evolution", "global_agent")
    }
}
