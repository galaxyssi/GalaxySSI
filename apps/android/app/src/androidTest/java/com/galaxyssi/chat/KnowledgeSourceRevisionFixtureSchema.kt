package com.galaxyssi.chat

internal object KnowledgeSourceRevisionFixtureSchema {
    fun remove(db: KnowledgeSqlite) {
        for (operation in listOf("insert", "update", "delete"))
            db.execSQL("DROP TRIGGER IF EXISTS knowledge_source_revision_$operation")
        db.execSQL("DROP TABLE IF EXISTS knowledge_source_revisions")
        db.execSQL("DROP TABLE IF EXISTS knowledge_source_revision_state")
    }
    fun versionNine(f: KnowledgeBackupTestFixture) {
        f.store.close()
        KnowledgeSourceMigrationTestSupport.raw(f.name) { db ->
            db.beginTransaction()
            try { remove(db); db.execSQL("PRAGMA user_version=9"); db.setTransactionSuccessful() }
            finally { db.endTransaction() }
        }
        f.reopen()
    }
}
