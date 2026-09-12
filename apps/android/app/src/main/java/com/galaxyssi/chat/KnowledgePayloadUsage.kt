package com.galaxyssi.chat

import android.content.ContentValues

/** Derived live-byte counters: constant-size checks without scanning a segment's membership. */
internal object KnowledgePayloadUsage {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_payload_usage(segment TEXT PRIMARY KEY," +
            "bytes INTEGER NOT NULL CHECK(typeof(bytes)='integer' AND bytes>=0)," +
            "items INTEGER NOT NULL CHECK(typeof(items)='integer' AND items>=0))")
        db.execSQL("CREATE TABLE knowledge_payload_usage_scan(id INTEGER PRIMARY KEY CHECK(id=1)," +
            "after_item TEXT NOT NULL DEFAULT '',complete INTEGER NOT NULL CHECK(complete IN (0,1)))")
        db.execSQL("INSERT INTO knowledge_payload_usage_scan(id,complete) VALUES(1," +
            "NOT EXISTS(SELECT 1 FROM knowledge_payloads LIMIT 1))")
        // No CHECK on ADD COLUMN: validating all existing rows would make schema open unbounded.
        db.execSQL("ALTER TABLE knowledge_payloads ADD COLUMN live_counted INTEGER NOT NULL DEFAULT 0")
        db.execSQL("CREATE TRIGGER knowledge_payload_usage_insert_guard BEFORE INSERT ON knowledge_payloads " +
            "WHEN typeof(NEW.live_counted)!='integer' OR NEW.live_counted!=0 BEGIN " +
            "SELECT RAISE(ABORT,'Invalid new payload accounting state'); END")
        db.execSQL("CREATE TRIGGER knowledge_payload_usage_update_guard BEFORE UPDATE ON knowledge_payloads " +
            "WHEN NEW.item_key IS NOT OLD.item_key OR typeof(NEW.live_counted)!='integer' OR " +
            "NEW.live_counted NOT IN (0,1) OR NEW.live_counted<OLD.live_counted BEGIN " +
            "SELECT RAISE(ABORT,'Invalid payload accounting transition'); END")
        db.execSQL("CREATE TRIGGER knowledge_payload_usage_insert AFTER INSERT ON knowledge_payloads BEGIN " +
            "UPDATE knowledge_payloads SET live_counted=1 WHERE item_key=NEW.item_key; " + changed() + " END")
        val subtract = "UPDATE knowledge_payload_usage SET bytes=bytes-OLD.bytes,items=items-1 " +
            "WHERE segment=OLD.segment AND OLD.live_counted=1; " +
            "SELECT CASE WHEN OLD.live_counted=1 AND changes()!=1 THEN RAISE(ABORT,'Payload usage is missing') END; " +
            "DELETE FROM knowledge_payload_usage WHERE segment=OLD.segment AND items=0; "
        db.execSQL("CREATE TRIGGER knowledge_payload_usage_update AFTER UPDATE ON knowledge_payloads " +
            "WHEN NEW.live_counted=1 BEGIN $subtract " +
            "INSERT INTO knowledge_payload_usage(segment,bytes,items) VALUES(NEW.segment,NEW.bytes,1) " +
            "ON CONFLICT(segment) DO UPDATE SET bytes=bytes+excluded.bytes,items=items+1; ${changed()} END")
        db.execSQL("CREATE TRIGGER knowledge_payload_usage_delete AFTER DELETE ON knowledge_payloads " +
            "WHEN OLD.live_counted=1 BEGIN $subtract END")
    }

    fun ready(db: KnowledgeSqlite): Boolean = db.rawQuery(
        "SELECT complete FROM knowledge_payload_usage_scan WHERE id=1", null
    ).use { check(it.moveToFirst()) { "Payload usage checkpoint missing" }; it.getLong(0) == 1L }

    /** New writes are counted immediately, even behind this durable keyset cursor. */
    fun advance(db: KnowledgeSqlite, limit: Int = 64): Boolean {
        require(limit in 1..128)
        if (ready(db)) return true
        val after = db.rawQuery("SELECT after_item FROM knowledge_payload_usage_scan WHERE id=1", null)
            .use { check(it.moveToFirst()); it.getString(0) }
        val keys = db.rawQuery("SELECT item_key FROM knowledge_payloads WHERE item_key>? ORDER BY item_key LIMIT ?",
            arrayOf(after, (limit + 1).toString())).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
        keys.take(limit).forEach { key ->
            db.update("knowledge_payloads", ContentValues().apply { put("live_counted", 1) },
                "item_key=? AND live_counted=0", arrayOf(key))
        }
        val complete = keys.size <= limit
        db.update("knowledge_payload_usage_scan", ContentValues().apply {
            put("after_item", keys.take(limit).lastOrNull() ?: after); put("complete", if (complete) 1 else 0)
        }, "id=1", emptyArray())
        db.rawQuery("SELECT changes()", null).use { check(it.moveToFirst() && it.getLong(0) == 1L) }
        return complete
    }

    fun bytes(db: KnowledgeSqlite, segment: String): Long = db.rawQuery(
        "SELECT bytes FROM knowledge_payload_usage WHERE segment=?", arrayOf(segment)
    ).use { if (it.moveToFirst()) it.getLong(0) else 0L }

    private fun changed() = "SELECT CASE WHEN changes()!=1 THEN RAISE(ABORT,'Payload accounting update was lost') END;"
}
