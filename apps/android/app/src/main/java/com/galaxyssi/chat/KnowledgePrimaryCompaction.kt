package com.galaxyssi.chat

/** Caller holds the exclusive cross-process snapshot lease and a catalog/primary transaction. */
internal object KnowledgePrimaryCompaction {
    private const val DISCOVERY_PAGE = 32
    private const val CANDIDATE_PAGE = 8
    private const val RECORD_PAGE = 8

    fun advance(db: KnowledgeSqlite, primary: KnowledgePrimaryPartitions, checkActive: () -> Unit): Int {
        discover(db, checkActive)
        var source = db.rawQuery("SELECT source FROM knowledge_primary_compaction WHERE id=1", null).use {
            check(it.moveToFirst()); it.getString(0)
        }
        if (source.isEmpty()) source = select(db, checkActive) ?: return 0
        val keys = db.rawQuery("SELECT item_key FROM knowledge_primary_refs WHERE partition_key=? ORDER BY item_key LIMIT $RECORD_PAGE",
            arrayOf(source)).use { buildList { while (it.moveToNext()) add(it.getString(0)) } }
        for (key in keys) {
            checkActive()
            primary.relocate(db, key, source, checkActive)
        }
        val remains = db.rawQuery("SELECT 1 FROM knowledge_primary_refs WHERE partition_key=? LIMIT 1", arrayOf(source)).use { it.moveToFirst() }
        if (!remains) {
            retire(db, source)
            db.execSQL("UPDATE knowledge_primary_compaction SET source='' WHERE id=1")
        }
        return keys.size
    }

    private fun discover(db: KnowledgeSqlite, checkActive: () -> Unit) {
        val after = db.rawQuery("SELECT after_partition FROM knowledge_primary_compaction WHERE id=1 AND discovered=0", null).use {
            if (!it.moveToFirst()) return
            it.getString(0)
        }
        val keys = db.rawQuery("SELECT partition_key FROM knowledge_primary_partitions WHERE partition_key>? ORDER BY partition_key LIMIT $DISCOVERY_PAGE",
            arrayOf(after)).use { buildList { while (it.moveToNext()) add(it.getString(0)) } }
        for (key in keys) {
            checkActive()
            db.rawQuery("INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(?)", arrayOf(key)).use { it.moveToNext() }
        }
        db.rawQuery("UPDATE knowledge_primary_compaction SET after_partition=?,discovered=? WHERE id=1",
            arrayOf(keys.lastOrNull() ?: after, if (keys.size < DISCOVERY_PAGE) "1" else "0")).use { it.moveToNext() }
    }

    private fun select(db: KnowledgeSqlite, checkActive: () -> Unit): String? {
        val keys = db.rawQuery("SELECT partition_key FROM knowledge_primary_dirty ORDER BY partition_key LIMIT $CANDIDATE_PAGE", null).use {
            buildList { while (it.moveToNext()) add(it.getString(0)) }
        }
        for (key in keys) {
            checkActive()
            val records = db.rawQuery("SELECT records FROM knowledge_primary_partitions WHERE partition_key=?", arrayOf(key)).use {
                if (it.moveToFirst()) it.getLong(0) else null
            }
            if (records != null) {
                val live = db.rawQuery("SELECT count(*) FROM knowledge_primary_refs WHERE partition_key=?", arrayOf(key)).use {
                    check(it.moveToFirst()); it.getLong(0)
                }
                if (live == 0L) retire(db, key)
                else if (live <= records / 2) {
                    // Seal even a partially filled active partition so future writers cannot refill the source.
                    db.rawQuery("UPDATE knowledge_primary_partitions SET sealed=1 WHERE partition_key=?", arrayOf(key)).use { it.moveToNext() }
                    db.rawQuery("UPDATE knowledge_primary_compaction SET source=? WHERE id=1", arrayOf(key)).use { it.moveToNext() }
                    return key
                }
            }
            db.delete("knowledge_primary_dirty", "partition_key=?", arrayOf(key))
        }
        return null
    }

    private fun retire(db: KnowledgeSqlite, key: String) {
        db.rawQuery("INSERT OR IGNORE INTO knowledge_primary_retired VALUES(?)", arrayOf(key)).use { it.moveToNext() }
        db.delete("knowledge_primary_partitions", "partition_key=?", arrayOf(key))
        db.delete("knowledge_primary_dirty", "partition_key=?", arrayOf(key))
    }

    fun pending(db: KnowledgeSqlite) = db.rawQuery("SELECT 1 FROM knowledge_primary_dirty UNION ALL " +
        "SELECT 1 FROM knowledge_primary_retired UNION ALL SELECT 1 FROM knowledge_primary_compaction " +
        "WHERE discovered=0 OR source<>'' LIMIT 1", null).use { it.moveToFirst() }
}
