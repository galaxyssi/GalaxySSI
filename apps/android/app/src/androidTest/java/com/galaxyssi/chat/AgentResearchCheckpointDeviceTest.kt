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
class AgentResearchCheckpointDeviceTest {
    @Test fun recoveryRetainsFindingsAcrossReopenWithoutCrossTurnOrStaleOverwrite() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val conversation = "research-checkpoint-test-${UUID.randomUUID()}"
        fun event(revision: Long, text: String) = JSONObject().put("metadata", JSONObject().put("research_checkpoint",
            JSONObject().put("contract", AgentResearchCheckpoint.CONTRACT).put("entries", JSONArray().put(JSONObject()
                .put("id", "program").put("kind", "finding").put("text", text).put("revision", revision)
                .put("url", "https://example.org/program").put("quote", "").put("provenance", "model_reported_unverified")))))
        try {
            AgentResearchTraceStore.remote(context, conversation, "turn", event(1, "已查到在线博士，学费尚未确认"))
            AgentResearchTraceStore.remote(context, conversation, "turn", event(2, "已查到在线博士，仍需确认是否到校"))
            AgentResearchTraceStore.remote(context, conversation, "turn", event(1, "旧回执不得覆盖新进展"))
            val restored = AgentResearchTraceStore.recoveryHandoff(context, conversation, "turn")
            assertTrue(restored.contains("仍需确认是否到校"))
            assertFalse(restored.contains("旧回执"))
            val restoredPacket = JSONObject(restored.substring(restored.indexOf('{')))
            assertEquals("https://example.org/program", restoredPacket.getJSONArray("entries")
                .getJSONObject(0).getString("url"))
            assertEquals("", AgentResearchTraceStore.recoveryHandoff(context, conversation, "other-turn"))
            assertEquals("", AgentResearchTraceStore.recoveryHandoff(context, conversation + "-other", "turn"))
            // Terminal delivery must recover findings even if every progress packet was coalesced away.
            val packets = JSONArray()
            repeat(4) { batch ->
                val rows = JSONArray()
                repeat(24) { index -> rows.put(JSONObject().put("id", "batch-$batch-$index")
                    .put("kind", "finding").put("text", "保留的检索结果 $batch-$index")
                    .put("revision", 100 + batch * 24 + index).put("url", "https://example.org/$batch/$index")) }
                packets.put(JSONObject().put("contract", AgentResearchCheckpoint.CONTRACT).put("entries", rows))
            }
            AgentResearchTraceStore.remote(context, conversation, "terminal", JSONObject().put("research_checkpoints", packets))
            val terminal = AgentResearchTraceStore.recoveryHandoff(context, conversation, "terminal")
            assertEquals(96, JSONObject(terminal.substring(terminal.indexOf('{'))).getJSONArray("entries").length())
            AgentResearchTraceStore.delete(context, conversation)
            AgentResearchTraceStore.remote(context, conversation, "turn", event(3, "迟到回执不得复活已删除会话"))
            assertEquals("", AgentResearchTraceStore.recoveryHandoff(context, conversation, "turn"))
        } finally {
            AgentResearchTraceStore.delete(context, conversation)
        }
    }

    @Test fun inspectRealResearchHandoff() {
        val args = InstrumentationRegistry.getArguments()
        val conversation = args.getString("research_conversation").orEmpty()
        val turn = args.getString("research_turn").orEmpty()
        org.junit.Assume.assumeTrue(conversation.isNotBlank() && turn.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val handoff = AgentResearchTraceStore.recoveryHandoff(context, conversation, turn)
        assertTrue("No research evidence reached the phone", handoff.isNotBlank())
        val packet = JSONObject(handoff.substring(handoff.indexOf('{')))
        val rows = packet.getJSONArray("entries")
        val kinds = (0 until rows.length()).groupingBy { rows.getJSONObject(it).getString("kind") }.eachCount()
        assertTrue("No model findings persisted: $kinds", (kinds["finding"] ?: 0) > 0)
        assertTrue((0 until rows.length()).any { rows.getJSONObject(it).optString("url").startsWith("https://") })
        println("RESEARCH_HANDOFF kinds=$kinds chars=${handoff.length} truncated=${packet.optBoolean("truncated")}")
    }
}
