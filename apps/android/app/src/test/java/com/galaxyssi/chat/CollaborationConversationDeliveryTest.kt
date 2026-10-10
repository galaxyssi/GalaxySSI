package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationConversationDeliveryTest {
    private class Fixture {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        val ledger = CollaborationEvidenceLedger(CollaborationGoalAcceptanceTest.Rows())
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "coordinator")
        val ref = JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64))
        val messages = mutableMapOf<String, String>()
        var writes = 0
        var failAfterWrite = false
        var failBeforeObservation = false
        fun deliver(who: CollaborationWorkspaceAccess = access, text: String = " Complete content \n"): JSONObject =
            CollaborationConversationDelivery(rows) { 20 }.record(who, ref, text, 10,
                persist = { key, value, _ ->
                    if (messages.putIfAbsent(key, value) == null) writes++
                    if (failAfterWrite) error("process died after transcript commit")
                }, observe = { owner, invocation, output, finish ->
                    if (failBeforeObservation) error("evidence store unavailable")
                    ledger.record(owner, invocation, CollaborationInterimDelivery.TOOL, ref.toString(), output.toString(),
                        output.getLong("requested_at"), finish, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
                })
    }

    @Test fun replayAndNewCoordinatorDispatchDoNotDuplicateOrClaimReadingOrCompletion() {
        val f = Fixture(); val receipt = f.deliver()
        assertEquals(receipt.toString(), f.deliver(f.access.copy(nodeId = "next", round = 2)).toString())
        assertEquals(1, f.writes)
        assertEquals("conversation_persisted", receipt.getString("status"))
        assertEquals("not_observed", receipt.getString("user_read"))
        assertEquals("not_implied", receipt.getString("goal_acceptance"))
        val ref = receipt.getJSONObject("observation")
        val original = f.ledger.read(f.access, ref.getString("evidence_id"), ref.getString("sha256"))!!
        assertEquals(CollaborationInterimDelivery.TOOL, original.getString("tool"))
        assertEquals("android_native_tool", original.getString("origin"))
        assertEquals(20L, original.getLong("finished_at"))
    }

    @Test fun crashAfterTranscriptCommitRecoversWithoutSecondMessage() {
        val f = Fixture(); f.failAfterWrite = true
        assertNotNull(runCatching { f.deliver() }.exceptionOrNull())
        assertTrue(f.ledger.browse(f.access).first.isEmpty())
        f.failAfterWrite = false
        assertEquals("conversation_persisted", f.deliver().getString("status"))
        assertEquals(1, f.writes)
    }

    @Test fun confirmedDeliveryIsNotRecreatedWhenReceiptRecordingRetries() {
        val f = Fixture(); f.failBeforeObservation = true
        assertNotNull(runCatching { f.deliver() }.exceptionOrNull())
        f.messages.clear() // A later user deletion does not request another delivery.
        f.failBeforeObservation = false
        assertEquals("conversation_persisted", f.deliver().getString("status"))
        assertTrue(f.messages.isEmpty())
        assertEquals(1, f.writes)
    }

    @Test fun differentRunsAndGroupsRemainSeparateAndMutatedTextIsRejected() {
        val f = Fixture(); f.deliver()
        assertThrows(IllegalArgumentException::class.java) { f.deliver(text = "Changed") }
        f.deliver(f.access.copy(runId = "next-run"))
        f.deliver(f.access.copy(groupId = "other-group"))
        assertEquals(3, f.writes)
    }

    @Test fun corruptJournalDoesNotProduceAnotherMessageOrReceipt() {
        val f = Fixture(); f.deliver()
        val key = f.rows.data.keys.single()
        f.rows.data[key] = f.rows.data.getValue(key).replace("recorded", "prepared")
        assertThrows(IllegalArgumentException::class.java) { f.deliver() }
        assertEquals(1, f.writes)
    }
}
