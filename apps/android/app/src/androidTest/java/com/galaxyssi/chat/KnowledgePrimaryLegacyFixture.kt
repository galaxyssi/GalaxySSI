package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context

/** Explicit historical fixtures, not a production switch to bypass primary partitions. */
internal object KnowledgePrimaryLegacyFixture {
    fun rewrite(owner: AgentKnowledgeDatabase, context: Context, name: String, key: String,
        inline: Boolean, hardwareEnvelope: Boolean = false) = owner.transaction { db ->
        val header = requireNotNull(owner.readHeader(db, key))
        val encoded = owner.readEncoded(db, key, header)
        val cipher = AgentRowStorageCipher(context, "knowledge-records:v1:$name")
        fun seal(value: String, part: String): String {
            val aad = "$name:$key:$part".toByteArray(Charsets.UTF_8)
            return if (hardwareEnvelope) AgentStorageCipher.encrypt(value, aad) else cipher.encrypt(value, aad)
        }
        db.delete("knowledge_primary_refs", "item_key=?", arrayOf(key))
        db.delete("knowledge_payloads", "item_key=?", arrayOf(key))
        db.delete("knowledge_chunks", "item_key=?", arrayOf(key))
        var count = 0
        if (inline) {
            var offset = 0
            while (offset < encoded.length) {
                var end = minOf(offset + 16 * 1024, encoded.length)
                if (end < encoded.length && encoded[end - 1].isHighSurrogate() && encoded[end].isLowSurrogate()) end--
                db.insertOrThrow("knowledge_chunks", null, ContentValues().apply {
                    put("item_key", key); put("ordinal", count); put("ciphertext", seal(encoded.substring(offset, end), count.toString()))
                })
                offset = end; count++
            }
        } else owner.payloads.append(db, key, encoded)
        db.update("knowledge_items", ContentValues().apply { put("header", seal(header.put("chunks", count).toString(), "header")) },
            "item_key=?", arrayOf(key))
        db.execSQL("UPDATE knowledge_primary_migration SET after_item='',complete=0 WHERE id=1")
    }

    fun removePrimarySchemaBeforeDowngrade(db: KnowledgeSqlite) {
        if (!db.rawQuery("SELECT 1 FROM sqlite_master WHERE name='knowledge_primary_refs'", null).use { it.moveToFirst() }) return
        inlineForDowngrade(db)
        db.rawQuery("SELECT 1 FROM knowledge_primary_refs LIMIT 1", null).use { check(!it.moveToFirst()) }
        for (trigger in listOf("knowledge_primary_dirty_insert", "knowledge_primary_dirty_delete", "knowledge_primary_dirty_move")) {
            db.execSQL("DROP TRIGGER IF EXISTS $trigger")
        }
        db.execSQL("DROP TABLE IF EXISTS knowledge_primary_dirty")
        db.execSQL("DROP TABLE IF EXISTS knowledge_primary_compaction")
        db.execSQL("DROP TABLE knowledge_primary_refs")
        db.execSQL("DROP TABLE knowledge_primary_migration")
        db.execSQL("DROP TABLE knowledge_primary_retired")
        db.execSQL("DROP TABLE knowledge_primary_partitions")
    }

    fun inlineForDowngrade(db: KnowledgeSqlite) {
        val path = db.rawQuery("PRAGMA database_list", null).use {
            check(it.moveToFirst()); java.io.File(it.getString(2))
        }
        check(path.name.startsWith("test-")) { "Historical fixtures must not touch production data" }
        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        val cipher = AgentRowStorageCipher(context, "knowledge-records:v1:${path.name}")
        KnowledgePrimaryPartitions(context, java.io.File(path.absolutePath + ".primary"), path.name).use { primary ->
            while (true) {
                val keys = db.rawQuery("SELECT item_key FROM knowledge_primary_refs ORDER BY item_key LIMIT 32", null).use {
                    buildList { while (it.moveToNext()) add(it.getString(0)) }
                }
                if (keys.isEmpty()) break
                keys.forEach { key ->
                    val encoded = requireNotNull(primary.read(db, key))
                    val aad = "${path.name}:$key:header".toByteArray()
                    val header = db.rawQuery("SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
                        check(it.moveToFirst()); org.json.JSONObject(requireNotNull(cipher.decrypt(it.getString(0), aad)))
                    }
                    db.delete("knowledge_chunks", "item_key=?", arrayOf(key))
                    var offset = 0
                    var ordinal = 0
                    while (offset < encoded.length) {
                        var end = minOf(offset + 16 * 1024, encoded.length)
                        if (end < encoded.length && encoded[end - 1].isHighSurrogate() && encoded[end].isLowSurrogate()) end--
                        db.insertOrThrow("knowledge_chunks", null, ContentValues().apply {
                            put("item_key", key); put("ordinal", ordinal)
                            put("ciphertext", cipher.encrypt(encoded.substring(offset, end), "${path.name}:$key:$ordinal".toByteArray()))
                        })
                        ordinal++; offset = end
                    }
                    db.update("knowledge_items", ContentValues().apply {
                        put("header", cipher.encrypt(header.put("chunks", ordinal).toString(), aad))
                    }, "item_key=?", arrayOf(key))
                    db.delete("knowledge_primary_refs", "item_key=?", arrayOf(key))
                }
            }
        }
    }
}
