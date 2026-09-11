package com.galaxyssi.chat

/** Only isolated fixtures simulate an old schema; production migration never drops these tables. */
internal object KnowledgeSourceDirectoryFixtureSchema {
    fun remove(db: KnowledgeSqlite) {
        val present = db.rawQuery("SELECT 1 FROM sqlite_master WHERE name='knowledge_source_state'", null).use { it.moveToFirst() }
        if (!present) return
        for (suffix in listOf("group_insert", "group_delete", "member_immutable", "member_insert", "member_delete", "item_insert", "item_update"))
            db.execSQL("DROP TRIGGER knowledge_source_$suffix")
        db.execSQL("DROP TABLE knowledge_source_members")
        db.execSQL("DROP TABLE knowledge_source_directory")
        db.execSQL("DROP TABLE knowledge_source_state")
    }
}
