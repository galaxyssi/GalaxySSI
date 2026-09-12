package com.galaxyssi.chat

/** The catalog publishes references; immutable encrypted bodies live in physical partitions. */
internal object KnowledgePrimarySchema {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_primary_partitions(partition_key TEXT PRIMARY KEY,bucket INTEGER NOT NULL CHECK(bucket BETWEEN 0 AND 3)," +
            "bytes INTEGER NOT NULL CHECK(typeof(bytes)='integer' AND bytes>=0)," +
            "records INTEGER NOT NULL CHECK(typeof(records)='integer' AND records>=0),sealed INTEGER NOT NULL CHECK(sealed IN (0,1)))")
        db.execSQL("CREATE UNIQUE INDEX knowledge_primary_active ON knowledge_primary_partitions(bucket) WHERE sealed=0")
        db.execSQL("CREATE TABLE knowledge_primary_refs(item_key TEXT PRIMARY KEY REFERENCES knowledge_items(item_key) ON DELETE CASCADE," +
            "partition_key TEXT NOT NULL REFERENCES knowledge_primary_partitions(partition_key),reference TEXT NOT NULL)")
        db.execSQL("CREATE INDEX knowledge_primary_membership ON knowledge_primary_refs(partition_key,item_key)")
        db.execSQL("CREATE TABLE knowledge_primary_retired(partition_key TEXT PRIMARY KEY)")
        db.execSQL("CREATE TABLE knowledge_primary_migration(id INTEGER PRIMARY KEY CHECK(id=1),after_item TEXT NOT NULL," +
            "complete INTEGER NOT NULL CHECK(complete IN (0,1)))")
        db.execSQL("INSERT INTO knowledge_primary_migration SELECT 1,'',CASE WHEN EXISTS(SELECT 1 FROM knowledge_items LIMIT 1) THEN 0 ELSE 1 END")
    }
}
