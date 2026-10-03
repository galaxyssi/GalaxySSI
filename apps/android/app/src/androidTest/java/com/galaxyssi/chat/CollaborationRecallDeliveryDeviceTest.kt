package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class CollaborationRecallDeliveryDeviceTest {
    @Test fun droppedDeliveryIsNotCoverageConfirmedPagesSurviveEncryptedReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "recall-delivery-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "reviewer").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        try {
            val author = CollaborationWorkspaceAccess(group, "run", "turn", 1, "author-node", "author")
            val reader = author.copy(nodeId = "review-node", personId = "reviewer", dependencyNodes = setOf("author-node"))
            val ledger = CollaborationEvidenceLedger(context)
            val ref = ledger.record(author, "invocation", "commandExecution", "{}", "original:" + "x".repeat(12_000), 1, 2,
                CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)
            val args = JSONObject().put("mode", "evidence").put("evidence_id", ref.getString("evidence_id"))
                .put("sha256", ref.getString("sha256"))
            val request = JSONObject().apply {
                AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
                put("execution_generation", 1).put("arguments", args).put("phase", "read")
            }
            val deliveries = CollaborationRecallDelivery()
            fun read() = JSONObject(CollaborationCloudRecall.execute(context, reader, args, recordCoverage = false))
                .put("success", true)
            fun coverage() = CollaborationEvidenceLedger(context).references(reader, JSONArray().put(ref))
                .getJSONObject(0).getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
            val dropped = deliveries.prepare(request, reader, read())
            assertTrue(dropped.has("delivery"))
            assertEquals(0, coverage().getInt("covered_characters"))
            val confirm = JSONObject(request.toString()).put("phase", "confirm").put("delivery", dropped.getJSONObject("delivery"))
            assertFalse(CollaborationRecallDelivery().confirm(confirm, reader) { _, _ -> fail("Lost process receipt"); null }.getBoolean("success"))
            var offset: Int? = 0
            while (offset != null) {
                args.put("offset", offset)
                val result = deliveries.prepare(request, reader, read())
                val ack = JSONObject(request.toString()).put("phase", "confirm").put("delivery", result.getJSONObject("delivery"))
                repeat(2) {
                    val committed = deliveries.confirm(ack, reader) { input, hash ->
                        CollaborationEvidenceLedger(context).confirmPage(reader, input.getString("evidence_id"),
                            input.getString("sha256"), input.optInt("offset", 0), hash)
                    }
                    assertTrue(committed.toString(), committed.getBoolean("success"))
                }
                offset = if (result.isNull("next_offset")) null else result.getInt("next_offset")
            }
            assertTrue(coverage().getBoolean("complete"))
            val original = ledger.read(reader, ref.getString("evidence_id"), ref.getString("sha256"))!!
            val frozen = ledger.references(reader, JSONArray().put(ref)).getJSONObject(0)
            CollaborationEvidenceReadCoverage.requireComplete(frozen, CollaborationEvidenceReadCoverage.identity(reader), original)
        } finally {
            CollaborationEvidenceLedger.remove(context, group)
            groups.remove(group)
        }
    }
}
