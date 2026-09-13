package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorReplyCommitTest {
    @Test fun durableCheckpointAndTranscriptPrecedeInboxRetirementWithoutUi() {
        val stages = mutableListOf<String>()
        AgentConnectorReplyCommit.run({ stages += "checkpoint" }, { stages += "projection" },
            { stages += "old-delivery-complete" }, { stages += "next-delivery-bound" }, { stages += "retired" })
        assertEquals(listOf("checkpoint", "projection", "old-delivery-complete", "next-delivery-bound", "retired"), stages)
    }

    @Test fun checkpointFailureLeavesInboxAndProjectionUntouched() {
        var projected = false
        var retired = false
        assertTrue(runCatching {
            AgentConnectorReplyCommit.run({ error("disk full") }, { projected = true }, {}, {}, { retired = true })
        }.isFailure)
        assertFalse(projected)
        assertFalse(retired)
    }

    @Test fun projectionFailureDoesNotAcknowledgeReply() {
        var checkpointed = false
        var retired = false
        assertTrue(runCatching {
            AgentConnectorReplyCommit.run({ checkpointed = true }, { error("transcript failure") }, {}, {}, { retired = true })
        }.isFailure)
        assertTrue(checkpointed)
        assertFalse(retired)
    }

    @Test fun crashAfterProjectionCanReplayIdempotentProjectionBeforeRetirement() {
        val entries = mutableSetOf<String>()
        val usageReceipts = mutableSetOf<String>()
        var retired = false
        val projection = { entries.add("reply"); usageReceipts.add("usage"); Unit }
        assertTrue(runCatching {
            AgentConnectorReplyCommit.run({}, projection, {}, {}, { error("process stopped before retire") })
        }.isFailure)
        AgentConnectorReplyCommit.run({}, projection, {}, {}, { retired = true })
        assertEquals(1, entries.size)
        assertEquals(1, usageReceipts.size)
        assertTrue(retired)
    }

    @Test fun oldDeliveryCleanupCannotRemoveNewContinuationHead() {
        var head: String? = "old-source"
        AgentConnectorReplyCommit.run({}, {}, { head = null }, { head = "next-source" }, {})
        assertEquals("next-source", head)
    }

    @Test fun failedContinuationBindingKeepsInboxForRecovery() {
        var oldDeliveryCompleted = false
        var retired = false
        assertTrue(runCatching {
            AgentConnectorReplyCommit.run({}, {}, { oldDeliveryCompleted = true },
                { error("next binding could not be committed") }, { retired = true })
        }.isFailure)
        assertTrue(oldDeliveryCompleted)
        assertFalse(retired)
    }
}
