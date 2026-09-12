package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePayloadUsageDeviceTest {
    @Test fun insertReplaceDeleteAndRollbackKeepExactUsage() = KnowledgePayloadTestFixture().use { f ->
        repeat(9) { f.putLegacy(f.item(it)) }
        exact(f)
        f.db.payloads.seal()
        f.putLegacy(f.item(1, "\u66ff\u6362\u6d4b\u8bd5".repeat(3000)))
        exact(f)
        assertThrows(IllegalStateException::class.java) {
            f.db.transaction { it.delete("knowledge_items", null, null); error("rollback fixture") }
        }
        exact(f); assertEquals(9L, f.store.stats().itemCount)
        f.db.transaction { it.delete("knowledge_items", null, null) }
        exact(f)
        f.db.access { sql -> sql.rawQuery("SELECT 1 FROM knowledge_payload_usage LIMIT 1", null).use { assertFalse(it.moveToFirst()) } }
    }

    @Test fun schemaElevenBackfillIsPagedAndSurvivesConcurrentWritesAndReopen() = KnowledgePayloadTestFixture().use { f ->
        repeat(9) { f.putLegacy(f.item(it)) }
        versionEleven(f)
        assertFalse(f.db.access(KnowledgePayloadUsage::ready))
        assertFalse(f.db.access { KnowledgePayloadUsage.advance(it, 2) })
        val deleted = f.db.access { sql -> sql.rawQuery("SELECT item_key FROM knowledge_payloads WHERE live_counted=0 LIMIT 1", null)
            .use { assertTrue(it.moveToFirst()); it.getString(0) } }
        f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(deleted)) }
        f.putLegacy(f.item(20)); f.putLegacy(f.item(21))
        f.reopen()
        var pages = 0
        while (!f.db.access { KnowledgePayloadUsage.advance(it, 2) }) { assertTrue(++pages < 10) }
        exact(f); assertEquals(10L, f.store.stats().itemCount)
        val before = f.db.access { KnowledgePayloadUsage.bytes(it, "absent") }
        assertEquals(0L, before)
    }

    @Test fun failedAccountingAbortsDeletionAndTrackingCannotGoBackwards() = KnowledgePayloadTestFixture().use { f ->
        f.putLegacy(f.item(1)); exact(f)
        assertThrows(Exception::class.java) {
            f.db.transaction { sql ->
                sql.delete("knowledge_payload_usage", null, null)
                sql.delete("knowledge_items", null, null)
            }
        }
        exact(f); assertEquals(1L, f.store.stats().itemCount)
        assertThrows(Exception::class.java) { f.db.transaction { it.execSQL("UPDATE knowledge_payloads SET live_counted=0") } }
        exact(f)
    }

    @Test fun cancelledAccountingPageRollsBackItsCursorAndDeltas() = KnowledgePayloadTestFixture().use { f ->
        repeat(7) { f.putLegacy(f.item(it)) }; versionEleven(f)
        assertThrows(IllegalStateException::class.java) {
            f.db.transaction { KnowledgePayloadUsage.advance(it, 3); error("cancel page") }
        }
        f.reopen()
        f.db.access { sql ->
            sql.rawQuery("SELECT after_item FROM knowledge_payload_usage_scan", null).use { assertTrue(it.moveToFirst()); assertEquals("", it.getString(0)) }
            sql.rawQuery("SELECT 1 FROM knowledge_payload_usage LIMIT 1", null).use { assertFalse(it.moveToFirst()) }
        }
        assertFalse(requireNotNull(f.db.reclaimPayloads()).complete)
        while (!f.db.advancePayloadUsage()) { }
        exact(f)
    }

    @Test fun usageLookupUsesItsPrimaryKeyAndReadOnlyLookupDoesNotDecodeBodies() = KnowledgePayloadTestFixture().use { f ->
        f.putLegacy(f.item(1))
        val reads = f.db.decryptedItemReads
        f.db.access { sql ->
            val plans = sql.rawQuery("EXPLAIN QUERY PLAN SELECT bytes FROM knowledge_payload_usage WHERE segment=?", arrayOf("absent"))
                .use { c -> buildList { while (c.moveToNext()) add(c.getString(3)) } }
            assertTrue(plans.toString(), plans.any { it.contains("SEARCH knowledge_payload_usage") })
            assertEquals(0L, KnowledgePayloadUsage.bytes(sql, "absent"))
        }
        assertEquals(reads, f.db.decryptedItemReads)
    }

    companion object {
        internal fun exact(f: KnowledgePayloadTestFixture) = f.db.access { sql ->
            val actual = sql.rawQuery("SELECT segment,bytes,items FROM knowledge_payload_usage ORDER BY segment", null)
                .use { c -> buildList { while (c.moveToNext()) add(Triple(c.getString(0), c.getLong(1), c.getLong(2))) } }
            val expected = sql.rawQuery("SELECT segment,sum(bytes),count(*) FROM knowledge_payloads GROUP BY segment ORDER BY segment", null)
                .use { c -> buildList { while (c.moveToNext()) add(Triple(c.getString(0), c.getLong(1), c.getLong(2))) } }
            assertEquals(expected, actual)
        }

        private fun versionEleven(f: KnowledgePayloadTestFixture) {
            f.store.close()
            KnowledgeSqlite(f.context.getDatabasePath(f.name).absolutePath).use { sql ->
                sql.beginTransaction()
                try {
                    listOf("insert_guard", "update_guard", "insert", "update", "delete").forEach {
                        sql.execSQL("DROP TRIGGER knowledge_payload_usage_$it")
                    }
                    sql.execSQL("DROP TABLE knowledge_payload_usage")
                    sql.execSQL("DROP TABLE knowledge_payload_usage_scan")
                    sql.execSQL("ALTER TABLE knowledge_payloads DROP COLUMN live_counted")
                    KnowledgePrimaryLegacyFixture.removePrimarySchemaBeforeDowngrade(sql)
                    sql.execSQL("PRAGMA user_version=11")
                    sql.setTransactionSuccessful()
                } finally { sql.endTransaction() }
            }
            f.reopen()
        }
    }
}
