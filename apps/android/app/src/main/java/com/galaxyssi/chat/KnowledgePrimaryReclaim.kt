package com.galaxyssi.chat

/** Called under the cross-process exclusive snapshot lease, outside any writer transaction. */
internal object KnowledgePrimaryReclaim {
    data class Page(val partitions: Int, val bytes: Long, val complete: Boolean, val movedRecords: Int = 0,
        val allocationEntries: Int = 0, val orphanAllocations: Int = 0)

    fun advance(db: KnowledgeSqlite, primary: KnowledgePrimaryPartitions, checkActive: () -> Unit): Page {
        checkActive()
        var moved = 0
        db.beginTransaction()
        try {
            primary.begin()
            moved = KnowledgePrimaryCompaction.advance(db, primary, checkActive)
            primary.prepareCommit()
            db.setTransactionSuccessful()
        } finally { try { db.endTransaction() } finally { if (primary.activeOnCurrentThread()) primary.end() } }
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
        val allocations = primary.allocations.replay(isReferenced = { id ->
            db.rawQuery("SELECT 1 FROM knowledge_primary_partitions WHERE partition_key=? UNION ALL " +
                "SELECT 1 FROM knowledge_primary_refs WHERE partition_key=? UNION ALL " +
                "SELECT 1 FROM knowledge_primary_copy WHERE source_partition=? OR destination_partition=? LIMIT 1",
                arrayOf(id, id, id, id)).use { it.moveToFirst() }
        }, verifyReferenced = primary::verifyRegistered, remove = primary::removeRetired, checkActive = checkActive)
        return Page(keys.size, Math.addExact(bytes, allocations.bytes),
            allocations.complete && !KnowledgePrimaryCompaction.pending(db), moved, allocations.visited, allocations.orphaned)
    }
}
