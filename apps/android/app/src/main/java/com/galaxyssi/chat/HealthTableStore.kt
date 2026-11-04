package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.Closeable
import java.util.UUID
import org.json.JSONObject

/** Source rows, mapping checkpoints and observation ownership share a transaction boundary. */
internal class HealthTableStore(context: Context, private val name: String = "health_records_v1.db") : Closeable {
    private val records = HealthRecordStore(context, name)
    private val db get() = records.tableDatabase
    private fun aad(kind: String, id: String) = "$name|health-table-v1|$kind|$id".toByteArray(Charsets.UTF_8)
    private fun pack(kind: String, id: String, value: JSONObject): ByteArray {
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(bytes, aad(kind, id)) } finally { bytes.fill(0) }
    }
    private fun unpack(kind: String, id: String, bytes: ByteArray): JSONObject {
        val value = AgentStorageCipher.decryptBinary(bytes, aad(kind, id))
        return try { JSONObject(String(value, Charsets.UTF_8)) } finally { value.fill(0) }
    }
    private fun <T> transaction(block: () -> T): T {
        db.beginTransaction()
        return try { block().also { db.setTransactionSuccessful() } } finally { db.endTransaction(); records.publishCommittedChanges() }
    }
    fun batch(id: String): HealthTableBatch? = db.rawQuery("SELECT state,payload FROM health_tables WHERE id=?", arrayOf(id)).use {
        if (!it.moveToFirst()) null else HealthTableBatch.from(unpack("batch", id, it.getBlob(1))).also { value -> check(value.id == id && value.state.name == it.getString(0)) }
    }
    private fun put(batch: HealthTableBatch) {
        val bytes = pack("batch", batch.id, batch.json())
        try { val values = ContentValues().apply {
            put("id", batch.id); put("state", batch.state.name); put("payload", bytes)
        }
            if (db.update("health_tables", values, "id=?", arrayOf(batch.id)) == 0) db.insertOrThrow("health_tables", null, values)
        } finally { bytes.fill(0) }
    }
    fun begin(id: String, original: HealthOriginal, format: String): HealthTableBatch = transaction {
        require(UUID.fromString(id).toString() == id)
        val previous = batch(id)
        if (previous != null) {
            check(previous.originalId == original.id && previous.sha256 == original.sha256 && previous.format == format)
            previous
        } else HealthTableBatch(id, original.id, original.sha256, original.name, format).also(::put)
    }
    fun workbook(id: String, sheets: List<HealthXlsxSheet>, date1904: Boolean) = transaction {
        val batch = requireNotNull(batch(id)); check(batch.format == "xlsx" && batch.state == HealthTableState.READING && batch.sheetIndex < 0)
        put(batch.copy(sheets = sheets, date1904 = date1904, state = HealthTableState.SHEET_SELECTION))
    }
    fun configureSheet(id: String, expectedRevision: Int, index: Int, headerRow: Int, load: Boolean = false) = transaction {
        val batch = requireNotNull(batch(id))
        check(batch.format == "xlsx" && batch.mappingRevision == expectedRevision &&
            batch.state in listOf(HealthTableState.SHEET_SELECTION, HealthTableState.MAPPING, HealthTableState.READY))
        require((index == -1 && !load || batch.sheets.any { it.index == index }) && headerRow in 1..1_048_576)
        db.delete("health_table_rows", "batch_id=?", arrayOf(id))
        put(batch.copy(sheetIndex = index, headerRow = headerRow, rows = 0, cursor = 0, headers = emptyList(), mapping = HealthTableMapping(),
            mappingRevision = batch.mappingRevision + 1, state = if (load) HealthTableState.READING else HealthTableState.SHEET_SELECTION, error = ""))
    }
    fun cancelReading(id: String, expectedRevision: Int) = transaction {
        val batch = requireNotNull(batch(id)); check(batch.format == "xlsx" && batch.state == HealthTableState.READING && batch.mappingRevision == expectedRevision)
        db.delete("health_table_rows", "batch_id=?", arrayOf(id))
        put(batch.copy(rows = 0, cursor = 0, headers = emptyList(), state = HealthTableState.SHEET_SELECTION, mappingRevision = batch.mappingRevision + 1, error = ""))
    }
    fun append(id: String, rows: List<HealthTableRow>, expectedRevision: Int? = null) = transaction {
        val batch = requireNotNull(batch(id))
        if (batch.state != HealthTableState.READING || expectedRevision != null && batch.mappingRevision != expectedRevision) throw java.util.concurrent.CancellationException()
        var last = batch.rows
        rows.forEach { row ->
            check(row.number == last + 1)
            val bytes = pack("row", "$id:${row.number}", row.json())
            try { db.insertOrThrow("health_table_rows", null, ContentValues().apply {
                put("batch_id", id); put("number", row.number); put("payload", bytes); put("state", HealthTableRowState.PENDING.name)
                put("issue", ""); put("record_id", ""); put("created_revision", 0)
            }) } finally { bytes.fill(0) }
            last = row.number
        }
        put(batch.copy(rows = last))
    }
    fun finishReading(id: String, headers: List<String>, expectedRevision: Int? = null) = transaction {
        val batch = requireNotNull(batch(id))
        if (batch.state != HealthTableState.READING || expectedRevision != null && batch.mappingRevision != expectedRevision) throw java.util.concurrent.CancellationException()
        if (batch.rows == 0L) throw HealthImportFailure("table_empty")
        put(batch.copy(headers = headers, state = HealthTableState.MAPPING,
            mapping = HealthTablePolicy.suggest(headers, HealthMetric.BLOOD_PRESSURE)))
    }
    fun mapping(id: String, expectedRevision: Int, value: HealthTableMapping, validate: Boolean) = transaction {
        val batch = requireNotNull(batch(id))
        check(batch.mappingRevision == expectedRevision && batch.state in listOf(HealthTableState.MAPPING, HealthTableState.READY))
        if (validate) require(value.valid(batch.headers))
        db.execSQL("UPDATE health_table_rows SET state=?,issue='',dedupe=NULL WHERE batch_id=?",
            arrayOf(HealthTableRowState.PENDING.name, id))
        put(batch.copy(mapping = value, mappingRevision = batch.mappingRevision + 1, cursor = 0,
            state = if (validate) HealthTableState.VALIDATING else HealthTableState.MAPPING, error = ""))
    }
    fun page(id: String, after: Long = 0, limit: Int = PAGE_SIZE): List<HealthTablePreview> {
        require(limit in 1..PAGE_SIZE)
        return db.rawQuery("SELECT number,payload,state,issue,record_id FROM health_table_rows WHERE batch_id=? AND number>? ORDER BY number LIMIT $limit",
            arrayOf(id, after.toString())).use { cursor -> buildList {
            while (cursor.moveToNext()) {
                val number = cursor.getLong(0)
                val row = HealthTableRow.from(unpack("row", "$id:$number", cursor.getBlob(1)))
                check(row.number == number)
                add(HealthTablePreview(row, HealthTableRowState.valueOf(cursor.getString(2)), cursor.getString(3), cursor.getString(4)))
            }
        } }
    }
    fun counts(id: String) = HealthTableCounts(db.rawQuery("SELECT state,COUNT(*) FROM health_table_rows WHERE batch_id=? GROUP BY state", arrayOf(id))
        .use { cursor -> buildMap { while (cursor.moveToNext()) put(HealthTableRowState.valueOf(cursor.getString(0)), cursor.getLong(1)) } })
    fun confirmSave(id: String, expectedRevision: Int) = transaction {
        val batch = requireNotNull(batch(id))
        check(batch.mappingRevision == expectedRevision && batch.state == HealthTableState.READY && batch.cursor == batch.rows)
        require(batch.mapping.valid(batch.headers))
        put(batch.copy(state = HealthTableState.SAVING, cursor = 0))
    }
    fun undo(id: String) = transaction {
        val batch = requireNotNull(batch(id)); check(batch.state == HealthTableState.SAVED)
        put(batch.copy(state = HealthTableState.UNDOING, cursor = 0))
    }
    fun pause(id: String) = transaction {
        val batch = requireNotNull(batch(id))
        if (batch.state == HealthTableState.VALIDATING) put(batch.copy(state = HealthTableState.MAPPING, cursor = 0))
    }
    fun fail(id: String, code: String, expectedPhase: HealthTableState? = null, expectedRevision: Int? = null) = transaction {
        val batch = requireNotNull(batch(id))
        if ((expectedPhase == null || batch.state == expectedPhase) && (expectedRevision == null || batch.mappingRevision == expectedRevision)) put(batch.copy(error = code))
    }
    fun active(after: String = ""): List<String> = db.rawQuery("SELECT id FROM health_tables WHERE id>? AND state IN (?,?,?,?) ORDER BY id LIMIT 100",
        arrayOf(after, HealthTableState.VALIDATING.name, HealthTableState.SAVING.name, HealthTableState.UNDOING.name, HealthTableState.READING.name))
        .use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }

    /** One small transaction advances both the output records and its durable cursor. */
    fun step(id: String, expectedPhase: HealthTableState? = null, expectedRevision: Int? = null): Boolean = transaction {
        val batch = requireNotNull(batch(id))
        if (expectedPhase != null && batch.state != expectedPhase || expectedRevision != null && batch.mappingRevision != expectedRevision) return@transaction false
        if (batch.state !in listOf(HealthTableState.VALIDATING, HealthTableState.SAVING, HealthTableState.UNDOING)) return@transaction false
        val rows = page(id, batch.cursor)
        check(rows.isNotEmpty() && rows.withIndex().all { it.value.row.number == batch.cursor + it.index + 1 }) { "Health source row is missing" }
        rows.forEach { preview ->
            var state = preview.state; var issue = preview.issue; var recordId = preview.recordId; var created = 0
            var duplicateKey: String? = null
            when (batch.state) {
                HealthTableState.VALIDATING -> {
                    val evaluation = HealthTablePolicy.evaluate(batch, preview.row)
                    state = evaluation.state; issue = evaluation.issue
                    evaluation.draft?.let { draft ->
                        duplicateKey = AgentMemoryIndexKey.token("$name|health-table-dedupe|${HealthObservationPolicy.duplicateKey(HealthObservationPolicy.observation(draft))}")
                        val existing = records.duplicateFor(draft)
                        val earlier = db.rawQuery("SELECT number FROM health_table_rows WHERE batch_id=? AND dedupe=? AND number<? AND state=? LIMIT 1",
                            arrayOf(id, duplicateKey, preview.row.number.toString(), HealthTableRowState.VALID.name)).use { it.moveToFirst() }
                        if (existing != null || earlier) { state = HealthTableRowState.DUPLICATE; recordId = existing.orEmpty() }
                    }
                }
                HealthTableState.SAVING -> if (state == HealthTableRowState.VALID) {
                    val evaluation = HealthTablePolicy.evaluate(batch, preview.row)
                    val draft = requireNotNull(evaluation.draft)
                    when (val result = records.save(draft)) {
                        is HealthSaveResult.Saved -> { state = HealthTableRowState.SAVED; recordId = result.record.id; created = result.record.revision }
                        is HealthSaveResult.Duplicate -> { state = HealthTableRowState.DUPLICATE; recordId = result.id }
                        HealthSaveResult.Conflict -> error("Table observation revision conflict")
                    }
                }
                HealthTableState.UNDOING -> if (state == HealthTableRowState.SAVED) {
                    val createdRevision = db.rawQuery("SELECT created_revision FROM health_table_rows WHERE batch_id=? AND number=?",
                        arrayOf(id, preview.row.number.toString())).use { it.moveToFirst(); it.getInt(0) }
                    val record = records.record(recordId)
                    state = when {
                        record == null -> HealthTableRowState.UNDONE
                        record.revision != createdRevision || record.draft.evidence?.jobId != id -> HealthTableRowState.EDITED
                        records.delete(recordId, createdRevision) -> HealthTableRowState.UNDONE
                        else -> error("Table undo revision conflict")
                    }
                }
                else -> Unit
            }
            db.update("health_table_rows", ContentValues().apply {
                put("state", state.name); put("issue", issue); put("record_id", recordId)
                if (batch.state == HealthTableState.VALIDATING) put("dedupe", duplicateKey)
                if (created > 0) put("created_revision", created)
            }, "batch_id=? AND number=?", arrayOf(id, preview.row.number.toString()))
        }
        val cursor = rows.lastOrNull()?.row?.number ?: batch.rows
        val finished = cursor >= batch.rows
        val next = if (!finished) batch.state else when (batch.state) {
            HealthTableState.VALIDATING -> HealthTableState.READY
            HealthTableState.SAVING -> HealthTableState.SAVED
            else -> HealthTableState.UNDONE
        }
        put(batch.copy(cursor = cursor, state = next, error = ""))
        !finished
    }
    override fun close() = records.close()
    companion object {
        const val PAGE_SIZE = 30
        fun createSchema(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE health_tables(id TEXT PRIMARY KEY,state TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX health_table_active ON health_tables(state,id)")
            db.execSQL("CREATE TABLE health_table_rows(batch_id TEXT NOT NULL REFERENCES health_tables(id),number INTEGER NOT NULL," +
                "payload BLOB NOT NULL,state TEXT NOT NULL,issue TEXT NOT NULL,record_id TEXT NOT NULL,created_revision INTEGER NOT NULL,dedupe TEXT," +
                "PRIMARY KEY(batch_id,number))")
            db.execSQL("CREATE INDEX health_table_duplicate ON health_table_rows(batch_id,dedupe,number,state)")
            db.execSQL("CREATE INDEX health_table_counts ON health_table_rows(batch_id,state)")
        }
    }
}
