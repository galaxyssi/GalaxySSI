package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorSessionLookupTest {
    private val reads = mutableListOf<String>()
    private val removed = mutableListOf<String>()
    private val remembered = mutableListOf<String>()
    private var indexReads = 0
    private var scans = 0
    private var index: String? = null
    private var keys = listOf("task:old", "task:new")
    private var valid = setOf<String>()

    private fun find(turn: String = "", source: Long = 1L) = AgentConnectorSessionLookup.find(
        source, turn,
        indexed = { indexReads++; index },
        matches = { reads += it; it in valid },
        removeStaleIndex = { removed += it },
        legacyKeys = { scans++; keys.asSequence() },
        remember = { remembered += it }
    )

    @Test fun explicitTurnReadsOnlyItsOwnSnapshot() {
        valid = setOf("task:new")
        assertEquals("task:new", find("new"))
        assertEquals(listOf("task:new"), reads)
        assertEquals(0, scans)
        assertEquals(0, indexReads)
    }

    @Test fun explicitMissingTurnDoesNotScanTenThousandUnrelatedTasks() {
        keys = (1..10_000).map { "task:$it" }
        valid = keys.toSet()
        assertNull(find("missing"))
        assertEquals(listOf("task:missing"), reads)
        assertEquals(0, scans)
    }

    @Test fun explicitMismatchCannotFallBackToAnotherIndexedTurn() {
        index = "task:old"
        valid = setOf("task:old")
        assertNull(find("new"))
        assertEquals(0, indexReads)
        assertTrue(removed.isEmpty())
    }

    @Test fun explicitTurnIsTrimmed() {
        valid = setOf("task:new")
        assertEquals("task:new", find(" new "))
    }

    @Test fun invalidSourceDoesNotTouchStorage() {
        assertNull(find("new", 0))
        assertNull(find(source = -1))
        assertTrue(reads.isEmpty())
        assertEquals(0, indexReads)
        assertEquals(0, scans)
    }

    @Test fun legacyIndexedHitDoesNotScan() {
        index = "task:old"
        valid = setOf("task:old")
        assertEquals("task:old", find())
        assertEquals(listOf("task:old"), reads)
        assertEquals(0, scans)
    }

    @Test fun staleLegacyIndexIsRemovedWithoutLoadingItTwice() {
        index = "task:old"
        valid = setOf("task:new")
        assertEquals("task:new", find())
        assertEquals(listOf("task:old", "task:new"), reads)
        assertEquals(listOf("task:old"), removed)
        assertEquals(listOf("task:new"), remembered)
    }

    @Test fun legacyUnindexedMatchIsStillRecoverable() {
        valid = setOf("task:new")
        assertEquals("task:new", find("  "))
        assertEquals(1, scans)
        assertEquals(listOf("task:new"), remembered)
    }

    @Test fun legacyMissingSnapshotDoesNotInventAnIndex() {
        assertNull(find())
        assertEquals(keys, reads)
        assertTrue(remembered.isEmpty())
    }

    @Test fun explicitLateArrivalIsNotHiddenByNegativeCaching() {
        assertNull(find("new"))
        valid = setOf("task:new")
        assertEquals("task:new", find("new"))
        assertEquals(listOf("task:new", "task:new"), reads)
    }
}
