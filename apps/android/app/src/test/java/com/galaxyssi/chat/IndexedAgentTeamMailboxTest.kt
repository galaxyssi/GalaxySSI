package com.galaxyssi.chat

import java.util.TreeMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class IndexedAgentTeamMailboxTest {
    private class Rows : AgentTeamMailboxRows {
        val data = TreeMap<String, String>()
        var reads = 0
        var pages = 0
        var written = 0
        var commits = 0
        var fail = false
        var pageSize = 256
        override fun read(key: String): String? { reads++; return data[key] }
        override fun page(prefix: String, after: String, limit: Int): List<String> {
            pages++
            return data.tailMap(maxOf(prefix, after), after < prefix).keys.asSequence()
                .takeWhile { it.startsWith(prefix) }.take(minOf(limit, pageSize)).toList()
        }
        override fun pageBefore(prefix: String, before: String, limit: Int): List<String> {
            pages++
            return data.headMap(before.ifEmpty { "$prefix\uffff" }, false).descendingKeySet().asSequence()
                .takeWhile { it.startsWith(prefix) }.take(minOf(limit, pageSize)).toList()
        }
        override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) {
            check(!fail) { "Synthetic transaction failure" }
            removeKeys.forEach(data::remove)
            data.putAll(values)
            written += values.size
            commits++
        }
        fun resetCounts() { reads = 0; pages = 0; written = 0; commits = 0 }
    }

    private fun message(id: String, run: String = "run", to: String = "peer", pending: Boolean = true) = AgentTeamMessageEnvelope(
        messageId = id, teamId = "team", conversationId = "conversation-$run", supervisorRunId = run,
        fromInstanceId = "author", toInstanceId = to, kind = AgentTeamMessageKind.REVIEW,
        text = "Independent challenge $id", createdAtMillis = 100L,
        state = if (pending) AgentTeamMessageState.PENDING else AgentTeamMessageState.ACKNOWLEDGED,
        deliveredAtMillis = if (pending) 0L else 200L, acknowledgedAtMillis = if (pending) 0L else 250L)

    @Test fun tenThousandMessagesKeepOldPendingWorkAndHistoryAcrossReopen() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        val oldest = mailbox.append(message("oldest", run = "old-run"))
        mailbox.appendAll((1..10_000).map { message("message-$it", pending = it == 10_000) })
        val reopened = IndexedAgentTeamMailbox(rows)
        assertEquals(listOf(oldest), reopened.pendingMessages("old-run", "peer"))
        val history = reopened.messages("run")
        assertEquals(10_000, history.size)
        assertEquals((1L..10_000L).toList(), history.map { it.sequence })
        assertEquals(listOf(history.last()), reopened.pendingMessages("run", "peer"))
        assertEquals(history.first(), reopened.append(message("message-1")))
        assertEquals(10_001L, reopened.append(message("after-reopen")).sequence)
        assertEquals(10_001, reopened.messages("run").size)
        rows.resetCounts()
        assertEquals((9_982L..10_001L).toList(), reopened.recentMessages("run").map { it.sequence })
        assertEquals(21, rows.reads)
        assertEquals(1, rows.pages)
        assertEquals(0, rows.written)
    }

    @Test fun recentHistoryIsScopedChronologicalAndUnaffectedByLateReceipts() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        mailbox.appendAll((1..40).map { message("own-$it") })
        mailbox.appendAll((1..80).map { message("other-$it", run = "other") })
        mailbox.acknowledge("own-1", 999L)
        mailbox.markDelivered("own-40", 1_000L)
        assertEquals((21L..40L).toList(), mailbox.recentMessages("run").map { it.sequence })
        assertEquals(AgentTeamMessageState.DELIVERED, mailbox.recentMessages("run", 1).single().state)
        assertTrue(mailbox.recentMessages("missing").isEmpty())
        assertEquals((79L..80L).toList(), mailbox.recentMessages("other", 2).map { it.sequence })
        assertEquals(40, mailbox.messages("run").size)
    }

    @Test fun recentHistoryHandlesShortPagesAndLegacySequenceGapsWithoutRenumbering() {
        val rows = Rows().also { it.pageSize = 1 }
        val original = listOf(message("first").copy(sequence = 4_900L),
            message("second").copy(sequence = 20_000L), message("third").copy(sequence = Long.MAX_VALUE))
        rows.data["messages"] = AgentTeamMessageCodec.encode(original).toString()
        val mailbox = IndexedAgentTeamMailbox(rows)
        assertEquals(original.takeLast(2), mailbox.recentMessages("run", 2))
        assertEquals(original, mailbox.recentMessages("run", 20))
        assertEquals(InMemoryAgentTeamMailbox(original).recentMessages("run", 2), mailbox.recentMessages("run", 2))
        for (limit in listOf(-1, 0, 257)) {
            assertTrue(runCatching { mailbox.recentMessages("run", limit) }.isFailure)
            assertTrue(runCatching { InMemoryAgentTeamMailbox(original).recentMessages("run", limit) }.isFailure)
        }
    }

    @Test fun recentReadSurfacesCorruptRowsAndRejectsNonAdvancingReversePages() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        mailbox.append(message("one"))
        val key = rows.data.keys.single { it.contains("/message/") }
        val repeating = object : AgentTeamMailboxRows by rows {
            override fun pageBefore(prefix: String, before: String, limit: Int) = listOf(key)
        }
        assertTrue(runCatching { IndexedAgentTeamMailbox(repeating).recentMessages("run", 2) }.isFailure)
        rows.data[key] = "{broken"
        assertTrue(runCatching { mailbox.recentMessages("run") }.isFailure)
        assertEquals("{broken", rows.data[key])
    }

    @Test fun pendingReadAndSingleAppendDoNotScanOrRewriteAcknowledgedHistory() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        mailbox.appendAll((1..6_000).map { message("history-$it", pending = false) })
        val pending = mailbox.append(message("pending"))
        mailbox.appendAll((1..600).map { message("other-recipient-$it", to = "someone-else") })
        rows.resetCounts()
        assertEquals(listOf(pending), IndexedAgentTeamMailbox(rows).pendingMessages("run", "peer"))
        assertTrue("Read ${rows.reads} rows for one pending message", rows.reads <= 4)
        assertTrue(rows.pages <= 3)
        assertEquals(0, rows.written)
        rows.resetCounts()
        mailbox.append(message("new-message"))
        assertTrue(rows.reads <= 5)
        assertEquals(0, rows.pages)
        assertEquals(5, rows.written)
        assertEquals(1, rows.commits)
    }

    @Test fun directAndBroadcastPendingIndexesAreScopedAndOrdered() {
        val rows = Rows().also { it.pageSize = 1 }
        val mailbox = IndexedAgentTeamMailbox(rows)
        val broadcast = mailbox.append(message("broadcast", to = ""))
        val direct = mailbox.append(message("direct"))
        mailbox.append(message("elsewhere", run = "other-run"))
        val other = mailbox.append(message("other", to = "other-peer"))
        assertEquals(listOf(broadcast, direct), mailbox.pendingMessages("run", "peer"))
        assertEquals(listOf(broadcast, other), mailbox.pendingMessages("run", "other-peer"))
        assertEquals(listOf(broadcast, direct, other), mailbox.pendingMessages("run"))
        assertEquals(listOf(direct), mailbox.messages("run", "peer", broadcast.sequence))
        assertTrue(mailbox.messages("run", afterSequence = Long.MAX_VALUE).isEmpty())
    }

    @Test fun deliveryAndAcknowledgementRemovePendingIndexesButKeepOriginalContent() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        val original = mailbox.append(message("question").copy(text = "Independent reasoning ".repeat(500).trim(),
            metadata = mapOf("candidate_id" to "candidate-2")))
        val delivered = mailbox.markDelivered(original.messageId, 200L)!!
        assertTrue(mailbox.pendingMessages("run").isEmpty())
        assertTrue(mailbox.pendingMessages("run", "peer").isEmpty())
        assertEquals(200L, mailbox.markDelivered(original.messageId, 150L)!!.deliveredAtMillis)
        val acknowledged = mailbox.acknowledge(original.messageId, 180L)!!
        assertEquals(AgentTeamMessageState.ACKNOWLEDGED, acknowledged.state)
        assertEquals(200L, acknowledged.acknowledgedAtMillis)
        assertEquals(acknowledged, mailbox.markDelivered(original.messageId, 999L))
        assertEquals(acknowledged, IndexedAgentTeamMailbox(rows).append(original))
        assertEquals(delivered.text, acknowledged.text)
        assertEquals(original.metadata, acknowledged.metadata)
        assertNull(mailbox.acknowledge("missing", 999L))
    }

    @Test fun failedReceiptOrBatchRollsBackWithoutLosingPendingWorkOrSequence() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        val original = mailbox.append(message("first"))
        val saved = rows.data.toMap()
        rows.fail = true
        assertTrue(runCatching { mailbox.markDelivered("first", 200L) }.isFailure)
        assertTrue(runCatching { mailbox.appendAll(listOf(message("second"), message("third"))) }.isFailure)
        assertEquals(saved, rows.data)
        rows.fail = false
        val reopened = IndexedAgentTeamMailbox(rows)
        assertEquals(listOf(original), reopened.pendingMessages("run", "peer"))
        assertEquals(listOf(2L, 3L), reopened.appendAll(listOf(message("second"), message("third"))).map { it.sequence })
    }

    @Test fun entireBatchIsValidatedBeforeAnyPersistenceAndDuplicatesRemainIdempotent() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        assertTrue(runCatching { mailbox.appendAll(listOf(message("valid"), message("invalid").copy(text = ""))) }.isFailure)
        assertTrue(rows.data.isEmpty())
        val batch = mailbox.appendAll(listOf(message("one"), message("one").copy(text = "Duplicate changed"), message("two")))
        assertEquals(batch[0], batch[1])
        assertEquals(listOf(1L, 1L, 2L), batch.map { it.sequence })
        assertEquals(2, mailbox.messages("run").size)
    }

    @Test fun migrationRetainsEveryRecordStateAndSequenceAndDoesNotRepeatAfterClear() {
        val rows = Rows()
        val old = listOf(message("old-pending").copy(sequence = 4_900L), message("old-ack", pending = false).copy(sequence = 5_000L),
            message("other-run", run = "other-run").copy(sequence = 88L))
        rows.data["messages"] = AgentTeamMessageCodec.encode(old).toString()
        val mailbox = IndexedAgentTeamMailbox(rows)
        assertEquals(old.take(2), mailbox.messages("run"))
        assertEquals(listOf(old[0]), mailbox.pendingMessages("run", "peer"))
        assertFalse(rows.data.containsKey("messages"))
        assertEquals(5_001L, mailbox.append(message("new")).sequence)
        mailbox.clear("run")
        assertEquals(listOf(old.last()), IndexedAgentTeamMailbox(rows).messages("other-run"))
        assertTrue(mailbox.messages("run").isEmpty())
        assertEquals(1L, mailbox.append(message("new-run", run = "run")).sequence)
        mailbox.clear()
        assertTrue(IndexedAgentTeamMailbox(rows).messages("other-run").isEmpty())
        assertEquals(mapOf("mailbox.v2/schema" to "2"), rows.data)
    }

    @Test fun migrationIsAtomicAndDoesNotAcknowledgeUnknownOrCorruptLegacyRecords() {
        val raw = AgentTeamMessageCodec.encode(listOf(message("old").copy(sequence = 9L))).toString()
        for (bad in listOf("{broken", "[123]", JSONArray(raw).put(JSONObject().put("protocol", "team.v1")).toString(),
            raw.replace("PENDING", "UNRECOGNIZED"), raw.replace("Independent challenge old", " padded "),
            raw.replace("\"sequence\":9", "\"sequence\":9.2"))) {
            val rows = Rows().also { it.data["messages"] = bad }
            assertTrue("Must retain corrupt input: $bad", runCatching { IndexedAgentTeamMailbox(rows).append(message("new")) }.isFailure)
            assertEquals(mapOf("messages" to bad), rows.data)
        }
        val rows = Rows().also { it.data["messages"] = raw; it.fail = true }
        assertTrue(runCatching { IndexedAgentTeamMailbox(rows).messages("run") }.isFailure)
        assertEquals(mapOf("messages" to raw), rows.data)
        rows.fail = false
        assertEquals(9L, IndexedAgentTeamMailbox(rows).messages("run").single().sequence)
    }

    @Test fun migratedSequencesKeepLegacyOrderingAndRejectDuplicateIdentityWithoutDroppingIt() {
        val old = listOf(message("first").copy(sequence = 90L), message("second").copy(sequence = 0L))
        val rows = Rows().also { it.data["messages"] = AgentTeamMessageCodec.encode(old).toString() }
        assertEquals(listOf(90L, 91L), IndexedAgentTeamMailbox(rows).messages("run").map { it.sequence })
        val duplicate = AgentTeamMessageCodec.encode(listOf(old.first(), old.first())).toString()
        val badRows = Rows().also { it.data["messages"] = duplicate }
        assertTrue(runCatching { IndexedAgentTeamMailbox(badRows).pendingMessages("run") }.isFailure)
        assertEquals(mapOf("messages" to duplicate), badRows.data)
    }

    @Test fun concurrentStoreInstancesPreserveAtomicBatchesAndUniqueSequences() {
        val rows = Rows()
        val pool = Executors.newFixedThreadPool(4)
        try {
            (1..4).map { writer -> pool.submit<List<AgentTeamMessageEnvelope>> {
                IndexedAgentTeamMailbox(rows).appendAll((1..120).map { message("$writer-$it") })
            } }.forEach { it.get(30, TimeUnit.SECONDS) }
        } finally { pool.shutdownNow() }
        val saved = IndexedAgentTeamMailbox(rows).messages("run")
        assertEquals(480, saved.map { it.messageId }.distinct().size)
        assertEquals((1L..480L).toList(), saved.map { it.sequence })
    }

    @Test fun damagedRowAndCounterFailClosedWithoutOverwritingPriorMessages() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        mailbox.append(message("first"))
        val counter = rows.data.keys.single { it.endsWith("/sequence") }
        rows.data.remove(counter)
        val saved = rows.data.toMap()
        assertTrue(runCatching { mailbox.append(message("second")) }.isFailure)
        assertEquals(saved, rows.data)
        rows.data[counter] = "0"
        assertTrue(runCatching { mailbox.append(message("second")) }.isFailure)
        val row = rows.data.keys.single { it.contains("/message/") }
        rows.data[row] = "[]"
        assertTrue(runCatching { mailbox.pendingMessages("run", "peer") }.isFailure)
    }

    @Test fun failedScopedClearRetainsOtherRunsAndItsOwnPendingMessages() {
        val rows = Rows()
        val mailbox = IndexedAgentTeamMailbox(rows)
        mailbox.append(message("one"))
        mailbox.append(message("two", run = "other-run"))
        val snapshot = rows.data.toMap()
        rows.fail = true
        assertTrue(runCatching { mailbox.clear("run") }.isFailure)
        assertEquals(snapshot, rows.data)
        rows.fail = false
        mailbox.clear("run")
        assertTrue(mailbox.messages("run").isEmpty())
        assertEquals("two", mailbox.pendingMessages("other-run").single().messageId)
    }
}
