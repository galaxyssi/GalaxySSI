package com.galaxyssi.chat

/** Called under the cross-process exclusive snapshot lease, outside any writer transaction. */
internal object KnowledgePrimaryReclaim {
    data class Page(val partitions: Int, val bytes: Long, val complete: Boolean)

    fun advance(db: KnowledgeSqlite, primary: KnowledgePrimaryPartitions, checkActive: () -> Unit): Page {
        checkActive()
        db.beginTransaction()
        try {
            db.execSQL("INSERT OR IGNORE INTO knowledge_primary_retired SELECT partition_key FROM knowledge_primary_partitions p " +
                "WHERE NOT EXISTS(SELECT 1 FROM knowledge_primary_refs r WHERE r.partition_key=p.partition_key) LIMIT 8")
            db.execSQL("DELETE FROM knowledge_primary_partitions WHERE partition_key IN(SELECT partition_key FROM knowledge_primary_retired)")
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        // The durable retirement queue survives a crash between catalog removal and unlink.
        val keys = db.rawQuery("SELECT partition_key FROM knowledge_primary_retired ORDER BY partition_key LIMIT 8", null).use {
            buildList { while (it.moveToNext()) add(it.getString(0)) }
        }
        var bytes = 0L
        for (key in keys) {
            checkActive()
            bytes = Math.addExact(bytes, primary.removeRetired(key))
            db.delete("knowledge_primary_retired", "partition_key=?", arrayOf(key))
        }
        val more = db.rawQuery("SELECT 1 FROM knowledge_primary_retired UNION ALL " +
            "SELECT 1 FROM knowledge_primary_partitions p WHERE NOT EXISTS(" +
            "SELECT 1 FROM knowledge_primary_refs r WHERE r.partition_key=p.partition_key) LIMIT 1", null).use { it.moveToFirst() }
        return Page(keys.size, bytes, !more)
    }
}
