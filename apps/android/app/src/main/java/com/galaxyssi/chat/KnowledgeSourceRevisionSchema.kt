package com.galaxyssi.chat

import android.content.ContentValues
import java.util.UUID

/** Constant-work migration: old sources start at revision zero until their first mutation. */
internal object KnowledgeSourceRevisionSchema {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_source_revision_state(id INTEGER PRIMARY KEY CHECK(id=1),epoch TEXT NOT NULL," +
            "sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0))")
        db.insertOrThrow("knowledge_source_revision_state", null, ContentValues().apply {
            put("id", 1); put("epoch", UUID.randomUUID().toString()); put("sequence", 0L)
        })
        db.execSQL("CREATE TABLE knowledge_source_revisions(group_key TEXT PRIMARY KEY," +
            "sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>0))")
        db.execSQL("CREATE TRIGGER knowledge_source_revision_insert AFTER INSERT ON knowledge_items BEGIN ${advance()} ${touch("NEW")} END")
        db.execSQL("CREATE TRIGGER knowledge_source_revision_delete AFTER DELETE ON knowledge_items BEGIN " +
            "${advance()} ${touch("OLD")} ${removeEmpty()} END")
        db.execSQL("CREATE TRIGGER knowledge_source_revision_update AFTER UPDATE OF item_key,title_key,source_key,updated,header " +
            "ON knowledge_items BEGIN ${advance()} ${touch("OLD")} ${touch("NEW")} ${removeEmpty()} END")
    }
    private fun advance() = "UPDATE knowledge_source_revision_state SET sequence=sequence+1 WHERE id=1; " +
        "SELECT CASE WHEN changes()!=1 THEN RAISE(ABORT,'Source revision state is missing') END;"
    private fun group(alias: String) = "CASE WHEN $alias.source_key='' THEN 'i:'||$alias.item_key ELSE 's:'||$alias.source_key END"
    private fun touch(alias: String) = "INSERT INTO knowledge_source_revisions(group_key,sequence) " +
        "VALUES(${group(alias)},(SELECT sequence FROM knowledge_source_revision_state WHERE id=1)) " +
        "ON CONFLICT(group_key) DO UPDATE SET sequence=excluded.sequence; " +
        "SELECT CASE WHEN changes()!=1 THEN RAISE(ABORT,'Source revision was not persisted') END;"
    private fun removeEmpty() = "DELETE FROM knowledge_source_revisions WHERE group_key=${group("OLD")} AND " +
        "CASE WHEN OLD.source_key='' THEN NOT EXISTS(SELECT 1 FROM knowledge_items WHERE item_key=OLD.item_key AND source_key='' LIMIT 1) " +
        "ELSE NOT EXISTS(SELECT 1 FROM knowledge_items WHERE source_key=OLD.source_key LIMIT 1) END;"
}
