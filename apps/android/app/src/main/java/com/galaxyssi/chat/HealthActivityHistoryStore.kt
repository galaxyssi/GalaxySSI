package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import java.nio.ByteBuffer
import java.time.LocalDate

/** One encrypted total per local date and sensor kind; historical days have no retention cutoff. */
internal class HealthActivityHistoryStore(context: Context, private val name: String = DEFAULT_DB) : Closeable {
    private val helper = Database(context.applicationContext, name)
    private fun aad(kind: HealthActivityKind, day: Long) = "$name|activity-v1|${kind.name}|$day".toByteArray()
    fun save(kind: HealthActivityKind, day: LocalDate, total: Long) {
        require(total >= 0 && total <= if (kind == HealthActivityKind.STEPS) Int.MAX_VALUE.toLong() else 172_800_000L)
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val old = read(kind, day, day).firstOrNull()?.total
            // Checkpoint migrations and duplicate sensor callbacks cannot roll a completed total backwards.
            if (old == null || total > old) {
                val plain = ByteBuffer.allocate(8).putLong(total).array()
                val payload = try { AgentStorageCipher.encryptBinary(plain, aad(kind, day.toEpochDay())) } finally { plain.fill(0) }
                db.insertWithOnConflict("days", null, ContentValues().apply {
                    put("kind", kind.name); put("day", day.toEpochDay()); put("payload", payload)
                }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    fun read(kind: HealthActivityKind, first: LocalDate, last: LocalDate): List<HealthActivityDay> {
        require(!last.isBefore(first) && java.time.temporal.ChronoUnit.DAYS.between(first, last) < 732)
        return helper.readableDatabase.rawQuery("SELECT day,payload FROM days WHERE kind=? AND day>=? AND day<=? ORDER BY day",
            arrayOf(kind.name, first.toEpochDay().toString(), last.toEpochDay().toString())).use { cursor -> buildList {
                while (cursor.moveToNext()) {
                    val day = cursor.getLong(0)
                    val plain = AgentStorageCipher.decryptBinary(cursor.getBlob(1), aad(kind, day))
                    val total = try { check(plain.size == 8); ByteBuffer.wrap(plain).long.also { check(it >= 0) } } finally { plain.fill(0) }
                    add(HealthActivityDay(kind, LocalDate.ofEpochDay(day), total))
                }
            } }
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE days(kind TEXT NOT NULL,day INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(kind,day)) WITHOUT ROWID")
        }
        override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) = error("Unsupported activity history version")
    }
    companion object { const val DEFAULT_DB = "health_activity_history_v1.db" }
}
