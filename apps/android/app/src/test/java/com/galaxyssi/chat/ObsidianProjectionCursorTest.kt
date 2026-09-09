package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ObsidianProjectionCursorTest {
    private class Fixture(val size: Int) {
        var revision = 1L
        var checkpoint: ObsidianProjectionCheckpoint? = null
        val index = mutableMapOf<Int, Long>()
        val writes = mutableMapOf<Int, Int>()
        val starts = mutableListOf<Int>()
        var summaries = 0
        var failSave = false
        var afterVisit: () -> Unit = {}
        fun page(cursor: AgentKnowledgeSourceCursor?): AgentKnowledgeSourcePage {
            require(cursor == null || cursor.scope == "fixture")
            if (cursor != null && cursor.revision != revision) throw KnowledgeSourcePageChanged()
            val start = cursor?.groupKey?.toInt()?.plus(1) ?: 0
            starts += start
            val ids = (start until minOf(size, start + 50)).toList()
            summaries += ids.size
            val groups = ids.map { AgentKnowledgeSourceGroup(it.toString(), "note", emptySet(), 1,
                AgentKnowledgeCloudAccess.DENY, AgentKnowledgeAgentAccess.LOCAL_ONLY, emptyList(), 1) }
            val positions = ids.map { AgentKnowledgeSourceCursor(1, it.toString(), revision, "fixture") }
            return AgentKnowledgeSourcePage(groups, size, positions.lastOrNull()?.takeIf { start + ids.size < size }, positions, revision)
        }
        fun run(budget: Int = 12, namespace: String = "vault") = ObsidianProjectionCursor.run(namespace, checkpoint, budget,
            ::page, { revision }, { group, remaining ->
                val id = group.source.toInt()
                val result = when {
                    index[id] == revision -> ObsidianProjectionBatchResult(0, 1, 0)
                    remaining == 0 -> ObsidianProjectionBatchResult(0, 0, 1)
                    else -> {
                        index[id] = revision
                        writes[id] = writes.getOrDefault(id, 0) + 1
                        ObsidianProjectionBatchResult(1, 0, 0)
                    }
                }
                afterVisit()
                result
            }, { value ->
                if (failSave) { failSave = false; error("checkpoint unavailable") }
                checkpoint = value?.let { requireNotNull(ObsidianProjectionCheckpoint.decode(it.encode())) }
            })
    }

    @Test fun fullCorpusDrainsWithoutRepeatedPrefixScans() {
        val f = Fixture(1201)
        assertEquals(ObsidianProjectionBatchResult(12, 0, 1189), f.run())
        assertEquals(12, requireNotNull(f.checkpoint).visited)
        var result: ObsidianProjectionBatchResult
        do { result = f.run(32) } while (result.remaining > 0)
        assertEquals(1201, f.index.size)
        assertTrue(f.writes.values.all { it == 1 })
        assertTrue(f.summaries <= 1950)
        assertTrue(f.starts.zipWithNext().all { (a, b) -> b > a })
        assertNull(f.checkpoint)
    }

    @Test fun unchangedCorpusStillHasBoundedVisitsAndZeroWrites() {
        val f = Fixture(1201)
        repeat(1201) { f.index[it] = f.revision }
        assertEquals(ObsidianProjectionBatchResult(0, 50, 1151), f.run())
        assertEquals(50, f.summaries)
        var unchanged = 50
        var result: ObsidianProjectionBatchResult
        do { result = f.run(); unchanged += result.unchanged } while (result.remaining > 0)
        assertEquals(1201, unchanged)
        assertTrue(f.writes.isEmpty())
    }

    @Test fun committedWriteBeforeCheckpointFailureIsNotWrittenTwice() {
        val f = Fixture(3)
        f.failSave = true
        assertThrows(IllegalStateException::class.java) { f.run(1) }
        assertNull(f.checkpoint)
        assertEquals(ObsidianProjectionBatchResult(2, 1, 0), f.run(2))
        assertEquals(1, f.writes[0])
    }

    @Test fun corpusChangeBetweenRoundsRestartsAndRevisitsEarlierUpdates() {
        val f = Fixture(3)
        f.run(1)
        f.revision++
        f.run(3)
        assertEquals(listOf(0, 0), f.starts)
        assertTrue(f.index.values.all { it == f.revision })
        assertNull(f.checkpoint)
    }

    @Test fun mutationDuringLastPageCannotClaimCompletion() {
        val f = Fixture(1)
        f.afterVisit = { f.revision++ }
        assertEquals(1, f.run().remaining)
        assertNull(f.checkpoint)
        f.afterVisit = {}
        assertEquals(0, f.run().remaining)
    }

    @Test fun namespaceAndDatabaseScopeCannotReuseAnotherCursor() {
        val f = Fixture(3)
        f.run(1)
        f.run(1, "another-vault")
        assertEquals(0, f.starts.last())
        f.checkpoint = requireNotNull(f.checkpoint).copy(cursor = requireNotNull(f.checkpoint).cursor.copy(scope = "other-db"))
        f.run(1, "another-vault")
        assertEquals(0, f.starts.last())
    }

    @Test fun zeroWriteBudgetDoesNotAdvancePastPendingSource() {
        val f = Fixture(3)
        assertEquals(ObsidianProjectionBatchResult(0, 0, 3), f.run(0))
        assertNull(f.checkpoint)
        assertTrue(f.writes.isEmpty())
    }

    @Test fun invalidCheckpointFailsClosedAndEmptyCorpusCompletes() {
        assertNull(ObsidianProjectionCheckpoint.decode("invalid"))
        assertNull(ObsidianProjectionCheckpoint.decode("{\"visited\":-1}"))
        assertEquals(ObsidianProjectionBatchResult(0, 0, 0), Fixture(0).run())
    }
}
