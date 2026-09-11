package com.galaxyssi.chat

import org.json.JSONObject
import java.util.UUID

/** Keep access-only writes off the index, while detecting writers unaware of this token. */
internal object AgentMemoryRecallRevision {
    fun content(metadata: JSONObject): String {
        val revision = metadata.getString("revision")
        val content = metadata.optString("recall_content_revision")
        return if (metadata.optString("recall_observed_revision") == revision && content.isNotBlank()) content else revision
    }

    fun advance(metadata: JSONObject, contentChanged: Boolean = true): JSONObject {
        val revision = UUID.randomUUID().toString()
        val content = if (contentChanged) revision else content(metadata)
        return metadata.put("revision", revision).put("recall_observed_revision", revision)
            .put("recall_content_revision", content)
    }
}
