package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.RandomAccessFile
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePayloadDeviceTest {
    @Test fun mixedInlineAndSegmentBodiesRetainSearchPoliciesAndIdentityAfterReopen() = KnowledgePayloadTestFixture().use { f ->
        val small = f.item(1, "\u672c\u5730 quartzplanet")
        val large = f.item(2).copy(cloudAccess = AgentKnowledgeCloudAccess.DENY,
            agentAccess = AgentKnowledgeAgentAccess.SELECTED_AGENTS, allowedAgentIds = listOf("trusted"))
        f.putLegacy(small); f.putLegacy(large)
        assertEquals(1L, f.count("knowledge_payloads")); assertEquals(1L, f.count("knowledge_chunks"))
        assertEquals(2L, f.count("knowledge_fts"))
        f.reopen()
        assertEquals(setOf(small, large), f.store.list(10).toSet())
        assertEquals(listOf(small), f.store.search("quartzplanet", 8))
        assertEquals(2L, f.store.stats().itemCount)
        assertTrue(f.root.walkTopDown().filter { it.extension == "seg" }.all { file ->
            !file.readBytes().toString(Charsets.UTF_8).contains("\u79c1\u5bc6\u77e5\u8bc6")
        })
    }
    @Test fun failedReferencePublicationPreservesOldRowAndOrphanCanBeReclaimed() = KnowledgePayloadTestFixture().use { f ->
        val old = f.item(1, "old-content")
        f.putLegacy(old)
        f.db.access { it.execSQL("CREATE TRIGGER fail_payload BEFORE INSERT ON knowledge_payloads BEGIN SELECT RAISE(ABORT,'fixture reference failure'); END") }
        try { assertThrows(Exception::class.java) { f.putLegacy(f.item(1)) } }
        finally { f.db.access { it.execSQL("DROP TRIGGER fail_payload") } }
        assertEquals(listOf(old), f.store.list(10)); assertEquals(0L, f.count("knowledge_payloads"))
        assertTrue(f.root.walkTopDown().any { it.extension == "seg" && it.length() > 0 })
        assertTrue(requireNotNull(f.db.reclaimPayloads()).bytes > 0)
        f.reopen(); assertEquals(listOf(old), f.store.list(10))
    }
    @Test fun backupSnapshotPinsOldBodiesWithoutBlockingConcurrentWriter() = KnowledgePayloadTestFixture().use { f ->
        val original = f.item(1); f.putLegacy(original)
        f.db.backupSnapshot().use { snapshot ->
            val executor = Executors.newSingleThreadExecutor()
            try { executor.submit {
                f.putLegacy(f.item(1, "replacement")); f.putLegacy(f.item(2))
            }.get(5, TimeUnit.SECONDS) } finally { executor.shutdownNow() }
            assertNull(f.db.reclaimPayloads())
            assertEquals(listOf(original), snapshot.items().toList())
        }
        assertNotNull(f.db.reclaimPayloads())
        assertEquals("replacement", f.store.findByIds(setOf(original.id)).single().content)
    }
    @Test fun sourceSnapshotSurvivesDeletionAndDefersReclamationUntilClosed() = KnowledgePayloadTestFixture().use { f ->
        val original = f.item(1); f.putLegacy(original)
        val selection = KnowledgeSourceSelection(f.db, AgentKnowledgeSourceReference(source = original.source))
        val revision = f.db.access(selection::revision)
        f.db.sourceSnapshot(selection, revision).use { snapshot ->
            f.db.transaction { it.delete("knowledge_items", null, null) }
            assertEquals(0L, f.count("knowledge_payloads")); assertNull(f.db.reclaimPayloads())
            assertEquals(original, snapshot.find(original.id))
            assertEquals(listOf(original), snapshot.items().toList())
        }
        assertTrue(requireNotNull(f.db.reclaimPayloads()).bytes > 0)
        f.reopen(); assertEquals(0L, f.store.stats().itemCount)
    }
    @Test fun migrationIsBoundedResumableAndDoesNotInvalidateDerivedIndexesOrSourceRevision() = KnowledgePayloadTestFixture().use { f ->
        val expected = (1..9).map { f.item(it) }
        expected.forEach(f::makeLegacy)
        assertEquals(9L, f.count("knowledge_chunks")); assertEquals(0L, f.count("knowledge_payloads"))
        val selection = KnowledgeSourceSelection(f.db, AgentKnowledgeSourceReference(source = expected.first().source))
        val revision = f.db.access(selection::revision)
        val browse = f.store.sourceRevision()
        val page = f.db.migratePayloadPage()
        assertEquals(4, page.visited); assertEquals(4, page.moved); assertFalse(page.complete)
        val checkpoint = f.checkpoint()
        f.reopen(); assertEquals(checkpoint, f.checkpoint())
        while (!f.db.migratePayloadPage().complete) { }
        assertEquals(0L, f.count("knowledge_chunks")); assertEquals(9L, f.count("knowledge_payloads"))
        assertEquals(9L, f.count("knowledge_fts")); assertEquals(browse, f.store.sourceRevision())
        assertEquals(revision, f.db.access(selection::revision))
        assertEquals(expected.toSet(), f.store.list(20).toSet())
        assertEquals(KnowledgePayloadMigration.Page(0, 0, true), f.db.migratePayloadPage())
    }
    @Test fun cancelledMigrationRollsBackReferencesChunksAndCursorTogether() = KnowledgePayloadTestFixture().use { f ->
        (1..5).forEach { f.makeLegacy(f.item(it)) }
        val checkpoint = f.checkpoint()
        var checked = 0
        assertThrows(IllegalStateException::class.java) { f.db.migratePayloadPage { if (++checked == 2) error("fixture cancelled") } }
        assertEquals(checkpoint, f.checkpoint()); assertEquals(0L, f.count("knowledge_payloads")); assertEquals(5L, f.count("knowledge_chunks"))
        f.reopen(); assertEquals(5, f.store.list(10).size)
        while (!f.db.migratePayloadPage().complete) { }
        assertEquals(5L, f.count("knowledge_payloads"))
    }
    @Test fun expiredSchedulingQuantumCommitsCompletedPrefixInsteadOfRepeatingItForever() = KnowledgePayloadTestFixture().use { f ->
        (1..5).forEach { f.makeLegacy(f.item(it)) }
        var checks = 0
        val page = f.db.migratePayloadPage { if (++checks == 2) throw MemoryMaintenanceYield() }
        assertEquals(KnowledgePayloadMigration.Page(1, 1, false), page)
        assertEquals(1L, f.count("knowledge_payloads")); assertEquals(4L, f.count("knowledge_chunks"))
        val checkpoint = f.checkpoint()
        f.reopen(); assertEquals(checkpoint, f.checkpoint())
        while (!f.db.migratePayloadPage().complete) { }
        assertEquals(5L, f.count("knowledge_payloads")); assertEquals(5, f.store.list(10).size)
    }
    @Test fun missingOrCorruptedPayloadNeverBecomesAnEmptySuccessfulResult() = KnowledgePayloadTestFixture().use { f ->
        val original = f.item(1); f.putLegacy(original)
        val file = f.root.walkTopDown().single { it.extension == "seg" }
        RandomAccessFile(file, "rw").use { bytes ->
            bytes.seek(bytes.length() - 1); val last = bytes.read()
            bytes.seek(bytes.length() - 1); bytes.write(last xor 1); bytes.fd.sync()
            assertThrows(Exception::class.java) { f.store.findByIds(setOf(original.id)) }
            bytes.seek(bytes.length() - 1); bytes.write(last); bytes.fd.sync()
        }
        assertEquals(listOf(original), f.store.list(10))
        f.db.transaction { it.delete("knowledge_payloads", null, null) }
        assertThrows(Exception::class.java) { f.store.findByIds(setOf(original.id)) }
        assertEquals(1L, f.store.stats().itemCount)
    }
    @Test fun closedOwnerStillPinsFilesUntilItsSnapshotLeaseIsReleased() = KnowledgePayloadTestFixture().use { f ->
        f.putLegacy(f.item(1))
        val snapshot = f.db.backupSnapshot()
        try {
            f.reopen(); f.db.transaction { it.delete("knowledge_items", null, null) }
            assertNull(f.db.reclaimPayloads())
            assertThrows(IllegalStateException::class.java) { snapshot.items().toList() }
        } finally { snapshot.close() }
        assertTrue(requireNotNull(f.db.reclaimPayloads()).bytes > 0)
    }
}
