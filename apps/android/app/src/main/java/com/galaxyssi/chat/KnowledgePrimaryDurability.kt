package com.galaxyssi.chat

/** DELETE-journal commits must persist journal unlink before the separate WAL catalog can commit. */
internal object KnowledgePrimaryDurability {
    fun configureWriter(db: KnowledgeSqlite) {
        val journal = db.rawQuery("PRAGMA journal_mode", null).use { check(it.moveToFirst()); it.getString(0) }
        check(journal == "delete") { "Primary storage requires DELETE journaling" }
        db.execSQL("PRAGMA synchronous=EXTRA")
        val synchronous = db.rawQuery("PRAGMA synchronous", null).use { check(it.moveToFirst()); it.getInt(0) }
        check(synchronous == 3) { "Primary storage requires EXTRA synchronization" }
    }
}
