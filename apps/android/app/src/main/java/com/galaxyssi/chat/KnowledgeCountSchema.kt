package com.galaxyssi.chat

/** Derived counters, not authentication or a substitute for source/vector integrity checks. */
internal object KnowledgeCountSchema {
    enum class Kind(val table: String, val field: String, val keys: List<String>) {
        VECTOR("knowledge_vectors", "chunks", listOf("item_key", "model_key", "ordinal")),
        QUEUE("knowledge_vector_queue", "pending", listOf("model_key", "item_key"))
    }

    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_vector_counts(model_key TEXT PRIMARY KEY " +
            "REFERENCES knowledge_vector_models(model_key) ON DELETE CASCADE," +
            "chunks INTEGER NOT NULL DEFAULT 0 CHECK(typeof(chunks)='integer' AND chunks>=0)," +
            "pending INTEGER NOT NULL DEFAULT 0 CHECK(typeof(pending)='integer' AND pending>=0)," +
            "legacy INTEGER NOT NULL DEFAULT 0 CHECK(legacy IN (0,1)))")
        db.execSQL("CREATE TABLE knowledge_count_scan(kind TEXT PRIMARY KEY," +
            "after_item TEXT NOT NULL DEFAULT '',after_model TEXT NOT NULL DEFAULT ''," +
            "after_ordinal INTEGER NOT NULL DEFAULT -1 CHECK(typeof(after_ordinal)='integer' AND after_ordinal>=-1)," +
            "complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0,1)))")
        // Only the small model directory is copied. No corpus COUNT, index build or row rewrite.
        db.execSQL("INSERT INTO knowledge_vector_counts(model_key,legacy) SELECT model_key,1 FROM knowledge_vector_models")
        db.execSQL("CREATE TRIGGER knowledge_count_model AFTER INSERT ON knowledge_vector_models BEGIN " +
            "INSERT INTO knowledge_vector_counts(model_key) VALUES(NEW.model_key); END")
        Kind.entries.forEach { kind ->
            db.execSQL("INSERT INTO knowledge_count_scan(kind,complete) VALUES('${kind.name}'," +
                "NOT EXISTS(SELECT 1 FROM ${kind.table} LIMIT 1))")
            // A CHECK on ADD COLUMN would validate all old rows. Validate new changes with triggers instead.
            db.execSQL("ALTER TABLE ${kind.table} ADD COLUMN count_tracked INTEGER NOT NULL DEFAULT 0")
            installTriggers(db, kind)
        }
    }

    private fun installTriggers(db: KnowledgeSqlite, kind: Kind) {
        val table = kind.table
        val name = "knowledge_count_${kind.name.lowercase()}"
        val identity = kind.keys.joinToString(" AND ") { "$it=NEW.$it" }
        db.execSQL("CREATE TRIGGER ${name}_insert_guard BEFORE INSERT ON $table " +
            "WHEN typeof(NEW.count_tracked)!='integer' OR NEW.count_tracked!=0 BEGIN " +
            "SELECT RAISE(ABORT,'Invalid new count tracking state'); END")
        db.execSQL("CREATE TRIGGER ${name}_update_guard BEFORE UPDATE ON $table WHEN " +
            "typeof(NEW.count_tracked)!='integer' OR NEW.count_tracked NOT IN (0,1) OR " +
            "NEW.count_tracked<OLD.count_tracked OR " + kind.keys.joinToString(" OR ") { "NEW.$it IS NOT OLD.$it" } +
            " BEGIN SELECT RAISE(ABORT,'Invalid count identity or tracking transition'); END")
        db.execSQL("CREATE TRIGGER ${name}_insert AFTER INSERT ON $table BEGIN " +
            "UPDATE $table SET count_tracked=1 WHERE $identity; " + changed() + " END")
        db.execSQL("CREATE TRIGGER ${name}_track AFTER UPDATE OF count_tracked ON $table " +
            "WHEN OLD.count_tracked=0 AND NEW.count_tracked=1 BEGIN " +
            "UPDATE knowledge_vector_counts SET ${kind.field}=${kind.field}+1 WHERE model_key=NEW.model_key; " +
            changed() + " END")
        db.execSQL("CREATE TRIGGER ${name}_delete AFTER DELETE ON $table WHEN OLD.count_tracked=1 AND " +
            "EXISTS(SELECT 1 FROM knowledge_vector_models WHERE model_key=OLD.model_key) BEGIN " +
            "UPDATE knowledge_vector_counts SET ${kind.field}=${kind.field}-1 WHERE model_key=OLD.model_key; " +
            changed() + " END")
    }

    private fun changed() = "SELECT CASE WHEN changes()!=1 THEN RAISE(ABORT,'Memory count update was lost') END;"
}
