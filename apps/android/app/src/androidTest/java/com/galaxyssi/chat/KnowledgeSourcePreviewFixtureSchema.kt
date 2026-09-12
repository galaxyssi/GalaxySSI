package com.galaxyssi.chat

internal object KnowledgeSourcePreviewFixtureSchema {
    fun remove(db: KnowledgeSqlite) {
        KnowledgeSourceRevisionFixtureSchema.remove(db)
        db.execSQL("DROP TRIGGER IF EXISTS knowledge_source_preview_invalidate")
        db.execSQL("DROP TABLE IF EXISTS knowledge_source_previews")
    }
    fun versionEight(f: KnowledgeBackupTestFixture) {
        f.store.close()
        KnowledgeSourceMigrationTestSupport.raw(f.name) { db ->
            db.beginTransaction()
            try { remove(db); db.execSQL("PRAGMA user_version=8"); db.setTransactionSuccessful() }
            finally { db.endTransaction() }
        }
        f.reopen()
    }
    fun count(f: KnowledgeBackupTestFixture): Int = f.db.access { db ->
        db.rawQuery("SELECT count(*) FROM knowledge_source_previews", null).use { check(it.moveToFirst()); it.getInt(0) }
    }
}
