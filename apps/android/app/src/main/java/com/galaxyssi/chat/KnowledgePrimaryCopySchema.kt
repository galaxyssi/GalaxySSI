package com.galaxyssi.chat

internal object KnowledgePrimaryCopySchema {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_primary_copy(id INTEGER PRIMARY KEY CHECK(id=1),item_key TEXT NOT NULL," +
            "source_partition TEXT NOT NULL REFERENCES knowledge_primary_partitions(partition_key)," +
            "destination_partition TEXT NOT NULL REFERENCES knowledge_primary_partitions(partition_key)," +
            "original TEXT NOT NULL,checkpoint TEXT NOT NULL,CHECK(source_partition<>destination_partition))")
    }
}
