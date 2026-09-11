package com.galaxyssi.chat

/** Transactional derived-index hints. Source ciphertext and authenticated vectors remain authoritative. */
internal object KnowledgeVectorChangeSchema {
    fun create(db: KnowledgeSqlite) {
        // No source/vector scan or new index over the existing corpus during migration.
        db.execSQL("ALTER TABLE knowledge_vector_docs ADD COLUMN feed_tracked INTEGER NOT NULL DEFAULT 0")
        for ((suffix, operation) in listOf("tracked_insert" to "INSERT", "tracked_update" to "UPDATE OF feed_tracked")) {
            db.execSQL("CREATE TRIGGER knowledge_vector_feed_$suffix BEFORE $operation ON knowledge_vector_docs " +
                "WHEN NEW.feed_tracked NOT IN (0,1) BEGIN SELECT RAISE(ABORT,'Invalid vector feed tracking state'); END")
        }
        db.execSQL("CREATE TABLE knowledge_vector_feed_state (model_key TEXT PRIMARY KEY REFERENCES knowledge_vector_models(model_key) " +
            "ON DELETE CASCADE,epoch TEXT NOT NULL,head INTEGER NOT NULL DEFAULT 0 CHECK(typeof(head)='integer' AND head>=0)," +
            "completed_chunks INTEGER NOT NULL DEFAULT 0 CHECK(typeof(completed_chunks)='integer' AND completed_chunks>=0)," +
            "bootstrap_after TEXT NOT NULL DEFAULT '',bootstrap_complete INTEGER NOT NULL DEFAULT 1 CHECK(bootstrap_complete IN (0,1)))")
        db.execSQL("CREATE TABLE knowledge_vector_changes (sequence INTEGER PRIMARY KEY AUTOINCREMENT," +
            "model_key TEXT NOT NULL REFERENCES knowledge_vector_models(model_key) ON DELETE CASCADE,item_key TEXT NOT NULL," +
            "operation INTEGER NOT NULL CHECK(operation IN (0,1)),revision TEXT NOT NULL,chunk_count INTEGER NOT NULL CHECK(chunk_count>=0)," +
            "previous INTEGER NOT NULL CHECK(previous>=0))")
        db.execSQL("CREATE INDEX knowledge_vector_changes_model ON knowledge_vector_changes(model_key,sequence)")
        db.execSQL("INSERT INTO knowledge_vector_feed_state(model_key,epoch,bootstrap_complete) " +
            "SELECT model_key,lower(hex(randomblob(16))),0 FROM knowledge_vector_models")
        db.execSQL("CREATE TRIGGER knowledge_vector_feed_model AFTER INSERT ON knowledge_vector_models BEGIN " +
            "INSERT INTO knowledge_vector_feed_state(model_key,epoch) VALUES(NEW.model_key,lower(hex(randomblob(16)))); END")
        db.execSQL("CREATE TRIGGER knowledge_vector_feed_head AFTER INSERT ON knowledge_vector_changes BEGIN " +
            "UPDATE knowledge_vector_feed_state SET head=NEW.sequence WHERE model_key=NEW.model_key; END")
        db.execSQL("CREATE TRIGGER knowledge_vector_feed_insert AFTER INSERT ON knowledge_vector_docs " +
            "WHEN NEW.complete=1 AND NEW.feed_tracked=1 BEGIN " +
            event("NEW", 1) +
            "UPDATE knowledge_vector_feed_state SET completed_chunks=completed_chunks+NEW.chunk_count WHERE model_key=NEW.model_key; END")
        db.execSQL("CREATE TRIGGER knowledge_vector_feed_update AFTER UPDATE OF complete,feed_tracked,revision,chunk_count ON knowledge_vector_docs " +
            "WHEN OLD.complete!=NEW.complete OR OLD.feed_tracked!=NEW.feed_tracked OR OLD.revision!=NEW.revision OR OLD.chunk_count!=NEW.chunk_count BEGIN " +
            event("OLD", 0, "OLD.complete=1 AND OLD.feed_tracked=1") +
            event("NEW", 1, "NEW.complete=1 AND NEW.feed_tracked=1") +
            "UPDATE knowledge_vector_feed_state SET completed_chunks=completed_chunks+" +
            "(CASE WHEN NEW.complete=1 AND NEW.feed_tracked=1 THEN NEW.chunk_count ELSE 0 END)-" +
            "(CASE WHEN OLD.complete=1 AND OLD.feed_tracked=1 THEN OLD.chunk_count ELSE 0 END) WHERE model_key=NEW.model_key; END")
        db.execSQL("CREATE TRIGGER knowledge_vector_feed_delete AFTER DELETE ON knowledge_vector_docs " +
            "WHEN EXISTS(SELECT 1 FROM knowledge_vector_models WHERE model_key=OLD.model_key) BEGIN " +
            event("OLD", 0) +
            "UPDATE knowledge_vector_feed_state SET completed_chunks=completed_chunks-" +
            "(CASE WHEN OLD.complete=1 AND OLD.feed_tracked=1 THEN OLD.chunk_count ELSE 0 END) WHERE model_key=OLD.model_key; END")
    }
    private fun event(row: String, operation: Int, where: String = "1") =
        "INSERT INTO knowledge_vector_changes(model_key,item_key,operation,revision,chunk_count,previous) " +
            "SELECT $row.model_key,$row.item_key,$operation,$row.revision,$row.chunk_count," +
            "(SELECT head FROM knowledge_vector_feed_state WHERE model_key=$row.model_key) WHERE $where; "
}
