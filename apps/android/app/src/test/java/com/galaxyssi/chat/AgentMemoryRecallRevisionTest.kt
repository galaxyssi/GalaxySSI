package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentMemoryRecallRevisionTest {
    @Test fun legacyMetadataUsesItsExistingRevision() {
        assertEquals("legacy", AgentMemoryRecallRevision.content(JSONObject().put("revision", "legacy")))
    }

    @Test fun accessChangesOnlyTheGeneralRevision() {
        val meta = AgentMemoryRecallRevision.advance(JSONObject())
        val initial = meta.getString("revision")
        repeat(10) { AgentMemoryRecallRevision.advance(meta, false) }
        assertNotEquals(initial, meta.getString("revision"))
        assertEquals(initial, AgentMemoryRecallRevision.content(meta))
    }

    @Test fun contentChangesAdvanceBothRevisions() {
        val meta = AgentMemoryRecallRevision.advance(JSONObject())
        val initial = AgentMemoryRecallRevision.content(meta)
        AgentMemoryRecallRevision.advance(meta)
        assertNotEquals(initial, AgentMemoryRecallRevision.content(meta))
        assertEquals(meta.getString("revision"), AgentMemoryRecallRevision.content(meta))
    }

    @Test fun olderWritersCannotHideBehindARecordedContentRevision() {
        val meta = AgentMemoryRecallRevision.advance(JSONObject()).put("revision", "older-writer")
        assertEquals("older-writer", AgentMemoryRecallRevision.content(meta))
        AgentMemoryRecallRevision.advance(meta, false)
        assertEquals("older-writer", AgentMemoryRecallRevision.content(meta))
    }

    @Test fun firstAccessToLegacyMetadataPreservesItsContentToken() {
        val meta = JSONObject().put("revision", "legacy")
        AgentMemoryRecallRevision.advance(meta, false)
        assertEquals("legacy", AgentMemoryRecallRevision.content(meta))
    }

    @Test fun IncompleteDerivedFieldsCannotMaskTheSourceRevision() {
        val meta = JSONObject().put("revision", "source").put("recall_observed_revision", "source")
        assertEquals("source", AgentMemoryRecallRevision.content(meta))
    }
}
