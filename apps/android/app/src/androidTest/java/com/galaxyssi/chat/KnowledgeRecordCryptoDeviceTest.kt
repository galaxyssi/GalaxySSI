package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeRecordCryptoDeviceTest {
    @Test fun legacyRecordsRemainReadableWithoutEagerRewrite() = KnowledgeSourceReplaceFixture().use { f ->
        val item = f.item(1)
        f.store.upsert(item)
        val owner = f.db
        val key = owner.key("id", item.id)
        KnowledgePrimaryLegacyFixture.rewrite(owner, f.context, f.name, key, inline = true)
        val cipher = AgentRowStorageCipher(f.context, "knowledge-records:v1:${f.name}")
        val oldHeader = owner.transaction { sql ->
            val header = sql.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
                check(it.moveToFirst()); it.getString(0)
            }
            assertTrue(AgentRowStorageCipher.isEncrypted(header))
            val aad = "${f.name}:$key:header".toByteArray()
            val legacy = AgentStorageCipher.encrypt(requireNotNull(cipher.decrypt(header, aad)), aad)
            sql.update("knowledge_items", ContentValues().apply { put("header", legacy) }, "item_key=?", arrayOf(key))
            val chunks = sql.rawQuery("SELECT ordinal,ciphertext FROM knowledge_chunks WHERE item_key=?", arrayOf(key)).use {
                buildList { while (it.moveToNext()) add(it.getInt(0) to it.getString(1)) }
            }
            chunks.forEach { (ordinal, value) ->
                val chunkAad = "${f.name}:$key:$ordinal".toByteArray()
                sql.update("knowledge_chunks", ContentValues().apply {
                    put("ciphertext", AgentStorageCipher.encrypt(requireNotNull(cipher.decrypt(value, chunkAad)), chunkAad))
                }, "item_key=? AND ordinal=?", arrayOf(key, ordinal.toString()))
            }
            KnowledgePrimaryLegacyFixture.removePrimarySchemaBeforeDowngrade(sql)
            sql.execSQL("PRAGMA user_version=12")
            legacy
        }
        f.reopen()
        assertEquals(item, f.store.findByIds(setOf(item.id)).single())
        f.db.access { sql ->
            sql.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
                check(it.moveToFirst()); assertEquals(oldHeader, it.getString(0))
            }
            sql.rawQuery("PRAGMA user_version", null).use { check(it.moveToFirst()); assertEquals(14, it.getInt(0)) }
        }
        f.store.upsert(item.copy(content = "updated"))
        AgentRowStorageCipher.clearCachedKeys()
        f.reopen()
        assertEquals("updated", f.store.findByIds(setOf(item.id)).single().content)
        f.db.access { sql ->
            sql.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
                check(it.moveToFirst()); assertTrue(AgentRowStorageCipher.isEncrypted(it.getString(0)))
            }
        }
    }

    @Test fun swappedCiphertextCannotAuthenticateAsAnotherRecord() = KnowledgeSourceReplaceFixture().use { f ->
        f.store.upsert(f.item(1)); f.store.upsert(f.item(2))
        val first = f.db.key("id", f.item(1).id)
        val second = f.db.key("id", f.item(2).id)
        f.db.transaction { sql ->
            sql.rawQuery("UPDATE knowledge_primary_refs SET reference=(SELECT reference FROM knowledge_primary_refs WHERE item_key=?) WHERE item_key=?", arrayOf(first, second)).use { it.moveToNext() }
        }
        assertThrows(Exception::class.java) { f.store.findByIds(setOf(f.item(2).id)) }
        assertEquals(f.item(1), f.store.findByIds(setOf(f.item(1).id)).single())
        assertEquals(2L, f.store.stats().itemCount)
    }

    @Test fun memoEndsOnSuccessFailureAndNestedAccess() = KnowledgeSourceReplaceFixture().use { f ->
        val owner = f.db
        val expected = owner.key("source", "\u6765\u6e90")
        assertFalse(owner.hasActiveIndexMemo)
        owner.access {
            assertEquals(expected, owner.key("source", "\u6765\u6e90"))
            assertTrue(owner.hasActiveIndexMemo)
            owner.access { assertEquals(expected, owner.key("source", "\u6765\u6e90")) }
            assertTrue(owner.hasActiveIndexMemo)
            val result = java.util.concurrent.CompletableFuture.supplyAsync { owner.key("source", "\u6765\u6e90") }
            assertEquals(expected, result.get(10, java.util.concurrent.TimeUnit.SECONDS))
        }
        assertFalse(owner.hasActiveIndexMemo)
        assertThrows(IllegalStateException::class.java) { owner.access {
            owner.key("source", "\u6765\u6e90"); error("synthetic failure")
        } }
        assertFalse(owner.hasActiveIndexMemo)
        assertEquals(expected, owner.key("source", "\u6765\u6e90"))
    }
}
