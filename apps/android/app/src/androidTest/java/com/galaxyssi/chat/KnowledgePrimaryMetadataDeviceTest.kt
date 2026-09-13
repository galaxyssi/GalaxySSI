package com.galaxyssi.chat

import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import androidx.test.ext.junit.runners.AndroidJUnit4

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryMetadataDeviceTest {
    private fun pointer(f: KnowledgeSourceReplaceFixture, key: String) = f.db.access { db ->
        db.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use { check(it.moveToFirst()); it.getString(0) }
    }
    private fun physical(f: KnowledgeSourceReplaceFixture, key: String, action: (KnowledgeSqlite, String) -> Unit) {
        val ref = f.db.access { requireNotNull(f.db.primary.reference(it, key)) }
        KnowledgeSqlite(File(f.context.getDatabasePath(f.name).absolutePath + ".primary", "${ref.partition}.sqlite").absolutePath)
            .use { action(it, ref.entry) }
    }
    private fun metadata(f: KnowledgePrimaryCompactionFixture, i: Int): String {
        val ref = requireNotNull(f.parts.reference(f.db, f.key(i)))
        return f.parts.resolveHeader(f.db, f.key(i), "khp1:${ref.headerHash}")
    }

    @Test fun publicWriteUsesCompactPointerAndEncryptedPhysicalHeader() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1); f.store.upsert(item)
        val key = f.db.key("id", item.id); val token = pointer(f, key)
        assertEquals(69, token.length); assertNotNull(KnowledgePrimaryMetadata.pointerHash(token))
        f.db.access { db ->
            val sealed = f.db.primary.resolveHeader(db, key, token)
            assertTrue(AgentRowStorageCipher.isEncrypted(sealed)); assertEquals(token, KnowledgePrimaryMetadata.pointer(sealed))
            assertFalse(requireNotNull(f.db.readHeader(db, key)).has("source_preview"))
        }
        f.reopen(); assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }

    @Test fun missingHeaderNeverFallsBackToReadableBody() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(1)); val key = f.db.key("id", f.item(1).id)
        physical(f, key) { db, entry -> db.delete("headers", "entry_key=?", arrayOf(entry)) }
        assertThrows(Exception::class.java) { f.store.findByIds(setOf(f.item(1).id)) }
        assertEquals(1L, f.store.stats().itemCount)
    }

    @Test fun corruptHeaderIsRejectedBeforeRecordUse() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(1)); val key = f.db.key("id", f.item(1).id)
        physical(f, key) { db, entry -> db.rawQuery("UPDATE headers SET ciphertext='damaged' WHERE entry_key=?", arrayOf(entry)).use { it.moveToNext() } }
        assertThrows(Exception::class.java) { f.store.findByIds(setOf(f.item(1).id)) }
        assertEquals(1L, f.store.stats().itemCount)
    }

    @Test fun copiedPointerCannotIdentifyAnotherRecord() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(1)); f.store.upsert(f.item(2))
        val first = f.db.key("id", f.item(1).id); val second = f.db.key("id", f.item(2).id)
        f.db.transaction { db -> db.rawQuery("UPDATE knowledge_items SET header=(SELECT header FROM knowledge_items WHERE item_key=?) WHERE item_key=?",
            arrayOf(first, second)).use { it.moveToNext() } }
        assertThrows(Exception::class.java) { f.store.findByIds(setOf(f.item(2).id)) }
        assertEquals(f.item(1), f.store.findByIds(setOf(f.item(1).id)).single())
    }

    @Test fun missingPreviewRebuildsFromAuthenticatedPartitionedRecord() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1).copy(cloudAccess = AgentKnowledgeCloudAccess.DENY, agentAccess = AgentKnowledgeAgentAccess.LOCAL_ONLY)
        f.store.upsert(item); val key = f.db.key("id", item.id)
        f.db.transaction { it.delete("knowledge_source_previews", "item_key=?", arrayOf(key)) }
        f.db.access { assertEquals(KnowledgeSourceMetadata.from(item), f.db.readSourceMetadata(it, key)) }
        f.reopen(); assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }

    @Test fun failedMetadataPublicationPreservesPreviousPointer() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1); f.store.upsert(item); val key = f.db.key("id", item.id); val original = pointer(f, key)
        assertThrows(IllegalStateException::class.java) { f.db.transaction { db ->
            f.db.write(db, item.copy(content = "replacement")); f.db.primary.prepareCommit(); error("before catalog commit")
        } }
        f.reopen(); assertEquals(original, pointer(f, key)); assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }

    @Test fun smallCompactionPreservesMetadataAndReclaimsOldFile() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1, "old", "old-header"); f.put(1, "current", "current-header") }
        val source = f.source(1); assertEquals(1, f.drain())
        assertEquals("current", f.parts.read(f.db, f.key(1))); assertEquals("current-header", metadata(f, 1))
        assertFalse(File(f.root, "$source.sqlite").exists())
    }

    @Test fun checkpointedCopyRetainsHeaderAcrossReopen() {
        val body = "\u5143\u6570\u636e".repeat(KnowledgePrimaryFrameCodec.CHARS * 7)
        val name = KnowledgePrimaryCompactionFixture().use { f ->
            f.transaction { f.put(1, "old", "old-header"); f.put(1, body, "bound-header") }
            f.transaction { KnowledgePrimaryCompaction.advance(f.db, f.parts) { } }
            f.transaction { f.parts.resumeCopy(f.db) { } }
            assertTrue(KnowledgePrimaryCopy.pending(f.db)); assertEquals("bound-header", metadata(f, 1)); f.name
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            assertEquals(1, f.drain()); assertEquals(body, f.parts.read(f.db, f.key(1)))
            assertEquals("bound-header", metadata(f, 1))
        }
    }

    @Test fun damagedMetadataPreventsCompactionPublication() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1, "old"); f.put(1, "new", "header") }
        val source = f.source(1)
        KnowledgeSqlite(File(f.root, "$source.sqlite").absolutePath).use { it.execSQL("UPDATE headers SET ciphertext='wrong'") }
        assertThrows(Exception::class.java) { f.drain() }
        assertEquals(source, f.source(1)); assertTrue(File(f.root, "$source.sqlite").isFile)
        assertEquals(0L, f.number("SELECT count(*) FROM knowledge_primary_retired"))
    }

    @Test fun versionOneBodyFileUpgradesOnlyWhenWritten() {
        val name = KnowledgePrimaryCompactionFixture().use { f ->
            f.transaction { f.put(1) }
            KnowledgeSqlite(File(f.root, "${f.source(1)}.sqlite").absolutePath).use {
                it.execSQL("DROP TABLE headers"); it.execSQL("PRAGMA user_version=1")
            }
            f.name
        }
        KnowledgePrimaryCompactionFixture(name).use { f ->
            assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
            f.transaction { f.put(2, "new", "new-header") }
            assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1))); assertEquals("new-header", metadata(f, 2))
            KnowledgeSqlite(File(f.root, "${f.source(2)}.sqlite").absolutePath).use { db ->
                db.rawQuery("PRAGMA user_version", null).use { assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0)) }
            }
        }
    }

    @Test fun oversizeMetadataRollsBackAndLeavesExistingRecord() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1, "old", "old-header") }
        assertThrows(IllegalArgumentException::class.java) { f.transaction { f.put(1, "new", "x".repeat(4097)) } }
        assertEquals("old", f.parts.read(f.db, f.key(1))); assertEquals("old-header", metadata(f, 1))
    }

    @Test fun malformedPointerDoesNotResolveAsLegacyCiphertext() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1, "body", "header") }
        assertThrows(IllegalArgumentException::class.java) { f.parts.resolveHeader(f.db, f.key(1), "khp1:wrong") }
        assertEquals("header", metadata(f, 1))
    }

    @Test fun physicalRelocationKeepsCatalogRevisionAndSnapshotValid() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1); f.store.upsert(item.copy(content = "old")); f.store.upsert(item)
        val key = f.db.key("id", item.id); val token = pointer(f, key); val revision = f.store.sourceRevision()
        var complete = false
        repeat(20) { if (!complete) complete = requireNotNull(f.db.reclaimPrimary()).complete }
        assertTrue(complete); assertEquals(token, pointer(f, key)); assertEquals(revision, f.store.sourceRevision())
        f.db.searchSnapshot().use { snapshot -> assertEquals(item, snapshot.recent(1).single()) }
        assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }

    @Test fun legacyInlineHeaderDoesNotChangeOnReopen() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1); f.store.upsert(item); val key = f.db.key("id", item.id)
        KnowledgePrimaryLegacyFixture.rewrite(f.db, f.context, f.name, key, inline = true)
        val before = pointer(f, key); assertNull(KnowledgePrimaryMetadata.pointerHash(before))
        f.reopen(); assertEquals(before, pointer(f, key)); assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }

    @Test fun longUserMetadataDoesNotExpandTheCatalogHeaderToken() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1).copy(title = "\u6807\u9898".repeat(3000), source = "\u6765\u6e90".repeat(3000))
        f.store.upsert(item); val key = f.db.key("id", item.id)
        assertEquals(69, pointer(f, key).length)
        f.reopen(); assertEquals(item, f.store.findByIds(setOf(item.id)).single())
    }
}
