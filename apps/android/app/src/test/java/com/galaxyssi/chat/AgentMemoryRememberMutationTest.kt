package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMemoryRememberMutationTest {
    private val item = AgentMemoryItem(AgentMemoryKind.PREFERENCE, "Chinese", id = "one", key = "language",
        scope = AgentMemoryScope.CONVERSATION, scopeId = "chat", timestampMillis = 1)

    @Test fun uniqueMemoryOnlyAddsOneRecord() {
        val change = AgentMemoryRememberMutation.plan(item, emptyList(), 100)
        assertTrue(change.before.isEmpty())
        assertEquals(listOf(item), change.after)
        assertFalse(change.result.duplicate)
    }

    @Test fun duplicatePreservesIdentityPrivacyAndSourceWhileMergingEvidence() {
        val old = item.copy(privateMemory = true, source = "original", confidence = 0.5, evidenceCount = 4)
        val next = item.copy(id = "ignored-new-id", value = "CHINESE", confidence = 0.9, evidenceCount = 3, expiresAtMillis = 500)
        val change = AgentMemoryRememberMutation.plan(next, listOf(old), 100)
        assertTrue(change.result.duplicate)
        assertEquals(old.copy(confidence = 0.9, evidenceCount = 7, lastConfirmedAtMillis = 100, expiresAtMillis = 500), change.result.item)
    }

    @Test fun evidenceAdditionCannotWrapNegative() {
        val change = AgentMemoryRememberMutation.plan(item.copy(evidenceCount = Int.MAX_VALUE), listOf(item.copy(evidenceCount = Int.MAX_VALUE)), 100)
        assertEquals(10_000, change.result.item!!.evidenceCount)
    }

    @Test fun conflictChangesOnlyMatchingCandidatesAndPreservesLineage() {
        val change = AgentMemoryRememberMutation.plan(item.copy(id = "two", value = "English"), listOf(item), 100)
        assertEquals(listOf(item), change.before)
        assertEquals(setOf("one", "two"), change.after.map { it.id }.toSet())
        assertTrue(change.after.all { it.status == AgentMemoryStatus.CONFLICTED })
        assertEquals(2, change.result.item!!.version)
        assertEquals("one", change.result.item!!.supersedesId)
        assertEquals(2, change.result.conflict!!.candidates.size)
    }

    @Test fun existingConflictGroupAndHigherVersionAreRetained() {
        val candidates = listOf(item.copy(status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "group", version = 2),
            item.copy(id = "two", value = "English", status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "group", version = 4))
        val change = AgentMemoryRememberMutation.plan(item.copy(id = "three", value = "French"), candidates, 100)
        assertEquals("group", change.result.conflict!!.groupId)
        assertEquals(5, change.result.item!!.version)
        assertEquals("two", change.result.item!!.supersedesId)
    }

    @Test fun unkeyedDifferentValuesDoNotBecomeConflicts() {
        val change = AgentMemoryRememberMutation.plan(item.copy(id = "two", key = "", value = "English"), listOf(item.copy(key = "")), 100)
        assertNull(change.result.conflict)
        assertEquals(1, change.after.size)
        assertTrue(change.before.isEmpty())
    }

    @Test fun foreignNamespaceAndHistoryAreRejectedAsCandidates() {
        for (wrong in listOf(item.copy(scopeId = "other"), item.copy(status = AgentMemoryStatus.SUPERSEDED))) {
            assertNotNull(runCatching { AgentMemoryRememberMutation.plan(item, listOf(wrong), 100) }.exceptionOrNull())
        }
    }

    @Test fun versionOverflowDoesNotCreateAnInvalidRevision() {
        assertNotNull(runCatching { AgentMemoryRememberMutation.plan(item.copy(value = "English"), listOf(item.copy(version = Int.MAX_VALUE)), 100) }.exceptionOrNull())
    }

    @Test fun targetOnlyObservationMatchesWholeCollectionForConflictAndDuplicate() {
        val other = item.copy(id = "unrelated", scopeId = "private", privateMemory = true)
        for (next in listOf(item.copy(id = "two", value = "English"), item.copy(id = "two"))) {
            val change = AgentMemoryRememberMutation.plan(next, listOf(item), 100)
            val full = GlobalPersistentContextObservationExtractor.memoryMutations(change.before + other, change.after + other, 100)
            val delta = GlobalPersistentContextObservationExtractor.memoryMutations(change.before, change.after, 100)
            assertEquals(full, delta)
        }
    }

    @Test fun repeatedEvidenceCannotRegressConfirmationOrExpiry() {
        val old = item.copy(lastConfirmedAtMillis = 500, expiresAtMillis = 900, confidence = 0.95)
        val change = AgentMemoryRememberMutation.plan(item.copy(lastConfirmedAtMillis = 2, expiresAtMillis = 4, confidence = 0.1), listOf(old), 100)
        assertEquals(500L, change.result.item!!.lastConfirmedAtMillis)
        assertEquals(900L, change.result.item!!.expiresAtMillis)
        assertEquals(0.95, change.result.item!!.confidence, 0.0)
    }
}
