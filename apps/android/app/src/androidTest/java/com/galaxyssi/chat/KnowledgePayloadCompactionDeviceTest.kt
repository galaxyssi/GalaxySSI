package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePayloadCompactionDeviceTest {
    @Test fun relocationCommitsBeforeOldFileDeletionAndPreservesLogicalRevision() = KnowledgePayloadTestFixture().use { f ->
        val item = KnowledgePayloadCompactionFixture.fragmented(f)
        val old = KnowledgePayloadCompactionFixture.row(f, item.id)
        val path = KnowledgePayloadCompactionFixture.path(f, old)
        val clock = revision(f)
        assertFalse(requireNotNull(f.db.reclaimPayloads()).complete)
        assertTrue("Old segment must outlive the relocation transaction", path.isFile)
        assertNotEquals(old.value, KnowledgePayloadCompactionFixture.row(f, item.id).value)
        f.reopen()
        assertEquals(item, f.store.findByIds(setOf(item.id)).single())
        assertEquals(clock, revision(f))
        assertTrue(KnowledgePayloadCompactionFixture.finish(f) > 0)
        assertFalse(path.exists()); KnowledgePayloadUsageDeviceTest.exact(f)
    }

    @Test fun failedReferencePublicationNeverDeletesRecoverableSourceBytes() = KnowledgePayloadTestFixture().use { f ->
        val item = KnowledgePayloadCompactionFixture.fragmented(f)
        val old = KnowledgePayloadCompactionFixture.row(f, item.id)
        val path = KnowledgePayloadCompactionFixture.path(f, old)
        f.db.transaction { it.execSQL("CREATE TRIGGER reject_payload_copy BEFORE UPDATE OF reference ON knowledge_payloads " +
            "BEGIN SELECT RAISE(ABORT,'fixture copy failure'); END") }
        assertThrows(Exception::class.java) { f.db.reclaimPayloads() }
        f.reopen()
        assertTrue(path.isFile); assertEquals(old.value, KnowledgePayloadCompactionFixture.row(f, item.id).value)
        assertEquals(item, f.store.findByIds(setOf(item.id)).single()); KnowledgePayloadUsageDeviceTest.exact(f)
        f.db.transaction { it.execSQL("DROP TRIGGER reject_payload_copy") }
        assertTrue(KnowledgePayloadCompactionFixture.finish(f) > 0)
    }

    @Test fun activeBackupPreventsCompactionUntilItsOldViewIsReleased() = KnowledgePayloadTestFixture().use { f ->
        val item = KnowledgePayloadCompactionFixture.fragmented(f)
        val old = KnowledgePayloadCompactionFixture.row(f, item.id)
        f.db.backupSnapshot().use { snapshot ->
            assertNull(f.db.reclaimPayloads())
            f.putLegacy(f.item(20))
            assertEquals(listOf(item), snapshot.items().toList())
            assertEquals(old.value, KnowledgePayloadCompactionFixture.row(f, item.id).value)
        }
        assertTrue(KnowledgePayloadCompactionFixture.finish(f) > 0)
        assertEquals(2L, f.store.stats().itemCount)
    }

    @Test fun largeRecordResumesFrameCopyAndReadbackVerificationAcrossReopen() = KnowledgePayloadTestFixture().use { f ->
        val item = KnowledgePayloadCompactionFixture.large(f)
        val old = KnowledgePayloadCompactionFixture.row(f, item.id)
        val path = KnowledgePayloadCompactionFixture.path(f, old)
        val revision = revision(f)
        f.db.reclaimPayloads(); f.db.reclaimPayloads()
        val job = requireNotNull(f.db.payloads.catalog.copyJob())
        val state = KnowledgePayloadCopy(f.db.payloads).decode(job)
        assertTrue(state.copiedBytes > 0); assertFalse(state.complete)
        assertEquals(old.value, KnowledgePayloadCompactionFixture.row(f, item.id).value)
        f.reopen()
        assertEquals(state, KnowledgePayloadCopy(f.db.payloads).decode(requireNotNull(f.db.payloads.catalog.copyJob())))
        assertTrue(KnowledgePayloadCompactionFixture.finish(f) > 0)
        assertNull(f.db.payloads.catalog.copyJob()); assertFalse(path.exists())
        assertEquals(item, f.store.findByIds(setOf(item.id)).single())
        assertEquals(revision, revision(f)); KnowledgePayloadUsageDeviceTest.exact(f)
    }

    @Test fun newerUserWriteWinsOverAnIncompleteCopy() = KnowledgePayloadTestFixture().use { f ->
        val item = KnowledgePayloadCompactionFixture.large(f)
        f.db.reclaimPayloads(); f.db.reclaimPayloads()
        assertNotNull(f.db.payloads.catalog.copyJob())
        val replacement = f.item(99, "\u7528\u6237\u65b0\u5185\u5bb9".repeat(3000))
        f.putLegacy(replacement)
        f.reopen(); KnowledgePayloadCompactionFixture.finish(f)
        assertNull(f.db.payloads.catalog.copyJob())
        assertEquals(replacement, f.store.findByIds(setOf(item.id)).single()); KnowledgePayloadUsageDeviceTest.exact(f)
    }

    @Test fun tamperedCopyCheckpointFailsWithoutPublishingOrDeletingSource() = KnowledgePayloadTestFixture().use { f ->
        val item = KnowledgePayloadCompactionFixture.large(f)
        f.db.reclaimPayloads()
        val old = KnowledgePayloadCompactionFixture.row(f, item.id)
        val job = requireNotNull(f.db.payloads.catalog.copyJob())
        val changed = (if (job.checkpoint[0] == 'A') "B" else "A") + job.checkpoint.drop(1)
        f.db.payloads.catalog.checkpointCopy(job, job.copy(checkpoint = changed))
        assertThrows(Exception::class.java) { f.db.reclaimPayloads() }
        assertTrue(KnowledgePayloadCompactionFixture.path(f, old).isFile)
        assertEquals(old.value, KnowledgePayloadCompactionFixture.row(f, item.id).value)
        f.db.payloads.catalog.checkpointCopy(job.copy(checkpoint = changed), job)
        KnowledgePayloadCompactionFixture.finish(f)
        assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }

    private fun revision(f: KnowledgePayloadTestFixture) = f.db.access { sql ->
        sql.rawQuery("SELECT sequence FROM knowledge_source_revision_state WHERE id=1", null)
            .use { assertTrue(it.moveToFirst()); it.getLong(0) }
    }
}
