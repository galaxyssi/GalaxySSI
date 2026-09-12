package com.galaxyssi.chat

/** Downgrade only isolated fixtures; production never drops or rescans these columns. */
internal object KnowledgeCountFixtureSchema {
    fun remove(db: KnowledgeSqlite) {
        KnowledgeSourceDirectoryFixtureSchema.remove(db)
        val present = db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='knowledge_vector_counts'", null)
            .use { it.moveToFirst() }
        if (!present) return
        db.execSQL("DROP TRIGGER knowledge_count_model")
        KnowledgeCountSchema.Kind.entries.forEach { kind ->
            for (suffix in listOf("insert_guard", "update_guard", "insert", "track", "delete"))
                db.execSQL("DROP TRIGGER knowledge_count_${kind.name.lowercase()}_$suffix")
            db.execSQL("ALTER TABLE ${kind.table} DROP COLUMN count_tracked")
        }
        db.execSQL("DROP TABLE knowledge_count_scan")
        db.execSQL("DROP TABLE knowledge_vector_counts")
    }
}
