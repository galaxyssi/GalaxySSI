package com.galaxyssi.chat

import android.database.Cursor
import android.database.sqlite.SQLiteDatabase

/** The legacy ciphertext keeps its original logical AAD namespace after the physical move. */
internal object HealthOriginalMetadataMigration {
    private const val INLINE_BYTES = 512 * 1024
    private val columns = linkedMapOf(
        "originals" to "id,imported_at,digest_token,payload,key_payload,kind",
        "imports" to "job_id,original_id",
        "jobs" to "id,created_at,state,payload",
        "pages" to "job_id,page_number,payload",
        "capture_batches" to "id,payload",
        "capture_pages" to "job_id,batch_id,position,payload",
        "library_exports" to "id,state,attempt,created_at,payload,key_payload",
        "library_export_items" to "session_id,original_id,snapshot"
    )

    fun migrate(target: SQLiteDatabase, namespace: String, source: () -> SQLiteDatabase?) {
        fun committed(): Boolean = target.rawQuery("SELECT source FROM health_original_metadata_migration WHERE id=1", null).use {
            it.moveToFirst().also { found -> if (found) check(it.getString(0) == namespace) { "Health original namespace mismatch" } }
        }
        if (committed()) return
        check(!target.inTransaction()) { "Health original migration must precede writes" }
        target.beginTransactionNonExclusive()
        try {
            if (!committed()) {
                source()?.let { legacy ->
                    check(legacy.path != target.path)
                    legacy.beginTransactionNonExclusive()
                    try {
                        columns.forEach { (table, names) -> copy(legacy, target, table, names) }
                        legacy.setTransactionSuccessful()
                    } finally { legacy.endTransaction() }
                }
                target.execSQL("INSERT INTO health_original_metadata_migration(id,source) VALUES(1,?)", arrayOf(namespace))
            }
            target.setTransactionSuccessful()
        } finally { target.endTransaction() }
    }

    private fun copy(source: SQLiteDatabase, target: SQLiteDatabase, table: String, columns: String) {
        val names = columns.split(',')
        val blobs = names.filter { it in setOf("payload", "key_payload", "snapshot") }
        val projection = names.joinToString(",") { name ->
            if (name in blobs) "CASE WHEN length($name)<=$INLINE_BYTES THEN $name END" else name
        }
        val lengths = blobs.joinToString(",") { "length($it)" }
        val suffix = if (lengths.isEmpty()) "" else ",$lengths"
        source.rawQuery("SELECT rowid,$projection$suffix FROM $table", null).use { rows ->
            val placeholders = List(names.size) { "?" }.joinToString(",")
            target.compileStatement("INSERT INTO $table($columns) VALUES($placeholders)").use { insert ->
                while (rows.moveToNext()) {
                    insert.clearBindings()
                    names.forEachIndexed { index, name ->
                        val column = index + 1
                        val lengthIndex = blobs.indexOf(name).let { if (it < 0) -1 else names.size + 1 + it }
                        val size = if (lengthIndex >= 0 && !rows.isNull(lengthIndex)) rows.getInt(lengthIndex) else 0
                        if (size > INLINE_BYTES) {
                            insert.bindBlob(column, blob(source, table, name, rows.getLong(0), size))
                        } else when (rows.getType(column)) {
                            Cursor.FIELD_TYPE_NULL -> insert.bindNull(column)
                            Cursor.FIELD_TYPE_INTEGER -> insert.bindLong(column, rows.getLong(column))
                            Cursor.FIELD_TYPE_STRING -> insert.bindString(column, rows.getString(column))
                            Cursor.FIELD_TYPE_BLOB -> insert.bindBlob(column, rows.getBlob(column))
                            else -> error("Unsupported health metadata storage type")
                        }
                    }
                    insert.executeInsert()
                }
            }
        }
    }

    private fun blob(source: SQLiteDatabase, table: String, column: String, row: Long, size: Int): ByteArray {
        // Some OCR pages exceed a CursorWindow; copy their ciphertext in bounded slices.
        val output = ByteArray(size)
        var copied = 0
        while (copied < size) {
            val expected = minOf(size - copied, INLINE_BYTES)
            source.rawQuery("SELECT substr($column,?,?) FROM $table WHERE rowid=?",
                arrayOf((copied + 1).toString(), expected.toString(), row.toString())).use {
                check(it.moveToFirst())
                val chunk = it.getBlob(0)
                check(chunk.size == expected)
                chunk.copyInto(output, copied)
            }
            copied += expected
        }
        return output
    }
}
