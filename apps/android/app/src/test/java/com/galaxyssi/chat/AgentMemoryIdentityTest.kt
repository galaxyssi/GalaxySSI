package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMemoryIdentityTest {
    private fun memory(id: String, scopeId: String = "conversation-a", value: String = "\u5317\u4eac") =
        AgentMemoryItem(AgentMemoryKind.PREFERENCE, value, id = id, key = "city",
            scope = AgentMemoryScope.CONVERSATION, scopeId = scopeId)

    @Test fun identicalValuesInDifferentConversationsAreNotDuplicates() {
        val store = InMemoryAgentMemoryStore()
        store.remember(memory("a"))
        assertFalse(store.remember(memory("b", "conversation-b")).duplicate)
        assertEquals(2, store.count())
    }

    @Test fun conflictingValuesInDifferentConversationsStayActive() {
        val store = InMemoryAgentMemoryStore()
        store.remember(memory("a"))
        assertNull(store.remember(memory("b", "conversation-b", "\u73e0\u6d77")).conflict)
        assertEquals(2, store.snapshot().activeItems.size)
    }

    @Test fun everyScopeTypeHasAnIndependentNamespace() {
        val store = InMemoryAgentMemoryStore()
        AgentMemoryScope.entries.forEach { scope ->
            val result = store.remember(memory(scope.name, "same-id").copy(scope = scope))
            assertFalse(scope.name, result.duplicate)
            assertNull(result.conflict)
        }
        assertEquals(AgentMemoryScope.entries.size, store.count())
    }

    @Test fun identifiersAreCaseSensitiveAndNotWhitespaceNormalized() {
        val store = InMemoryAgentMemoryStore()
        listOf("Scope", "scope", "scope ").forEachIndexed { index, id ->
            assertFalse(store.remember(memory("item-$index", id)).duplicate)
        }
        assertEquals(3, store.count())
    }

    @Test fun kindsRemainIndependentWithinTheSameScope() {
        val store = InMemoryAgentMemoryStore()
        AgentMemoryKind.entries.forEach { kind ->
            assertFalse(store.remember(memory(kind.name).copy(kind = kind)).duplicate)
        }
        assertEquals(AgentMemoryKind.entries.size, store.count())
    }

    @Test fun sameScopeDeduplicationStillWorks() {
        val store = InMemoryAgentMemoryStore()
        store.remember(memory("a"))
        val duplicate = store.remember(memory("b").copy(key = " CITY "))
        assertTrue(duplicate.duplicate)
        assertEquals("a", duplicate.item!!.id)
        assertEquals(1, store.count())
    }

    @Test fun sameScopeConflictCanStillBeResolved() {
        val store = InMemoryAgentMemoryStore()
        store.remember(memory("a"))
        val conflict = store.remember(memory("b", value = "\u73e0\u6d77")).conflict!!
        val resolved = store.resolveConflict(conflict.groupId, "b", null)!!
        assertEquals("\u73e0\u6d77", resolved.value)
        assertEquals(1, store.count())
        assertEquals(2, store.snapshot().historyItems.size)
    }

    @Test fun editAndDeleteDoNotTouchAnotherConversation() {
        val store = InMemoryAgentMemoryStore()
        store.remember(memory("a"))
        store.remember(memory("b", "conversation-b"))
        val edited = store.update("a", "\u73e0\u6d77")!!.item!!
        assertNull(store.snapshot().conflicts.firstOrNull())
        assertTrue(store.deleteById(edited.id))
        assertEquals(listOf("b"), store.snapshot().activeItems.map { it.id })
        assertTrue(store.snapshot().historyItems.isEmpty())
    }

    @Test fun deletingOldVersionFollowsRenamedKeysButNotForeignLineage() {
        val store = InMemoryAgentMemoryStore()
        store.items.addAll(listOf(
            memory("old").copy(status = AgentMemoryStatus.SUPERSEDED, supersedesId = "foreign"),
            memory("new").copy(key = "renamed", supersedesId = "old"),
            memory("foreign", "conversation-b").copy(supersedesId = "old")
        ))
        assertTrue(store.deleteById("old"))
        assertEquals(listOf("foreign"), store.items.map { it.id })
    }

    @Test fun lineageIgnoresMissingParentsForeignKindsAndCycles() {
        val target = memory("a").copy(supersedesId = "b")
        val cycle = memory("b").copy(supersedesId = "a")
        val foreign = memory("other").copy(kind = AgentMemoryKind.TASK, supersedesId = "a")
        assertEquals(setOf("a", "b"), AgentMemoryIdentity.lineageIds(listOf(target, cycle, foreign), target))
        assertEquals(setOf("a"), AgentMemoryIdentity.lineageIds(listOf(target.copy(supersedesId = "missing")), target))
    }

    @Test fun largeReverseOrderedLineageIsComplete() {
        val items = (0 until 10_000).map { index ->
            memory("id-$index").copy(supersedesId = if (index == 0) "" else "id-${index - 1}")
        }.reversed()
        assertEquals(10_000, AgentMemoryIdentity.lineageIds(items, items.first()).size)
    }

    private fun conflicted(item: AgentMemoryItem) =
        item.copy(status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "legacy-mixed-group")

    @Test fun legacyCrossScopeSingletonsBecomeRecallableWithoutLosingMetadata() {
        val store = InMemoryAgentMemoryStore()
        val first = memory("a").copy(important = true, confidence = 0.9, source = "local-source")
        val second = memory("b", "conversation-b").copy(privateMemory = true)
        store.items.addAll(listOf(conflicted(first), conflicted(second)))
        assertEquals(setOf(first, second), store.snapshot().activeItems.toSet())
        assertEquals(listOf(first), store.recall("\u5317\u4eac"))
    }

    @Test fun legacyMixedGroupsSplitDeterministicallyAndResolveIndependently() {
        val store = InMemoryAgentMemoryStore()
        val original = listOf(memory("a1"), memory("a2", value = "\u73e0\u6d77"),
            memory("b1", "conversation-b"), memory("b2", "conversation-b", "\u4e0a\u6d77"))
            .map(::conflicted)
        store.items.addAll(original)
        val normalized = AgentMemoryIdentity.normalizeConflicts(original)
        assertEquals(normalized, AgentMemoryIdentity.normalizeConflicts(normalized))
        val groups = store.snapshot().conflicts
        assertEquals(2, groups.size)
        assertEquals(2, groups.map { it.groupId }.distinct().size)
        val groupA = groups.single { it.candidates.any { candidate -> candidate.id == "a1" } }
        assertNull(store.resolveConflict(groupA.groupId, "b1", null))
        assertNotNull(store.resolveConflict(groupA.groupId, "a2", null))
        assertEquals(setOf("b1", "b2"), store.snapshot().conflicts.single().candidates.map { it.id }.toSet())
    }

    @Test fun conflictCandidatesRejectMixedScopeEvenBeforeMigration() {
        val items = listOf(conflicted(memory("a1")), conflicted(memory("a2")),
            conflicted(memory("b", "conversation-b")))
        assertEquals(listOf("a1", "a2"),
            AgentMemoryIdentity.conflictCandidates(items, "legacy-mixed-group", "a1").map { it.id })
    }

    @Test fun deletingOneMigratedGroupLeavesOtherConflictIntact() {
        val store = InMemoryAgentMemoryStore()
        store.items.addAll(listOf(memory("a1"), memory("a2"), memory("b1", "b"), memory("b2", "b"))
            .map(::conflicted))
        store.deleteById("a1")
        assertEquals(setOf("b1", "b2"), store.snapshot().conflicts.single().candidates.map { it.id }.toSet())
    }

    @Test fun blankConflictGroupIsRepairedAndValidGroupIsUnchanged() {
        val singleton = memory("a").copy(status = AgentMemoryStatus.CONFLICTED)
        assertEquals(AgentMemoryStatus.ACTIVE, AgentMemoryIdentity.normalizeConflicts(listOf(singleton)).single().status)
        val pair = listOf(conflicted(memory("b")), conflicted(memory("c")))
        assertSame(pair, AgentMemoryIdentity.normalizeConflicts(pair))
    }

    @Test fun deletionFingerprintsDoNotCollapseCaseSensitiveScopeIds() {
        val deleted = memory("a", "Case").copy(timestampMillis = 1)
        val other = memory("b", "case").copy(timestampMillis = 1)
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deleted), 2)!!
        assertTrue(tombstone.semanticFingerprints.single().startsWith("scope-v2:"))
        assertEquals(listOf(other), AgentMemoryCausalDeletionPolicy.filterRestoredItems(listOf(deleted, other), listOf(tombstone)))
    }

    @Test fun previouslyStoredDeletionHashesRemainRecognized() {
        val item = memory("old").copy(timestampMillis = 1)
        val bytes = listOf("PREFERENCE", "CONVERSATION", "conversation-a", "city")
            .joinToString("\u0000").toByteArray(Charsets.UTF_8)
        val legacy = java.security.MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val tombstone = AgentMemoryDeletionTombstone("legacy", emptySet(), setOf(legacy), emptySet(), 2)
        assertTrue(AgentMemoryCausalDeletionPolicy.filterRestoredItems(listOf(item), listOf(tombstone)).isEmpty())
    }
}
