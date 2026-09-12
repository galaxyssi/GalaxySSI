package com.galaxyssi.chat

internal object KnowledgeSourceRevisionFixtureSchema {
    fun remove(db: KnowledgeSqlite) {
        KnowledgePrimaryLegacyFixture.removePrimarySchemaBeforeDowngrade(db)
        val payloads = db.rawQuery("SELECT 1 FROM sqlite_master WHERE name='knowledge_payloads'", null).use { it.moveToFirst() }
        if (payloads) {
            // Old-format fixtures must be inline; never discard a live external body to fake a downgrade.
            db.rawQuery("SELECT 1 FROM knowledge_payloads LIMIT 1", null).use {
                check(!it.moveToFirst()) { "Legacy fixture requires inline payloads" }
            }
            db.execSQL("DROP TABLE knowledge_payloads")
        }
        db.execSQL("DROP TABLE IF EXISTS knowledge_payload_migration")
        db.execSQL("DROP TABLE IF EXISTS knowledge_payload_usage")
        db.execSQL("DROP TABLE IF EXISTS knowledge_payload_usage_scan")
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
