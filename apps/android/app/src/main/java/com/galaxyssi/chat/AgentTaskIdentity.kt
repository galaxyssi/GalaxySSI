package com.galaxyssi.chat

import android.content.Context
import java.nio.charset.StandardCharsets
import java.util.UUID
import org.json.JSONObject

internal data class AgentTaskIdentity(
    val clientRouteId: String,
    val conversationId: String,
    val taskId: String,
    val turnId: String
) {
    val isComplete: Boolean
        get() = clientRouteId.isNotBlank() &&
            conversationId.isNotBlank() &&
            taskId.isNotBlank() &&
            turnId.isNotBlank()
}

internal data class AgentConnectorResponseIdentity(
    val conversationId: String,
    val taskId: String,
    val turnId: String
)

internal object AgentTaskIdentityPolicy {
    fun conversationId(contactId: String, requested: String): String =
        requested.trim().ifBlank { "contact:${contactId.trim()}" }

    fun turnId(sourceMessageId: Long?, requested: String): String =
        requested.trim().ifBlank {
            sourceMessageId
                ?.takeIf { it > 0L }
                ?.let { "message:$it" }
                ?: UUID.randomUUID().toString()
        }

    fun taskId(
        ownerId: String,
        contactId: String,
        sourceMessageId: Long?,
        conversationId: String,
        turnId: String,
        requested: String = ""
    ): String {
        val explicit = requested.trim()
        if (explicit.isNotBlank()) return explicit
        val seed = listOf(
            ownerId.trim(),
            contactId.trim(),
            sourceMessageId?.toString().orEmpty(),
            conversationId.trim(),
            turnId.trim()
        ).joinToString("\u001f")
        return UUID.nameUUIDFromBytes(seed.toByteArray(StandardCharsets.UTF_8)).toString()
    }

    fun matchesDesktopResponse(
        expected: Map<String, String>,
        conversationId: String,
        taskId: String,
        turnId: String
    ): Boolean {
        if (expected["resource_location"] != "desktop") return true
        val expectedConversationId = expected["conversation_id"].orEmpty()
        val expectedTaskId = expected["remote_task_id"].orEmpty()
        val expectedTurnId = expected["turn_id"].orEmpty()
        return expectedConversationId.isNotBlank() &&
            expectedTaskId.isNotBlank() &&
            expectedTurnId.isNotBlank() &&
            conversationId == expectedConversationId &&
            taskId == expectedTaskId &&
            turnId == expectedTurnId
    }

    fun canonicalConnectorResponseIdentity(
        pendingDelivery: AgentPendingDelivery?,
        conversationId: String,
        taskId: String,
        turnId: String
    ): AgentConnectorResponseIdentity = AgentConnectorResponseIdentity(
        conversationId = pendingDelivery?.conversationId.orEmpty().ifBlank {
            conversationId.trim()
        },
        taskId = pendingDelivery?.taskId.orEmpty().ifBlank {
            taskId.trim()
        },
        turnId = pendingDelivery?.turnId.orEmpty().ifBlank {
            turnId.trim()
        }
    )

    fun routesToMainAgent(
        superseded: Boolean,
        hasRuntime: Boolean,
        resolvedConversationId: String
    ): Boolean = superseded || hasRuntime || resolvedConversationId.isNotBlank()
}

internal object AgentTaskIdentityStore {
    private const val PREFS_NAME = "galaxyssi_agent_task_identities"

    fun register(
        context: Context,
        contactId: String,
        sourceMessageId: Long,
        identity: AgentTaskIdentity
    ) {
        if (contactId.isBlank() || sourceMessageId <= 0L || !identity.isComplete) return
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(
                key(contactId, sourceMessageId),
                JSONObject()
                    .put("client_route_id", identity.clientRouteId)
                    .put("conversation_id", identity.conversationId)
                    .put("task_id", identity.taskId)
                    .put("turn_id", identity.turnId)
                    .toString()
            )
            .apply()
    }

    fun matches(context: Context, payload: JSONObject): Boolean {
        return matchesStored(context, payload, requireRegistered = false)
    }

    fun matchesRegistered(context: Context, payload: JSONObject): Boolean {
        return matchesStored(context, payload, requireRegistered = true)
    }

    private fun matchesStored(
        context: Context,
        payload: JSONObject,
        requireRegistered: Boolean
    ): Boolean {
        val contactId = payload.optString("contact_id")
        val sourceMessageId = payload.optString("source_message_id").toLongOrNull()
            ?: payload.optLong("source_message_id", 0L)
        if (contactId.isBlank() || sourceMessageId <= 0L) return false
        val encoded = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(key(contactId, sourceMessageId), null)
            ?: return !requireRegistered
        val expected = runCatching { JSONObject(encoded) }.getOrNull() ?: return false
        return payload.optString("client_route_id") == expected.optString("client_route_id") &&
            payload.optString("conversation_id") == expected.optString("conversation_id") &&
            payload.optString("task_id") == expected.optString("task_id") &&
            payload.optString("turn_id") == expected.optString("turn_id")
    }

    private fun key(contactId: String, sourceMessageId: Long): String =
        "${contactId.trim()}\u001f$sourceMessageId"
}
