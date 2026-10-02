package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationReviewContractTest {
    private fun body() = JSONObject().put("acceptance_review", JSONObject()
        .put("criterion_id", "doc").put("requirement", "Document actual output")
        .put("target", JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64)))
        .put("verdict", "supported").put("rationale", "Compared original output with the exact document")
        .put("unresolved", JSONArray()))
    private fun rejected(body: JSONObject) = assertThrows(IllegalArgumentException::class.java) {
        CollaborationReviewContract.validate(CollaborationReviewContract.KIND, body)
    }

    @Test fun structuredReviewAndSeparateNonblockingSuggestionsAreAllowed() {
        CollaborationReviewContract.validate(CollaborationReviewContract.KIND,
            body().put("recommendations", JSONArray().put("An independent implementation could provide stronger evidence")))
    }

    @Test fun proseAndSerializedJsonAreNotReviewObjects() {
        assertTrue(rejected(JSONObject().put("content", body().toString())).message!!.contains("JSON object"))
        rejected(JSONObject().put("acceptance_review", body().getJSONObject("acceptance_review").toString()))
    }

    @Test fun supportedCannotConcealUnresolvedBlockers() {
        val value = body()
        value.getJSONObject("acceptance_review").put("unresolved", JSONArray().put("Original was not read"))
        rejected(value)
        value.getJSONObject("acceptance_review").put("verdict", "not_tested")
        CollaborationReviewContract.validate(CollaborationReviewContract.KIND, value)
    }

    @Test fun targetAndRequiredFieldsHaveStrictTypes() {
        listOf("criterion_id", "requirement", "rationale").forEach { field ->
            rejected(body().apply { getJSONObject("acceptance_review").put(field, 123) })
        }
        listOf(0, 1.5, "1", Long.MAX_VALUE).forEach { version ->
            rejected(body().apply { getJSONObject("acceptance_review").getJSONObject("target").put("revision", version) })
        }
        rejected(body().apply { getJSONObject("acceptance_review").getJSONObject("target").put("sha256", "invented") })
        rejected(body().apply { getJSONObject("acceptance_review").put("unresolved", "none") })
    }

    @Test fun ordinaryDecisionsDoNotBecomeAcceptanceReviews() {
        CollaborationReviewContract.validate("decision", JSONObject().put("content", "A design decision, not an acceptance certificate"))
    }

    @Test fun malformedPublicationIsAtomicAndCanBeRepairedInNewWork() {
        val data = sortedMapOf<String, String>()
        val workspace = CollaborationResearchWorkspace(object : CollaborationWorkspaceRows {
            override fun read(key: String) = data[key]
            override fun commit(values: Map<String, String>) { data.putAll(values) }
            override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        })
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "review", "reviewer")
        fun raw(body: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Review")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(
                JSONObject().put("id", "review").put("kind", CollaborationReviewContract.KIND).put("title", "Review").put("body", body))).toString()
        val bad = raw(JSONObject().put("content", "acceptance_review: supported"))
        val receipt = workspace.publish(access, bad)
        assertEquals("rejected", receipt.getString("status"))
        assertTrue(receipt.getString("reason").contains("body.acceptance_review"))
        assertTrue(workspace.browse(access).revisions.isEmpty())
        assertEquals(receipt.toString(), workspace.publish(access, bad).toString())
        assertEquals("rejected", workspace.publish(access, raw(body())).getString("status"))
        assertEquals("recorded", workspace.publish(access.copy(nodeId = "repair"), raw(body())).getString("status"))
    }
}
