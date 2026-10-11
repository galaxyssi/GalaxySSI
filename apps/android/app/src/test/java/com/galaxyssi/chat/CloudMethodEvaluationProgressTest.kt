package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CloudMethodEvaluationProgressTest {
    private fun request(cursor: String = "") = JSONObject().put("mode", "method_history").put("view", "evaluations")
        .put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64)).put("cursor", cursor)
    private fun response(next: String? = null) = JSONObject().put("status", "returned").put("trust", CollaborationMethodEvaluations.TRUST)
        .put("view", "evaluations").put("method", CollaborationResearchCandidates.reference(request())).put("records", JSONArray())
        .put("scan_complete", next == null).put("next_cursor", next ?: JSONObject.NULL)

    @Test fun newEmptyScanPagesAreProgressButReplaysAreNot() {
        val progress = CloudMethodHistoryProgress()
        for ((cursor, next) in listOf("" to "page2", "page2" to "page3", "page3" to null)) {
            val encoded = response(next).toString()
            progress.record(request(cursor), encoded)
            assertEquals(true, progress.observe(encoded)); assertEquals(false, progress.observe(encoded))
        }
    }

    @Test fun failedUnboundOrNonAdvancingPagesCannotInventProgress() {
        for (change in listOf<(JSONObject) -> Unit>(
            { it.put("status", "failed") }, { it.put("trust", "model_report") },
            { it.getJSONObject("method").put("sha256", "c".repeat(64)) },
            { it.put("next_cursor", "same").put("scan_complete", false) }, { it.put("scan_complete", false) })) {
            val progress = CloudMethodHistoryProgress()
            val encoded = response().apply(change).toString()
            progress.record(request("same"), encoded)
            assertNull(progress.observe(encoded))
        }
    }

    @Test fun webLoopDoesNotStopAnAdvancingEvaluationScan() {
        val progress = CloudWebToolLoopProgress()
        repeat(5) { index ->
            val arguments = request("page$index")
            val encoded = response("page${index + 1}").toString()
            progress.record(CollaborationCloudRecall.NAME, arguments, encoded)
            assertFalse(progress.observeEvidenceBatch(listOf(encoded)))
        }
    }
}
