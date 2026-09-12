package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class KnowledgeBackupDeviceTest {
    @Test fun emptyArchiveRemovesOldSourcesAndPublishesOnlyAfterCommit() = KnowledgeBackupTestFixture().use { f ->
        assertEquals(2L, f.export())
        f.store.upsert(f.item(1)); f.mutations.clear()
        f.restore(); assertEquals(0L, f.store.stats().itemCount)
        assertEquals(listOf(listOf(f.item(1)) to emptyList<AgentKnowledgeItem>()), f.mutations)
        f.reopen(); assertEquals(0L, f.store.stats().itemCount)
    }
    @Test fun moreThanOnePageRoundTripsBodiesPoliciesAndStableIds() = KnowledgeBackupTestFixture().use { f ->
        f.seed(137)
        val special = f.item(500, "\u4e2d\u6587\ud83d\ude80".repeat(18000)).copy(id = "long-id-".repeat(700),
            cloudAccess = AgentKnowledgeCloudAccess.FULL, agentAccess = AgentKnowledgeAgentAccess.SELECTED_AGENTS,
            allowedAgentIds = listOf("agent-a", "agent-b"), tags = listOf("fixture", "\u4e2d\u6587"), chunkIndex = 3, chunkCount = 8)
        f.store.upsert(special)
        assertEquals(140L, f.export())
        f.db.transaction { it.delete("knowledge_items", null, null) }; f.store.upsert(f.item(900))
        f.mutations.clear(); f.restore(); f.reopen()
        assertEquals(138L, f.store.stats().itemCount)
        (1..137).forEach { assertEquals(f.item(it), f.store.findByIds(setOf(f.item(it).id)).single()) }
        assertEquals(special, f.store.findByIds(setOf(special.id)).single())
        assertTrue(f.mutations.all { it.first.size <= 1 && it.second.size <= 1 })
        assertFalse(f.store.search("\u5907\u4efd", 8).isEmpty())
    }
    @Test fun snapshotSurvivesConcurrentReplacementInsertAndDeleteWithoutBlockingWriter() = KnowledgeBackupTestFixture().use { f ->
        f.seed(137)
        f.db.backupSnapshot().use { snapshot ->
            val iterator = snapshot.items().iterator()
            val original = mutableMapOf<String, AgentKnowledgeItem>()
            val first = iterator.next(); original[first.id] = first
            val executor = Executors.newSingleThreadExecutor()
            try { executor.submit {
                f.store.upsert(f.item(1, "\u66f4\u65b0")); f.store.upsert(f.item(500))
                f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", f.item(2).id))) }
            }.get(5, TimeUnit.SECONDS) } finally { executor.shutdownNow() }
            while (iterator.hasNext()) { val item = iterator.next(); assertNull(original.put(item.id, item)) }
            assertEquals((1..137).associate { f.item(it).id to f.item(it) }, original)
        }
        assertEquals("\u66f4\u65b0", f.store.findByIds(setOf(f.item(1).id)).single().content)
        assertTrue(f.store.findByIds(setOf(f.item(2).id)).isEmpty())
    }
    @Test fun closedOwnerInvalidatesPendingSnapshot() = KnowledgeBackupTestFixture().use { f ->
        f.seed(3)
        f.db.backupSnapshot().use { snapshot ->
            val rows = snapshot.items().iterator(); rows.next(); f.store.close()
            assertThrows(IllegalStateException::class.java) { while (rows.hasNext()) rows.next() }
        }
        f.reopen(); assertEquals(3L, f.store.stats().itemCount)
    }
    @Test fun archiveReencryptsSourcesForAnotherDatabaseNamespace() = KnowledgeBackupTestFixture().use { from ->
        KnowledgeBackupTestFixture().use { to ->
            from.seed(3); from.export(); from.file.copyTo(to.file)
            to.restore()
            (1..3).forEach {
                assertEquals(from.item(it), to.store.findByIds(setOf(from.item(it).id)).single())
                assertNotEquals(from.db.key("id", from.item(it).id), to.db.key("id", from.item(it).id))
            }
        }
    }
    @Test fun cancelledRestoreRollsBackAlreadyWrittenRowsAndPublishesNothing() = KnowledgeBackupTestFixture().use { f ->
        f.seed(3)
        f.staged((10..20).asSequence().map { f.item(it) }) { stage ->
            assertThrows(IllegalStateException::class.java) { f.store.restoreRecords(stage) { if (it == 2L) error("Fixture cancellation") } }
        }
        f.reopen(); assertEquals((1..3).map { f.item(it) }.toSet(), f.store.list(10).toSet())
        assertTrue(f.mutations.isEmpty())
    }
    @Test fun sourceWriteFailureRollsBackEntireRestoreAndPublishesNothing() = KnowledgeBackupTestFixture().use { f ->
        f.seed(3)
        f.db.access { it.execSQL("CREATE TRIGGER reject_backup BEFORE INSERT ON knowledge_items BEGIN SELECT RAISE(ABORT,'fixture write'); END") }
        try {
            f.staged(sequenceOf(f.item(20), f.item(21))) { stage -> assertThrows(Exception::class.java) { f.store.restoreRecords(stage) } }
            assertEquals(3L, f.store.stats().itemCount); assertTrue(f.mutations.isEmpty())
        } finally { f.db.access { it.execSQL("DROP TRIGGER reject_backup") } }
        f.reopen(); (1..3).forEach { assertEquals(f.item(it), f.store.findByIds(setOf(f.item(it).id)).single()) }
    }
    @Test fun replacementPublishesMatchedOldAndNewRowsWithoutReplayingUnchangedItems() = KnowledgeBackupTestFixture().use { f ->
        f.seed(3)
        val changed = f.item(1, "\u4fee\u6539")
        f.staged(sequenceOf(changed, f.item(2), f.item(4))) { f.store.restoreRecords(it) }
        assertEquals(setOf(listOf(f.item(1)) to listOf(changed), listOf(f.item(3)) to emptyList(),
            emptyList<AgentKnowledgeItem>() to listOf(f.item(4))), f.mutations.toSet())
    }
    @Test fun unchangedRestoreKeepsDerivedVectorsAndBrowseRevision() = KnowledgeCountTestFixture().use { f ->
        f.seed(3); f.index()
        val revision = f.store.sourceRevision()
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.accept("knowledge", "begin", "{\"schema\":1}".byteInputStream())
            f.store.list(3).forEach { item -> stage.accept("knowledge-row", KnowledgeBackupRecords.key(item.id),
                AgentKnowledgeCodec.encodeItem(item).toString().byteInputStream()) }
            stage.accept("knowledge", "end", "{\"rows\":3}".byteInputStream()); stage.validateArchive()
            f.store.restoreRecords(stage) { fail("Unchanged source was rewritten") }
        }
        f.verify(); assertEquals(3L, f.counts().chunks); assertEquals(0L, f.counts().pending)
        assertEquals(revision, f.store.sourceRevision())
    }
    @Test fun duplicateRecordsWrongIdsPoliciesAndCountsAreRejected() = KnowledgeBackupTestFixture().use { f ->
        val valid = AgentKnowledgeCodec.encodeItem(f.item(1))
        for (mode in listOf("duplicate", "id", "policy", "count", "missing-end", "repeated-begin", "after-end")) {
            assertThrows(Exception::class.java) { KnowledgeBackupStaging(f.context).use { stage ->
                stage.accept("knowledge", "begin", "{\"schema\":1}".byteInputStream())
                val json = JSONObject(valid.toString()).apply { if (mode == "policy") put("cloud_access", "unrecognized") }
                val key = if (mode == "id") "wrong" else KnowledgeBackupRecords.key(f.item(1).id)
                stage.accept("knowledge-row", key, json.toString().byteInputStream())
                if (mode == "duplicate") stage.accept("knowledge-row", key, json.toString().byteInputStream())
                if (mode == "repeated-begin") stage.accept("knowledge", "begin", "{\"schema\":1}".byteInputStream())
                if (mode != "missing-end") stage.accept("knowledge", "end", "{\"rows\":${if (mode == "count") 2 else 1}}".byteInputStream())
                if (mode == "after-end") stage.accept("knowledge-row", key, json.toString().byteInputStream())
                stage.validateArchive()
            } }
        }
    }
    @Test fun truncatedOrTamperedArchiveDoesNotApplyStagedRecords() = KnowledgeBackupTestFixture().use { f ->
        f.seed(137); f.export()
        val bytes = f.file.readBytes()
        f.db.transaction { it.delete("knowledge_items", null, null) }; f.store.upsert(f.item(999)); f.mutations.clear()
        for (broken in listOf(bytes.copyOf(bytes.size - 1), bytes.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() })) {
            f.file.writeBytes(broken)
            assertThrows(Exception::class.java) { f.restore() }
            assertEquals(listOf(f.item(999)), f.store.list(10)); assertTrue(f.mutations.isEmpty())
        }
    }
    @Test fun largeStagingRecordIsEncryptedAndAvoidsCursorWindowOverflow() = KnowledgeBackupTestFixture().use { f ->
        val item = f.item(1, "private-knowledge-marker".repeat(100000))
        f.staged(sequenceOf(item)) { stage ->
            val files = File(f.context.cacheDir, "knowledge-backup-staging").listFiles().orEmpty().filter { it.extension == "db" }
            assertTrue(files.isNotEmpty())
            files.forEach { file ->
                val head = ByteArray(8192)
                file.inputStream().use { it.read(head) }
                assertFalse(String(head, Charsets.ISO_8859_1).contains("private-knowledge-marker"))
            }
            assertEquals(item, stage.incoming().single())
        }
    }
    @Test fun legacyArrayIsConsumedIncrementallyAndRejectsDuplicateEnvelopeKeys() = KnowledgeBackupTestFixture().use { f ->
        val json = AgentKnowledgeCodec.encodeItem(f.item(1)).toString()
        KnowledgeBackupStaging(f.context).use { stage ->
            stage.acceptLegacy("{\"value\":[$json]}".byteInputStream())
            stage.validateArchive(); assertEquals(f.item(1), stage.incoming().single())
        }
        for (bad in listOf("{\"value\":[],\"value\":[]}", "{\"value\":[$json,$json]}", "{\"value\":[]} trailing"))
            assertThrows(Exception::class.java) { KnowledgeBackupStaging(f.context).use { it.acceptLegacy(bad.byteInputStream()) } }
    }
}
