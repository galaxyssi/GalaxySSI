package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceRevisionDeviceTest {
    private fun token(f: KnowledgeBackupTestFixture, source: String = "shared", id: String = "") =
        f.store.sourceExport(AgentKnowledgeSourceReference(source, id)).revision

    @Test fun nonHeadSameTimestampChangesVersionButUnrelatedSourcesAndReplayDoNot() = KnowledgeBackupTestFixture().use { f ->
        val original = f.item(1).copy(source = "shared")
        f.store.upsert(original); f.store.upsert(f.item(2).copy(source = "shared"))
        val before = token(f)
        val reads = f.db.decryptedItemReads
        repeat(10) { assertEquals(before, token(f)) }
        assertEquals(reads, f.db.decryptedItemReads); assertEquals(0L, f.db.decryptedSourceSummaryReads)
        f.store.upsert(original); assertEquals(before, token(f))
        f.store.upsert(f.item(3)); assertEquals(before, token(f))
        f.store.upsert(original.copy(content = "\u66f4\u65b0\u5185\u5bb9"))
        val changed = token(f); assertNotEquals(before, changed)
        f.store.sourcePage(); assertEquals(changed, token(f))
        f.reopen(); assertEquals(changed, token(f))
    }

    @Test fun deletesRecreatesMovesAndBlankSourceIdsHaveIndependentVersions() = KnowledgeBackupTestFixture().use { f ->
        val one = f.item(1).copy(source = "")
        val two = f.item(2).copy(source = "")
        f.store.upsert(one); f.store.upsert(two)
        val a = token(f, "", one.id); val b = token(f, "", two.id)
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", one.id))) }
        val absent = token(f, "", one.id)
        assertNotEquals(a, absent); assertEquals(b, token(f, "", two.id))
        f.store.upsert(one); assertNotEquals(a, token(f, "", one.id)); assertNotEquals(absent, token(f, "", one.id))
        val target = token(f)
        f.db.transaction { f.db.write(it, one.copy(source = "shared")) }
        assertEquals(absent, token(f, "", one.id)); assertNotEquals(target, token(f))
        f.db.access { db -> db.rawQuery("SELECT count(*) FROM knowledge_source_revisions", null).use {
            assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0))
        } }
    }

    @Test fun rollbackMissingClockAndIgnoredClockWritesNeverCommitSourceChanges() = KnowledgeBackupTestFixture().use { f ->
        f.store.upsert(f.item(1).copy(source = "shared"))
        val before = token(f); val fingerprint = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        assertThrows(IllegalStateException::class.java) { f.db.transaction {
            f.db.write(it, f.item(2).copy(source = "shared")); error("rollback")
        } }
        assertEquals(before, token(f)); assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
        f.db.access { it.execSQL("CREATE TRIGGER reject_clock BEFORE UPDATE ON knowledge_source_revision_state BEGIN SELECT RAISE(IGNORE); END") }
        assertThrows(Exception::class.java) { f.store.upsert(f.item(3)) }
        assertEquals(before, token(f)); assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
        f.db.access { it.execSQL("DROP TRIGGER reject_clock"); it.execSQL("DELETE FROM knowledge_source_revision_state") }
        assertThrows(Exception::class.java) { f.store.upsert(f.item(4)) }
        assertThrows(IllegalStateException::class.java) { token(f) }
        assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
    }

    @Test fun sequenceOverflowAndIgnoredSourceVersionWritesFailAtomically() = KnowledgeBackupTestFixture().use { f ->
        f.seed(1)
        val fingerprint = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        f.db.access { it.execSQL("CREATE TRIGGER reject_version BEFORE INSERT ON knowledge_source_revisions BEGIN SELECT RAISE(IGNORE); END") }
        assertThrows(Exception::class.java) { f.store.upsert(f.item(2)) }
        assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
        f.db.access { it.execSQL("DROP TRIGGER reject_version"); it.execSQL("UPDATE knowledge_source_revision_state SET sequence=9223372036854775807") }
        assertThrows(Exception::class.java) { f.store.upsert(f.item(3)) }
        assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
    }

    @Test fun versionNineUpgradeDoesNotScanOrRewriteExistingSources() = KnowledgeBackupTestFixture().use { f ->
        f.seed(129)
        f.db.transaction(KnowledgePrimaryLegacyFixture::inlineForDowngrade)
        val fingerprint = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        KnowledgeSourceRevisionFixtureSchema.versionNine(f)
        val before = token(f, "fixture-1")
        assertTrue(before.endsWith(":0")); assertEquals(0L, f.db.decryptedItemReads)
        assertEquals(0L, f.db.decryptedSourceSummaryReads)
        f.db.access { db -> db.rawQuery("SELECT count(*) FROM knowledge_source_revisions", null).use {
            assertTrue(it.moveToFirst()); assertEquals(0L, it.getLong(0))
        } }
        assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
        f.reopen(); assertEquals(before, token(f, "fixture-1"))
        f.store.upsert(f.item(129, "\u66f4\u65b0")); assertEquals(before, token(f, "fixture-1"))
        assertFalse(token(f, "fixture-129").endsWith(":0"))
    }

    @Test fun invalidReferencesAreRejectedAndDatabaseNamespacesDoNotShareTokens() = KnowledgeBackupTestFixture().use { a ->
        KnowledgeBackupTestFixture().use { b ->
            a.seed(1); b.seed(1)
            assertNotEquals(token(a, "fixture-1"), token(b, "fixture-1"))
            assertThrows(IllegalArgumentException::class.java) { token(a, "") }
            assertThrows(IllegalArgumentException::class.java) { token(a, "fixture-1", "backup-1") }
            assertTrue(token(a, "nonexistent").endsWith(":absent"))
        }
    }

    @Test fun directSourceIndexMoveRemovesOldLocalRevisionAndCannotReturnUnauthenticatedMembership() = KnowledgeBackupTestFixture().use { f ->
        f.store.upsert(f.item(1).copy(source = ""))
        val old = token(f, "", "backup-1")
        f.db.access { db -> db.rawQuery("UPDATE knowledge_items SET source_key=?", arrayOf(f.db.key("source", "shared"))).use { it.moveToNext() } }
        assertTrue(token(f, "", "backup-1").endsWith(":absent")); assertNotEquals(old, token(f))
        assertThrows(Exception::class.java) { f.store.sourceExport(AgentKnowledgeSourceReference("shared")).items() }
        Unit
    }
}
