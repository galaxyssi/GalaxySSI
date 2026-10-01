package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationArchiveDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private fun execution(group: String, turn: String) = AgentTeamMemberExecutionContext(
        AgentTeamMember(agentId = "fixture", instanceId = "researcher", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = mapOf("collaboration_group_id" to group, "collaboration_name" to "Curie",
                CollaborationResearchWorkflow.STAGE to "VERIFY")),
        AgentRunRequest(group, turn, "task-$turn", runId = "run-$turn:verify", parentRunId = "run-$turn",
            goal = "Check historical constraints"), AgentSubagentContextHandoff("", emptyList(), 0, 100, false),
        1, AgentSubagentProvenance())

    private fun fixture(block: (String, CollaborationResearchArchive) -> Unit) {
        val id = "archive-test-" + UUID.randomUUID()
        val groups = CollaborationGroupStore(context)
        groups.update(id) { it }
        try { block(id, CollaborationResearchArchive(context, id)) } finally { groups.remove(id) }
    }

    @Test fun fullOriginalSurvivesSummaryCompressionAndPagedToolRecall() = fixture { group, archive ->
        val raw = "Public summary. " + "Background detail. ".repeat(1000) + "CRITICAL_ZEPHYR: never exceed 37 units."
        val id = archive.record(execution(group, "old-turn"), raw)
        assertEquals(id, archive.record(execution(group, "old-turn"), raw))
        val stored = requireNotNull(archive.read(id))
        assertFalse(stored.summary.contains("CRITICAL_ZEPHYR"))
        assertEquals(raw, JSONObject(stored.content).getString("raw_output"))
        assertTrue(archive.search("CRITICAL_ZEPHYR").any { it.id == id })
        val registry = AgentNativeToolRegistry().registerAll(CollaborationRecallNativeTool.definitions(context))
        val invocation = AgentNativeToolInvocationContext(conversationId = group, turnId = "new-turn")
        var offset = 0
        val reconstructed = StringBuilder()
        var pages = 0
        do {
            val result = registry.invoke(CollaborationRecallNativeTool.ID, mapOf("record_id" to id, "offset" to offset),
                invocation.copy(invocationId = UUID.randomUUID().toString()))
            assertTrue(result.toJson(), result.isSuccess)
            reconstructed.append(result.output["content"])
            pages++
            val next = result.output["next_offset"] as? Number
            offset = next?.toInt() ?: -1
        } while (offset >= 0 && pages < 10)
        assertTrue(pages > 1)
        assertEquals(stored.content, reconstructed.toString())
        assertFalse(registry.invoke(CollaborationRecallNativeTool.ID, mapOf("record_id" to id),
            invocation.copy(turnId = "old-turn", invocationId = UUID.randomUUID().toString())).isSuccess)
        fixture { other, otherArchive ->
            assertNull(otherArchive.read(id))
            assertFalse(registry.invoke(CollaborationRecallNativeTool.ID, mapOf("record_id" to id),
                invocation.copy(conversationId = other, invocationId = UUID.randomUUID().toString())).isSuccess)
        }
    }

    @Test fun revisionsDisagreementsAndHistoryBeyondTheSearchWindowRemainAvailable() = fixture { group, archive ->
        val expected = linkedSetOf<String>()
        repeat(65) { index ->
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
                .put("summary", "Checkpoint $index")
                .put("candidates", JSONArray()).put("findings", JSONArray())
                .put("memory", JSONArray().put(JSONObject().put("kind", if (index == 0) "constraint" else "rejected_route")
                    .put("text", "Checkpoint $index must remain available")
                    .put("source", "fixture:$index").put("supersedes", expected.firstOrNull().orEmpty()))).toString()
            expected += archive.record(execution(group, "turn-$index"), raw)
        }
        assertEquals(65, expected.size)
        val registry = AgentNativeToolRegistry().registerAll(CollaborationRecallNativeTool.definitions(context))
        val invocation = AgentNativeToolInvocationContext(conversationId = group, turnId = "new-turn")
        val seen = mutableSetOf<String>()
        var cursor = ""
        var pages = 0
        do {
            val result = registry.invoke(CollaborationRecallNativeTool.ID, mapOf("mode" to "browse", "cursor" to cursor),
                invocation.copy(invocationId = UUID.randomUUID().toString()))
            assertTrue(result.toJson(), result.isSuccess)
            val records = result.output["records"] as List<*>
            seen += records.map { (it as Map<*, *>)["record_id"].toString() }
            cursor = result.output["next_cursor"] as? String ?: ""
            pages++
        } while (cursor.isNotBlank() && pages < 10)
        assertEquals(expected, seen)
        val original = requireNotNull(archive.read(expected.first()))
        assertTrue(original.summary.contains("reported_constraint"))
        assertTrue(original.content.contains("Checkpoint 0 must remain available"))
        val replacement = requireNotNull(archive.read(expected.last()))
        assertTrue(replacement.content.contains(expected.first()))
        assertTrue(replacement.content.contains("model_reported_not_host_verified"))
        CollaborationGroupStore(context).remove(group)
        assertNull(archive.read(expected.first()))
    }
}
