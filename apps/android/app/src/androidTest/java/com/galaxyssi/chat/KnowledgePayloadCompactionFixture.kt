package com.galaxyssi.chat

import android.content.ContentValues
import android.util.Base64
import java.io.File
import java.util.Random
import org.junit.Assert.*

internal object KnowledgePayloadCompactionFixture {
    fun fragmented(f: KnowledgePayloadTestFixture): AgentKnowledgeItem {
        repeat(8) { f.store.upsert(f.item(it)) }
        val keep = f.item(7)
        val key = f.db.key("id", keep.id)
        f.db.transaction { it.delete("knowledge_items", "item_key!=?", arrayOf(key)) }
        return keep
    }

    fun row(f: KnowledgePayloadTestFixture, id: String) = f.db.access { sql ->
        val key = f.db.key("id", id)
        sql.rawQuery("SELECT reference,bytes FROM knowledge_payloads WHERE item_key=?", arrayOf(key)).use {
            assertTrue(it.moveToFirst()); KnowledgePayloadCompaction.Row(key, it.getString(0), it.getLong(1))
        }
    }

    fun path(f: KnowledgePayloadTestFixture, row: KnowledgePayloadCompaction.Row): File {
        val id = f.db.payloads.decodeReference(row.key, row.value).segment.toString()
        return File(File(f.root, id.take(2)), "$id.seg")
    }

    fun large(f: KnowledgePayloadTestFixture): AgentKnowledgeItem {
        val item = f.item(99)
        f.store.upsert(item)
        val noise = ByteArray(1600 * 1024).also { Random(7123).nextBytes(it) }
        val padding = try { Base64.encodeToString(noise, Base64.NO_WRAP) } finally { noise.fill(0) }
        // Authenticated, incompressible fixture padding avoids coupling copy recovery to FTS throughput.
        val encoded = AgentKnowledgeCodec.encodeItem(item).put("storage_fixture_padding", padding).toString()
        repeat(3) {
            f.db.transaction { sql ->
                val key = f.db.key("id", item.id)
                val header = requireNotNull(f.db.readHeader(sql, key)).put("chunks", 0)
                    .put("sha256", AgentNativeJsonCodec.sha256(encoded))
                sql.delete("knowledge_payloads", "item_key=?", arrayOf(key))
                f.db.payloads.append(sql, key, encoded)
                sql.update("knowledge_items", ContentValues().apply {
                    put("header", AgentStorageCipher.encrypt(header.toString(), "${f.name}:$key:header".toByteArray()))
                }, "item_key=?", arrayOf(key))
            }
        }
        assertTrue(row(f, item.id).bytes > KnowledgePayloadCompaction.COPY_BYTES)
        return item
    }

    fun finish(f: KnowledgePayloadTestFixture): Long {
        var reclaimed = 0L
        repeat(64) {
            val result = requireNotNull(f.db.reclaimPayloads())
            reclaimed += result.bytes
            if (result.complete) return reclaimed
        }
        error("Fixture compaction did not complete")
    }
}
