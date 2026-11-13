package com.galaxyssi.chat

import org.json.JSONObject

internal enum class HealthCareAttentionState { WAITING, POSTED, IN_APP_ONLY, STALE }

/** A routine assessment update, not a clinical alarm or permission to execute a care action. */
internal data class HealthCareModelAttention(val concernId: String, val turnId: String, val conversationId: String,
    val createdAt: Long, val state: HealthCareAttentionState = HealthCareAttentionState.WAITING) {
    init {
        require(listOf(concernId, turnId, conversationId).all(HealthProfilePolicy::uuid) && createdAt > 0)
    }
    fun json() = JSONObject().put("concern", concernId).put("turn", turnId).put("conversation", conversationId)
        .put("created_at", createdAt).put("state", state.name)
    companion object {
        fun from(j: JSONObject) = HealthCareModelAttention(j.getString("concern"), j.getString("turn"),
            j.getString("conversation"), j.getLong("created_at"), HealthCareAttentionState.valueOf(j.getString("state")))
    }
}

/** Visibility is scoped to the health conversation, not any foreground Agent page. */
internal object HealthCareModelReviewVisibility {
    private val visible = java.util.WeakHashMap<Any, Pair<String, String>>()
    @Synchronized fun show(owner: Any, database: String, conversation: String): Boolean =
        (visible.put(owner, database to conversation) != (database to conversation))
    @Synchronized fun hide(owner: Any): Boolean = visible.remove(owner) != null
    @Synchronized fun contains(database: String, conversation: String) = visible.values.any { it == (database to conversation) }
}
