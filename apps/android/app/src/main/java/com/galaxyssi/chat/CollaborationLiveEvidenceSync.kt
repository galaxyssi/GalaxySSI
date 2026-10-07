package com.galaxyssi.chat

import org.json.JSONObject

internal object CollaborationLiveEvidenceSync {
    // A read RPC yields to its caller; the durable import can continue. This is not a research budget.
    fun budget(request: JSONObject, now: Long): Long =
        (request.optLong("expires_at") - now - 1_500L).coerceIn(0L, 10_000L)

    fun needed(request: JSONObject): Boolean {
        val arguments = request.optJSONObject("arguments") ?: return false
        return request.optString("phase") == "read" && arguments.optString("mode") in setOf("evidence", "problems") &&
            arguments.optString("evidence_id").isBlank() && arguments.optString("cursor").isBlank()
    }

    fun report(job: JSONObject?, fallback: String = "unavailable"): JSONObject = JSONObject()
        .put("status", job?.optString("status") ?: fallback)
        .put("scope", "current_assignment_only")
        .put("synced_through_sequence", job?.optLong("cursor") ?: 0L)
        .put("imported_observations", job?.optLong("imported") ?: 0L)
        .put("large_originals_not_imported", job?.optLong("skipped_large") ?: 0L)
        .put("archive_final", job?.optBoolean("archive_final") == true)
        .put("provider_history_complete", false)
        .put("coverage", "observed_completed_items_only")
        .put("trust", CollaborationRemoteEvidenceProtocol.TRUST)
        .put("guidance", "Only imported observations can be read and cited. Missing observations are not verified. " +
            "A live snapshot does not include future tool completions; browse the first page again after new work. " +
            "Pending imports resume without re-executing tools. Read original evidence before judging any claim.")
}
