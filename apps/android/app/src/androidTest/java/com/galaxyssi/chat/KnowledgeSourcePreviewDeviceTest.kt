package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePreviewDeviceTest {
    @Test fun newSourcesHaveAuthenticatedDiskPreviewsWithoutBodyReadsOrRetainedKeys() = KnowledgeBackupTestFixture().use { f ->
        f.seed(65); assertFalse(f.db.hasActivePreviewKey)
        assertEquals(65, KnowledgeSourcePreviewFixtureSchema.count(f))
        val before = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        val first = f.store.sourcePage()
        assertEquals(50, first.groups.size); assertEquals(50L, f.db.sourcePreviewHits); assertEquals(0L, f.db.sourcePreviewMisses)
        assertFalse(f.db.hasActivePreviewKey); assertEquals(0L, f.db.decryptedItemReads)
        f.reopen(); val rest = f.store.sourcePage(requireNotNull(first.next))
        assertEquals(15, rest.groups.size); assertEquals(15L, f.db.sourcePreviewHits); assertEquals(0L, f.db.sourcePreviewMisses)
        assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
    }
    @Test fun legacyUpgradeOnlyMaterializesRequestedRowsAndKeepsBrowseRevision() = KnowledgeBackupTestFixture().use { f ->
        f.seed(65); val before = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        KnowledgeSourcePreviewFixtureSchema.versionEight(f)
        assertEquals(0, KnowledgeSourcePreviewFixtureSchema.count(f))
        val revision = f.store.sourceRevision()
        val first = f.store.sourcePage(limit = 3)
        assertEquals(3, KnowledgeSourcePreviewFixtureSchema.count(f)); assertEquals(3L, f.db.sourcePreviewMisses)
        first.groups.forEachIndexed { i, group -> KnowledgeSourceMigrationTestSupport.assertGroup(group, 65 - i) }
        assertEquals(revision, f.store.sourceRevision()); assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
        assertEquals(3, f.store.sourcePage(requireNotNull(first.next), 3).groups.size)
        assertEquals(6, KnowledgeSourcePreviewFixtureSchema.count(f))
    }
    @Test fun tamperedEnvelopeFailsClosedWithoutDowngradingToAnUnauthenticatedPreview() = KnowledgeBackupTestFixture().use { f ->
        f.seed(1)
        f.db.access { db ->
            val bytes = db.rawQuery("SELECT ciphertext FROM knowledge_source_previews", null).use { check(it.moveToFirst()); it.getBlob(0) }
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
            db.update("knowledge_source_previews", ContentValues().apply { put("ciphertext", bytes) }, "1=1", emptyArray())
        }
        assertThrows(Exception::class.java) { f.store.sourcePage() }
        assertEquals(0L, f.db.sourcePreviewMisses); assertFalse(f.db.hasActivePreviewKey)
    }
    @Test fun swappedSourceEnvelopesCannotCrossItemsOrDatabaseNamespaces() = KnowledgeBackupTestFixture().use { a ->
        KnowledgeBackupTestFixture().use { b ->
            a.seed(2); b.seed(2)
            val foreign = a.db.access { db -> db.rawQuery("SELECT ciphertext FROM knowledge_source_previews LIMIT 1", null).use {
                check(it.moveToFirst()); it.getBlob(0)
            } }
            b.db.access { db -> db.update("knowledge_source_previews", ContentValues().apply { put("ciphertext", foreign) }, "1=1", emptyArray()) }
            assertThrows(Exception::class.java) { b.store.sourcePage() }
            a.db.access { db -> db.update("knowledge_source_previews", ContentValues().apply { put("ciphertext", foreign) }, "1=1", emptyArray()) }
            assertThrows(Exception::class.java) { a.store.sourcePage() }
            assertFalse(a.db.hasActivePreviewKey); assertFalse(b.db.hasActivePreviewKey)
        }
    }
    @Test fun fingerprintCorruptionIsNotSilentlyRebuilt() = KnowledgeBackupTestFixture().use { f ->
        f.seed(1)
        f.db.access { it.execSQL("UPDATE knowledge_source_previews SET fingerprint=zeroblob(32)") }
        assertThrows(IllegalStateException::class.java) { f.store.sourcePage() }
        assertEquals(0L, f.db.sourcePreviewMisses)
    }
    @Test fun sourceHeaderAndIndexMutationsInvalidatePreviewsBeforeAuthentication() = KnowledgeBackupTestFixture().use { f ->
        for (assignment in listOf("header='corrupt'", "title_key='wrong'", "source_key='wrong'", "updated=999")) {
            f.db.transaction { db -> f.db.write(db, f.item(1)); db.execSQL("UPDATE knowledge_items SET $assignment") }
            assertEquals(0, KnowledgeSourcePreviewFixtureSchema.count(f))
            assertThrows(Exception::class.java) { f.store.sourcePage() }
        }
    }
    @Test fun accessChangesAndDeletedHeadsNeverReturnStalePolicies() = KnowledgeBackupTestFixture().use { f ->
        f.store.upsert(f.item(1).copy(source = "same")); f.store.upsert(f.item(2).copy(source = "same"))
        val group = f.store.sourcePage().groups.single(); assertEquals(f.item(2).title, group.title)
        f.store.updateAccess(setOf(f.item(2).id), AgentKnowledgeCloudAccess.SUMMARY_ONLY,
            AgentKnowledgeAgentAccess.SELECTED_AGENTS, listOf("fixture-agent"))
        assertEquals(listOf("fixture-agent"), f.store.sourcePage().groups.single().allowedAgentIds)
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", f.item(2).id))) }
        val remaining = f.store.sourcePage().groups.single()
        assertEquals(f.item(1).title, remaining.title); assertEquals(AgentKnowledgeCloudAccess.DENY, remaining.cloudAccess)
        assertEquals(1, KnowledgeSourcePreviewFixtureSchema.count(f))
    }
    @Test fun rollbackAndIgnoredPreviewWritesCannotCommitPartialSources() = KnowledgeBackupTestFixture().use { f ->
        f.seed(1); val before = KnowledgeSourceMigrationTestSupport.fingerprint(f.name)
        assertThrows(IllegalStateException::class.java) { f.db.transaction { db -> f.db.write(db, f.item(2)); error("rollback") } }
        assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name)); assertEquals(1, KnowledgeSourcePreviewFixtureSchema.count(f))
        f.db.access { it.execSQL("CREATE TRIGGER reject_preview BEFORE INSERT ON knowledge_source_previews BEGIN SELECT RAISE(IGNORE); END") }
        assertThrows(IllegalStateException::class.java) { f.db.transaction { f.db.write(it, f.item(2)) } }
        assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name)); assertEquals(1, f.store.sourceCount())
        assertFalse(f.db.hasActivePreviewKey)
    }
    @Test fun nestedOperationsKeepOneScopeAndFailureClosesOwnedKey() = KnowledgeBackupTestFixture().use { f ->
        f.seed(2)
        assertThrows(IllegalStateException::class.java) { f.db.access {
            f.store.sourcePage(); assertTrue(f.db.hasActivePreviewKey)
            f.store.sourcePage(); assertTrue(f.db.hasActivePreviewKey)
            error("fixture failure")
        } }
        assertFalse(f.db.hasActivePreviewKey)
        assertEquals(2, f.store.sourcePage().groups.size); assertFalse(f.db.hasActivePreviewKey)
    }
    @Test fun derivedPreviewBytesDoNotContainPlaintextSourceTitles() = KnowledgeBackupTestFixture().use { f ->
        f.seed(3)
        f.db.access { db -> db.rawQuery("SELECT ciphertext FROM knowledge_source_previews", null).use { c ->
            while (c.moveToNext()) {
                val raw = String(c.getBlob(0), Charsets.ISO_8859_1)
                assertFalse(raw.contains("fixture-")); assertFalse(raw.contains("backup-"))
            }
        } }
    }
}
