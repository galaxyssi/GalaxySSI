package com.galaxyssi.chat

/** Empty derived tables at migration time; source ciphertext is never copied or rewritten. */
internal object KnowledgeSourceDirectorySchema {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_source_state(id INTEGER PRIMARY KEY CHECK(id=1)," +
            "after_item TEXT NOT NULL DEFAULT '',complete INTEGER NOT NULL CHECK(complete IN (0,1))," +
            "items INTEGER NOT NULL DEFAULT 0 CHECK(typeof(items)='integer' AND items>=0)," +
            "groups INTEGER NOT NULL DEFAULT 0 CHECK(typeof(groups)='integer' AND groups>=0)," +
            "named_groups INTEGER NOT NULL DEFAULT 0 CHECK(typeof(named_groups)='integer' AND named_groups>=0))")
        db.execSQL("INSERT INTO knowledge_source_state(id,complete) VALUES(1,NOT EXISTS(SELECT 1 FROM knowledge_items LIMIT 1))")
        db.execSQL("CREATE TABLE knowledge_source_directory(group_key TEXT PRIMARY KEY,sort_updated INTEGER NOT NULL," +
            "head TEXT NOT NULL,members INTEGER NOT NULL CHECK(typeof(members)='integer' AND members>0))")
        db.execSQL("CREATE INDEX knowledge_source_directory_order ON knowledge_source_directory(sort_updated,group_key)")
        db.execSQL("CREATE TABLE knowledge_source_members(item_key TEXT PRIMARY KEY REFERENCES knowledge_items(item_key) " +
            "ON DELETE CASCADE,group_key TEXT NOT NULL,sort_updated INTEGER NOT NULL)")
        db.execSQL("CREATE INDEX knowledge_source_members_order ON knowledge_source_members(group_key,sort_updated,item_key)")
        for ((operation, sign, alias) in listOf(Triple("insert", "+", "NEW"), Triple("delete", "-", "OLD"))) {
            db.execSQL("CREATE TRIGGER knowledge_source_group_$operation AFTER ${operation.uppercase()} ON knowledge_source_directory BEGIN " +
                "UPDATE knowledge_source_state SET groups=groups$sign 1,named_groups=named_groups$sign " +
                "(substr($alias.group_key,1,2)='s:') WHERE id=1; ${changed()} END")
        }
        db.execSQL("CREATE TRIGGER knowledge_source_member_immutable BEFORE UPDATE ON knowledge_source_members BEGIN " +
            "SELECT RAISE(ABORT,'Source membership updates require replacement'); END")
        val newer = "excluded.sort_updated<sort_updated OR (excluded.sort_updated=sort_updated AND excluded.head<head)"
        db.execSQL("CREATE TRIGGER knowledge_source_member_insert AFTER INSERT ON knowledge_source_members BEGIN " +
            "INSERT INTO knowledge_source_directory(group_key,sort_updated,head,members) VALUES(NEW.group_key,NEW.sort_updated,NEW.item_key,1) " +
            "ON CONFLICT(group_key) DO UPDATE SET members=members+1," +
            "head=CASE WHEN $newer THEN excluded.head ELSE head END,sort_updated=min(sort_updated,excluded.sort_updated); " +
            "UPDATE knowledge_source_state SET items=items+1 WHERE id=1; ${changed()} END")
        val next = "FROM knowledge_source_members WHERE group_key=OLD.group_key ORDER BY sort_updated,item_key LIMIT 1"
        db.execSQL("CREATE TRIGGER knowledge_source_member_delete AFTER DELETE ON knowledge_source_members BEGIN " +
            "SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM knowledge_source_directory WHERE group_key=OLD.group_key) " +
            "THEN RAISE(ABORT,'Source directory is missing') END; " +
            "DELETE FROM knowledge_source_directory WHERE group_key=OLD.group_key AND members=1; " +
            "UPDATE knowledge_source_directory SET members=members-1," +
            "sort_updated=CASE WHEN head=OLD.item_key THEN (SELECT sort_updated $next) ELSE sort_updated END," +
            "head=CASE WHEN head=OLD.item_key THEN (SELECT item_key $next) ELSE head END WHERE group_key=OLD.group_key; " +
            "UPDATE knowledge_source_state SET items=items-1 WHERE id=1; ${changed()} END")
        val insert = "INSERT INTO knowledge_source_members(item_key,group_key,sort_updated) " +
            "VALUES(NEW.item_key,${group("NEW")},~NEW.updated);"
        db.execSQL("CREATE TRIGGER knowledge_source_item_insert AFTER INSERT ON knowledge_items BEGIN $insert END")
        db.execSQL("CREATE TRIGGER knowledge_source_item_update AFTER UPDATE OF item_key,source_key,updated ON knowledge_items BEGIN " +
            "DELETE FROM knowledge_source_members WHERE item_key=OLD.item_key; $insert END")
    }

    private fun group(alias: String) = "CASE WHEN $alias.source_key='' THEN 'i:'||$alias.item_key ELSE 's:'||$alias.source_key END"
    private fun changed() = "SELECT CASE WHEN changes()!=1 THEN RAISE(ABORT,'Source directory state is missing') END;"
}
