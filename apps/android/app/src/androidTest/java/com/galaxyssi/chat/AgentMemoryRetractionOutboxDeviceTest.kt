package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryRetractionOutboxDeviceTest {
    private fun fixture(test: (MemoryDeletionDeviceFixture) -> Unit) {
        val fixture = MemoryDeletionDeviceFixture()
        try { test(fixture) } finally { fixture.clear() }
    }

    @Test fun deletionIsPendingWithoutCallingPublish() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        assertTrue(f.store.deleteById("memory-1"))
        val reopened = f.reopen().deletionIndex
        val record = reopened.snapshot().single()
        assertEquals(AgentMemoryCausalDeletionPolicy.retractionEvents(record).toSet(), reopened.pendingRetractions().toSet())
        assertEquals(0, f.reopen().count())
    }

    @Test fun pendingInsertFailureRollsBackDeletionAndRecord() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        f.ledger.pendingRetractions()
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_outbox_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key LIKE 'memory-retraction:v1:pending:%' " +
                "BEGIN SELECT RAISE(ABORT, 'test_outbox_abort'); END")
            try {
                assertNotNull(runCatching { f.store.deleteById("memory-1") }.exceptionOrNull())
                assertEquals(1, f.reopen().count())
                assertTrue(f.ledger.snapshot().isEmpty())
                assertEquals(0, f.ledger.pendingRetractionCount())
            } finally { sql.execSQL("DROP TRIGGER test_outbox_abort") }
        }
    }

    @Test fun projectionFailureCannotAcknowledgePendingWork() = fixture { f ->
        f.ledger.record(listOf(deletionMemory(1)))
        val events = f.ledger.pendingRetractions()
        assertNotNull(runCatching {
            f.ledger.commitRetractionProjection(events.map { it.id }.toSet()) { error("projection failed") }
        }.exceptionOrNull())
        assertEquals(events, f.reopen().deletionIndex.pendingRetractions())
    }

    @Test fun committedProjectionWithFailedAckCanBeRecoveredWithoutDuplicateEffect() = fixture { f ->
        f.ledger.record(listOf(deletionMemory(1)))
        val events = f.ledger.pendingRetractions()
        val ids = events.map { it.id }.toSet()
        fun persistIdempotently() {
            if (!f.store.database.contains("test:projection-effect")) f.store.database.writeString("test:projection-effect", "1")
        }
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_ack_abort BEFORE DELETE ON encrypted_values " +
                "WHEN OLD.storage_key LIKE 'memory-retraction:v1:pending:%' " +
                "BEGIN SELECT RAISE(ABORT, 'test_ack_abort'); END")
            try {
                assertNotNull(runCatching { f.ledger.commitRetractionProjection(ids, ::persistIdempotently) }.exceptionOrNull())
                assertEquals("1", f.store.database.readString("test:projection-effect", ""))
                assertEquals(events, f.reopen().deletionIndex.pendingRetractions())
            } finally { sql.execSQL("DROP TRIGGER test_ack_abort") }
        }
        f.reopen().deletionIndex.commitRetractionProjection(ids, ::persistIdempotently)
        assertEquals("1", f.store.database.readString("test:projection-effect", ""))
        assertEquals(0, f.ledger.pendingRetractionCount())
        assertTrue(f.reopen().deletionIndex.pendingRetractions().isEmpty())
        assertEquals(1, f.ledger.snapshot().size)
    }

    @Test fun partialBatchAcknowledgesOnlyCompletedChunks() = fixture { f ->
        val record = f.ledger.record((0 until 200).map { deletionMemory(it) })!!
        val expected = AgentMemoryCausalDeletionPolicy.retractionEvents(record)
        assertTrue(expected.size > 1)
        val first = f.ledger.pendingRetractions(1).single()
        f.ledger.commitRetractionProjection(setOf(first.id)) { }
        assertEquals(expected.filterNot { it.id == first.id }.toSet(), f.reopen().deletionIndex.pendingRetractions().toSet())
    }

    @Test fun previousLedgerBootstrapsOnceAndDoesNotReviveAcknowledgedChunks() = fixture { f ->
        val record = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deletionMemory(1)), 2)!!
        f.store.database.writeString(EncryptedAgentMemoryDeletionIndex.MIGRATION_KEY, "1")
        f.store.database.writeString(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX + record.id,
            AgentMemoryCausalDeletionPolicy.encode(record).toString())
        assertEquals(0, f.ledger.pendingRetractionCount())
        val events = f.ledger.pendingRetractions()
        assertEquals(AgentMemoryCausalDeletionPolicy.retractionEvents(record), events)
        f.ledger.commitRetractionProjection(events.map { it.id }.toSet()) { }
        assertTrue(f.reopen().deletionIndex.pendingRetractions().isEmpty())
    }

    @Test fun interruptedBootstrapResumesFromDurableCursor() = fixture { f ->
        f.store.database.writeString(EncryptedAgentMemoryDeletionIndex.MIGRATION_KEY, "1")
        val records = (0 until 140).map { AgentMemoryCausalDeletionPolicy.tombstone(listOf(deletionMemory(it)), 2)!! }
        f.store.database.mutateStrings(records.associate {
            EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX + it.id to AgentMemoryCausalDeletionPolicy.encode(it).toString()
        })
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_outbox_ready_abort BEFORE INSERT ON encrypted_values " +
                "WHEN NEW.storage_key = 'memory-retraction:v1:ready' " +
                "BEGIN SELECT RAISE(ABORT, 'test_outbox_ready_abort'); END")
            try {
                assertNotNull(runCatching { f.ledger.pendingRetractions() }.exceptionOrNull())
                assertTrue(f.store.database.readString(AgentMemoryRetractionOutbox.CURSOR, "").isNotEmpty())
                assertFalse(f.store.database.contains(AgentMemoryRetractionOutbox.READY))
            } finally { sql.execSQL("DROP TRIGGER test_outbox_ready_abort") }
        }
        val expected = records.flatMap(AgentMemoryCausalDeletionPolicy::retractionEvents).map { it.id }.toSet()
        val actual = mutableSetOf<String>()
        while (true) {
            val page = f.reopen().deletionIndex.pendingRetractions(50)
            if (page.isEmpty()) break
            assertTrue(actual.intersect(page.map { it.id }.toSet()).isEmpty())
            actual.addAll(page.map { it.id })
            f.ledger.commitRetractionProjection(page.map { it.id }.toSet()) { }
        }
        assertEquals(expected, actual)
    }

    @Test fun corruptedReferenceDoesNotDisappearOrBecomeAcknowledged() = fixture { f ->
        f.ledger.record(listOf(deletionMemory(1)))
        val event = f.ledger.pendingRetractions().first()
        val key = AgentMemoryRetractionOutbox.PREFIX + event.id
        f.store.database.writeString(key, "invalid-reference")
        assertNotNull(runCatching { f.reopen().deletionIndex.pendingRetractions() }.exceptionOrNull())
        assertTrue(f.store.database.contains(key))
    }
}
