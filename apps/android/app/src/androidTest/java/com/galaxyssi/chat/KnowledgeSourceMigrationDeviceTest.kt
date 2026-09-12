package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceMigrationDeviceTest {
    @Test fun automaticVersionSevenMigrationPreservesCiphertextAndDoesNotLoadModels() = KnowledgeBackupTestFixture().use { f ->
        f.seed(137)
        f.db.transaction(KnowledgePrimaryLegacyFixture::inlineForDowngrade)
        val before = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        KnowledgeSourceMigrationTestSupport.versionSeven(f)
        f.db.access { db ->
            assertEquals(0L, KnowledgeSourceDirectory.state(db).items)
            assertThrows(KnowledgeSourceDirectoryNotReady::class.java) { f.store.sourcePage() }
        }
        KnowledgeSourceMigrationTestSupport.awaitReady(f)
        assertEquals(137, f.store.sourceCount())
        assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
        val bodyReads = f.db.decryptedItemReads
        var cursor: AgentKnowledgeSourceCursor? = null
        var expected = 137
        do {
            val page = f.store.sourcePage(cursor, 50)
            page.groups.forEach { KnowledgeSourceMigrationTestSupport.assertGroup(it, expected--) }
            cursor = page.next
        } while (cursor != null)
        assertEquals(0, expected); assertEquals(bodyReads, f.db.decryptedItemReads)
        assertEquals("not_configured", f.store.semanticSearchStatus)
        f.db.backupSnapshot().use { snapshot ->
            var verified = 0
            snapshot.items().forEach { item -> assertEquals(f.item(item.id.removePrefix("backup-").toInt()), item); verified++ }
            assertEquals(137, verified)
        }
    }

    @Test fun workerFailureIsVisibleAndRetryContinuesWithoutSourceLoss() = KnowledgeBackupTestFixture().use { f ->
        f.seed(65)
        f.db.transaction(KnowledgePrimaryLegacyFixture::inlineForDowngrade)
        val before = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        KnowledgeSourceMigrationTestSupport.versionSeven(f)
        f.db.access { db -> db.execSQL("CREATE TRIGGER reject_source_enrollment BEFORE INSERT ON knowledge_source_members " +
            "BEGIN SELECT RAISE(ABORT,'fixture migration failure'); END") }
        val failed = CountDownLatch(1)
        f.store.observeSourceDirectory { failed.countDown() }.use { assertTrue(failed.await(30, TimeUnit.SECONDS)) }
        assertTrue(f.db.sourceMaintenance.failure.orEmpty().contains("fixture migration failure"))
        val error = assertThrows(IllegalStateException::class.java) { f.store.sourceCount() }
        assertTrue(error.message.orEmpty().contains("fixture migration failure"))
        f.db.access { db ->
            assertEquals(0L, KnowledgeSourceDirectory.state(db).items)
            db.execSQL("DROP TRIGGER reject_source_enrollment")
        }
        f.store.retrySourceDirectory()
        KnowledgeSourceMigrationTestSupport.awaitReady(f)
        assertEquals(65, f.store.sourceCount())
        assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
    }

    @Test fun completedDirectoryNotifiesLateObserversAndKeepsCursorAcrossReopen() = KnowledgeBackupTestFixture().use { f ->
        f.seed(65)
        val ready = CountDownLatch(1)
        f.store.observeSourceDirectory { ready.countDown() }.use { assertTrue(ready.await(30, TimeUnit.SECONDS)) }
        val first = f.store.sourcePage(limit = 50)
        f.reopen()
        val rest = f.store.sourcePage(requireNotNull(first.next), 50)
        assertEquals(15, rest.groups.size); assertNull(rest.next)
        rest.groups.forEachIndexed { index, group -> KnowledgeSourceMigrationTestSupport.assertGroup(group, 15 - index) }
    }
}
