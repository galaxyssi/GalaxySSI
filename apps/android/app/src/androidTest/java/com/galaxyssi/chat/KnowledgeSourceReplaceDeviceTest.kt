package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceReplaceDeviceTest {
    @Test fun replacementCrossesKeyPagesAndKeepsOneSourceEvent() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.replaceSource("\u6765\u6e90", (0..192).asSequence().map { f.item(it) }.constrainOnce())
        val before = f.items()
        f.store.upsert(f.item(999, "other"))
        val after = (65..201).map { f.item(it).copy(content = "updated $it") }
        f.store.replaceSource("\u6765\u6e90", after.asSequence().constrainOnce())
        assertEquals(GlobalPersistentContextObservationExtractor.knowledgeMutations(before, after, 1234), f.events)
        assertEquals(138L, f.store.stats().itemCount)
        assertEquals(after.toSet(), f.items().filter { it.source == "\u6765\u6e90" }.toSet())
        f.reopen()
        assertEquals(138L, f.store.stats().itemCount)
    }

    @Test fun producerFailureNeverMutatesCanonicalSource() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0))
        assertThrows(IllegalStateException::class.java) {
            f.store.replaceSource("\u6765\u6e90", sequence { yield(f.item(1)); error("fixture producer failure") })
        }
        assertEquals(listOf(f.item(0)), f.items()); assertEquals(0, f.visits)
    }

    @Test fun duplicatesUseFirstValidItemAndInvalidInputCannotEraseSource() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.replaceSource(" \u6765\u6e90 ", sequenceOf(f.item(0).copy(title = ""), f.item(0),
            f.item(0).copy(content = "discard"), f.item(1, "other"), f.item(2).copy(content = "")))
        assertEquals(listOf(f.item(0)), f.items())
        f.store.replaceSource("\u6765\u6e90", emptySequence())
        f.store.replaceSource(" ", sequence { error("Blank source must not consume input") })
        assertEquals(listOf(f.item(0)), f.items()); assertEquals(1, f.visits)
    }

    @Test fun lateSqlFailureRollsBackSourceAndEmitsNothing() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.replaceSource("\u6765\u6e90", (0..70).asSequence().map { f.item(it) })
        val before = f.items(); val visits = f.visits
        val reject = f.db.key("id", "replace-150")
        f.db.transaction { it.execSQL("CREATE TRIGGER reject_fixture BEFORE INSERT ON knowledge_items " +
            "WHEN NEW.item_key='$reject' BEGIN SELECT RAISE(ABORT,'fixture failure'); END") }
        assertThrows(Exception::class.java) { f.store.replaceSource("\u6765\u6e90", (80..150).asSequence().map { f.item(it) }) }
        assertEquals(before, f.items()); assertEquals(visits, f.visits)
        f.reopen(); assertEquals(before, f.items())
    }

    @Test fun lateCrossSourceCollisionCannotStealIdentity() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0)); f.store.upsert(f.item(100, "other"))
        val before = f.items()
        assertThrows(IllegalArgumentException::class.java) { f.store.replaceSource("\u6765\u6e90", (1..100).asSequence().map { f.item(it) }) }
        assertEquals(before, f.items()); assertEquals(0, f.visits)
    }

    @Test fun replayDoesNotInvalidateSourceRevisionOrEmitAnUpdate() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.replaceSource("\u6765\u6e90", (0..5).asSequence().map { f.item(it) })
        val revision = f.store.sourceRevision()
        f.store.replaceSource("\u6765\u6e90", (5 downTo 0).asSequence().map { f.item(it) })
        assertEquals(revision, f.store.sourceRevision()); assertTrue(f.events.isEmpty())
    }

    @Test fun oldestPolicyTieUsesTheExistingKeyOrder() = KnowledgeSourceReplaceFixture().use { f ->
        val first = f.item(0).copy(updatedAtMillis = 1, cloudAccess = AgentKnowledgeCloudAccess.FULL)
        val second = f.item(1).copy(updatedAtMillis = 1, cloudAccess = AgentKnowledgeCloudAccess.DENY)
        f.store.upsert(second); f.store.upsert(first)
        val expected = if (f.db.key("id", first.id) < f.db.key("id", second.id)) first else second
        f.store.replaceSource("\u6765\u6e90", sequenceOf(f.item(2)))
        assertEquals(expected.cloudAccess, f.items().single().cloudAccess)
    }

    @Test fun unchangedInputStillInheritsOldestSourcePolicy() = KnowledgeSourceReplaceFixture().use { f ->
        val first = f.item(0).copy(cloudAccess = AgentKnowledgeCloudAccess.FULL,
            agentAccess = AgentKnowledgeAgentAccess.SELECTED_AGENTS, allowedAgentIds = listOf("trusted"))
        val second = f.item(1)
        f.store.upsert(first); f.store.upsert(second)
        f.store.replaceSource("\u6765\u6e90", sequenceOf(first, second))
        val records = f.items()
        assertTrue(records.all { it.cloudAccess == AgentKnowledgeCloudAccess.FULL && it.allowedAgentIds == listOf("trusted") })
        assertEquals(GlobalConversationEventType.KNOWLEDGE_ACCESS_CHANGED, f.events.single().type)
    }

    @Test fun publicationRunsAfterCommitAndCannotRollItBack() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0))
        f.observer = { change ->
            assertEquals(listOf(f.item(1)), f.items())
            assertEquals(listOf(f.item(0)), change.items(true))
            error("fixture publication failure")
        }
        assertThrows(IllegalStateException::class.java) { f.store.replaceSource("\u6765\u6e90", sequenceOf(f.item(1))) }
        f.reopen(); assertEquals(listOf(f.item(1)), f.items())
    }

    @Test fun corruptedPreviousBodyPreventsReplacement() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0))
        f.db.transaction { it.execSQL("UPDATE knowledge_chunks SET ciphertext='invalid'") }
        assertThrows(Exception::class.java) { f.store.replaceSource("\u6765\u6e90", sequenceOf(f.item(1))) }
        assertEquals(1L, f.store.stats().itemCount); assertEquals(0, f.visits)
    }

    @Test fun interruptedProducerPublishesNothing() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(0))
        try {
            assertThrows(IllegalStateException::class.java) { f.store.replaceSource("\u6765\u6e90", sequence {
                yield(f.item(1)); Thread.currentThread().interrupt(); yield(f.item(2))
            }) }
        } finally { Thread.interrupted() }
        assertEquals(listOf(f.item(0)), f.items()); assertEquals(0, f.visits)
    }
}
