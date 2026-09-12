package com.galaxyssi.chat

/** Version 15: indexed dirty work and resumable discovery, without a whole-catalog startup scan. */
internal object KnowledgePrimaryCompactionSchema {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_primary_dirty(partition_key TEXT PRIMARY KEY)")
        db.execSQL("CREATE TABLE knowledge_primary_compaction(id INTEGER PRIMARY KEY CHECK(id=1)," +
            "after_partition TEXT NOT NULL,discovered INTEGER NOT NULL CHECK(discovered IN (0,1)),source TEXT NOT NULL)")
        db.execSQL("INSERT INTO knowledge_primary_compaction VALUES(1,'',0,'')")
        db.execSQL("CREATE TRIGGER knowledge_primary_dirty_insert AFTER INSERT ON knowledge_primary_partitions BEGIN " +
            "INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(NEW.partition_key); END")
        db.execSQL("CREATE TRIGGER knowledge_primary_dirty_delete AFTER DELETE ON knowledge_primary_refs BEGIN " +
            "INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(OLD.partition_key); END")
        db.execSQL("CREATE TRIGGER knowledge_primary_dirty_move AFTER UPDATE OF partition_key ON knowledge_primary_refs " +
            "WHEN OLD.partition_key<>NEW.partition_key BEGIN " +
            "INSERT OR IGNORE INTO knowledge_primary_dirty VALUES(OLD.partition_key); END")
    }
}
