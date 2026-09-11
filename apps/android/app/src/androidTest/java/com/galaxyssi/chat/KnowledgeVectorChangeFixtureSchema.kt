package com.galaxyssi.chat

/** Only isolated test databases use this downgrade to reproduce real pre-v5 layouts. */
internal object KnowledgeVectorChangeFixtureSchema {
    fun remove(db: KnowledgeSqlite) {
        for (trigger in listOf("model", "head", "insert", "update", "delete", "tracked_insert", "tracked_update"))
            db.execSQL("DROP TRIGGER knowledge_vector_feed_$trigger")
        db.execSQL("DROP TABLE knowledge_vector_changes")
        db.execSQL("DROP TABLE knowledge_vector_feed_state")
        db.execSQL("ALTER TABLE knowledge_vector_docs DROP COLUMN feed_tracked")
    }
}
