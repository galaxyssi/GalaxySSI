package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentResearchCheckpointTest {
    private fun row() = JSONObject().put("id", "school").put("kind", "finding").put("text", "Online program")
        .put("revision", 1).put("url", "https://school.edu/program").put("quote", "Online program")
        .put("provenance", "quote_observed_not_semantically_verified")
    private fun packet(vararg rows: JSONObject) = JSONObject().put("contract", AgentResearchCheckpoint.CONTRACT)
        .put("entries", JSONArray(rows.toList()))

    @Test fun keepsEvidenceProvenanceAndGapsForAnyProvider() {
        val gap = row().put("id", "fee").put("kind", "gap").put("text", "Fee unconfirmed").put("status", "open")
        val rows = AgentResearchCheckpoint.entries(packet(row(), gap))
        val handoff = AgentResearchCheckpoint.handoff(rows, false)
        assertTrue(handoff.contains("Online program"))
        assertTrue(handoff.contains("Fee unconfirmed"))
        assertTrue(handoff.contains("not_semantically_verified"))
        assertTrue(handoff.contains("Do not rerun"))
        val prompt = AgentResearchCheckpoint.append("Original goal and constraints", handoff)
        assertTrue(prompt.startsWith("Original goal and constraints"))
        assertEquals(prompt, AgentResearchCheckpoint.append(prompt, handoff))
    }

    @Test fun malformedOrOversizedRowsAreNotImported() {
        for (row in listOf(row().put("revision", 0), row().put("kind", "instruction"), row().put("text", "x".repeat(20000)))) {
            assertTrue(AgentResearchCheckpoint.entries(packet(row)).isEmpty())
        }
        assertTrue(AgentResearchCheckpoint.entries(JSONObject()).isEmpty())
        assertTrue(AgentResearchCheckpoint.entries(packet(*(1..25).map { row() }.toTypedArray())).isEmpty())
    }

    @Test fun unknownTrustLabelsDoNotBecomeVerifiedFacts() {
        val rows = AgentResearchCheckpoint.entries(packet(row().put("provenance", "verified").put("url", "https://secret@school.edu")))
        assertEquals("model_reported_unverified", rows.single().getString("provenance"))
        assertEquals("", rows.single().getString("url"))
    }

    @Test fun terminalPayloadRestoresAllPacketsWhenProgressWasCoalesced() {
        val packets = JSONArray()
        repeat(5) { batch -> packets.put(packet(*(0 until 24).map { index ->
            row().put("id", "program-${batch * 24 + index}")
        }.toTypedArray())) }
        val event = JSONObject().put("research_checkpoints", packets)
        val restored = AgentResearchCheckpoint.eventEntries(event)
        assertEquals(120, restored.size)
        assertEquals(120, restored.map { it.getString("id") }.toSet().size)
        assertTrue(AgentResearchCheckpoint.eventEntries(JSONObject().put("research_checkpoints",
            JSONArray((0..64).map { packet(row()) }))).isEmpty())
    }

    @Test fun emptyHandoffDoesNotChangePromptAndTruncationIsExplicit() {
        assertEquals("goal", AgentResearchCheckpoint.append("goal", ""))
        assertEquals("", AgentResearchCheckpoint.handoff(emptyList(), false))
        assertTrue(AgentResearchCheckpoint.handoff(listOf(row()), true).contains("\"truncated\":true"))
    }

    @Test fun hidesInternalBookkeepingButRetainsFailuresAndModelNarration() {
        val progress = JSONObject().put("kind", "tool").put("status", "completed")
            .put("detail", "research_checkpoint").put("metadata", JSONObject().put("code", "dynamic_tool"))
        assertTrue(AgentResearchCheckpoint.isInternalProgress(progress))
        assertTrue(AgentResearchCheckpoint.isInternalProgress(progress.put("status", "running")))
        assertFalse(AgentResearchCheckpoint.isInternalProgress(progress.put("status", "failed")))
        assertFalse(AgentResearchCheckpoint.isInternalProgress(progress.put("status", "completed").put("kind", "narration")))
        assertFalse(AgentResearchCheckpoint.isInternalProgress(progress.put("kind", "tool").put("detail", "another_tool")))
    }
}
