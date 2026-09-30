package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal object AgentDesktopArtifactReception {
    /** A stored final chunk is replayable until its application receipt is durably queued. */
    fun accept(
        context: Context,
        payload: JSONObject,
        publishReceipt: (AgentDesktopArtifactIngestResult) -> Boolean
    ): AgentDesktopArtifactIngestResult {
        val result = AgentDesktopArtifactStore.ingest(context, payload)
        if (result.completed) {
            check(publishReceipt(result)) { "Desktop artifact receipt was not durably queued" }
        }
        return result
    }
}
