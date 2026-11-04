package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import java.io.Closeable
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.json.JSONObject

internal class HealthReminderConflict : IllegalStateException("Health reminder changed")
internal data class HealthReminderPage(val rows: List<HealthReminderOccurrence>, val next: LocalDate?)

internal class HealthReminderStore(private val context: Context, private val name: String = DEFAULT_DB) : Closeable {
    private val helper = Database(context)
    private val db get() = helper.writableDatabase
    private fun aad(row: String) = "$name|health-reminders-v1|$row".toByteArray(Charsets.UTF_8)
    private fun pack(row: String, json: JSONObject): ByteArray {
        val plain = json.toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(plain, aad(row)) } finally { plain.fill(0) }
    }
    private fun unpack(row: String, payload: ByteArray): JSONObject {
        val plain = AgentStorageCipher.decryptBinary(payload, aad(row))
        return try { JSONObject(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
    }
    private fun <T> transaction(block: () -> T): T {
        val database = db
        database.beginTransactionNonExclusive()
        return try { block().also { database.setTransactionSuccessful() } } finally { database.endTransaction() }
    }
    fun settings(): HealthReminderSettings = db.rawQuery("SELECT payload FROM settings WHERE id=1", null).use {
        check(it.moveToFirst()); HealthReminderSettings.from(unpack("settings", it.getBlob(0)))
    }
    private fun writeSettings(settings: HealthReminderSettings) {
        check(db.update("settings", ContentValues().apply { put("payload", pack("settings", settings.json())) }, "id=1", null) == 1)
    }
    private fun changed() = context.contentResolver.notifyChange(changes(context, name), null)

    fun save(candidate: HealthReminderSettings, now: Long): HealthReminderSettings = transaction {
        val current = settings()
        if (current.revision != candidate.revision) throw HealthReminderConflict()
        val planChanged = current.enabled != candidate.enabled || current.minute != candidate.minute || current.target != candidate.target
        val saved = candidate.copy(effectiveAt = if (planChanged) now else current.effectiveAt, revision = UUID.randomUUID().toString())
        writeSettings(saved)
        if (current.enabled && !saved.enabled) disableOutstanding(now)
        saved
    }.also { changed() }

    private fun read(cursor: Cursor): HealthReminderOccurrence {
        val day = cursor.getString(0)
        val event = HealthReminderOccurrence.from(unpack("day:$day", cursor.getBlob(1)))
        check(event.day.toString() == day)
        return event
    }
    fun occurrence(day: LocalDate): HealthReminderOccurrence? =
        db.rawQuery("SELECT day,payload FROM reminders WHERE day=?", arrayOf(day.toString())).use { if (it.moveToFirst()) read(it) else null }

    private fun values(event: HealthReminderOccurrence) = ContentValues().apply {
        put("day", event.day.toString()); put("state", event.state.ordinal); put("delivery", event.delivery.ordinal)
        put("due", event.dueAt); put("resume", event.resumeAt); put("payload", pack("day:${event.day}", event.json()))
    }
    private fun update(event: HealthReminderOccurrence) {
        check(db.update("reminders", values(event), "day=?", arrayOf(event.day.toString())) == 1)
    }
    private fun rows(where: String, args: Array<String>, limit: Int): List<HealthReminderOccurrence> =
        db.rawQuery("SELECT day,payload FROM reminders WHERE $where ORDER BY day DESC LIMIT $limit", args).use { cursor ->
            buildList { while (cursor.moveToNext()) add(read(cursor)) }
        }
    private fun disableOutstanding(now: Long) {
        val where = "state IN (${HealthReminderState.PENDING.ordinal},${HealthReminderState.SNOOZED.ordinal})"
        while (true) {
            val page = rows(where, emptyArray(), 30)
            page.forEach { update(it.copy(state = HealthReminderState.DISABLED, handledAt = now, resumeAt = 0, revision = UUID.randomUUID().toString())) }
            if (page.size < 30) break
        }
    }
    fun reconcile(now: Long, zone: ZoneId) {
        val changed = transaction {
            var dirty = false
            val due = HealthReminderPolicy.due(settings(), now, zone)
            if (due != null && occurrence(due.day) == null) {
                db.insertOrThrow("reminders", null, values(due)); dirty = true
            }
            val where = "state=${HealthReminderState.SNOOZED.ordinal} AND resume<=?"
            while (true) {
                val page = rows(where, arrayOf(now.toString()), 30)
                page.forEach { update(it.copy(state = HealthReminderState.PENDING, revision = UUID.randomUUID().toString())) }
                dirty = dirty || page.isNotEmpty()
                if (page.size < 30) break
            }
            dirty
        }
        if (changed) changed()
    }
    fun act(day: LocalDate, expected: String, action: HealthReminderAction, now: Long) = transaction {
        val event = occurrence(day) ?: throw HealthReminderConflict()
        if (event.revision != expected || event.state !in listOf(HealthReminderState.PENDING, HealthReminderState.SNOOZED)) throw HealthReminderConflict()
        val revision = UUID.randomUUID().toString()
        when (action) {
            HealthReminderAction.COMPLETE -> update(event.copy(state = HealthReminderState.COMPLETE, handledAt = now, resumeAt = 0, revision = revision))
            HealthReminderAction.SNOOZE -> update(event.copy(state = HealthReminderState.SNOOZED, resumeAt = now + HealthReminderPolicy.HOUR,
                delivery = HealthReminderDelivery.WAITING, revision = revision))
            HealthReminderAction.DISABLE -> {
                writeSettings(settings().copy(enabled = false, revision = revision))
                disableOutstanding(now)
            }
        }
    }.also { changed() }

    fun pendingDelivery(now: Long): List<HealthReminderOccurrence> =
        (now - HealthReminderPolicy.DAY).toString().let { cutoff ->
            rows("state=${HealthReminderState.PENDING.ordinal} AND delivery=${HealthReminderDelivery.WAITING.ordinal} AND (due>? OR resume>?)",
                arrayOf(cutoff, cutoff), 30)
        }
    fun delivered(event: HealthReminderOccurrence, outcome: HealthReminderDelivery) {
        val changed = transaction {
            val current = occurrence(event.day)
            if (current?.revision != event.revision || current.state != HealthReminderState.PENDING || current.delivery != HealthReminderDelivery.WAITING) false
            else { update(current.copy(delivery = outcome)); true }
        }
        if (changed) changed()
    }
    fun nextSnooze(): Long? = db.rawQuery("SELECT MIN(resume) FROM reminders WHERE state=${HealthReminderState.SNOOZED.ordinal}", null).use {
        if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
    }
    fun page(filter: HealthReminderFilter, after: LocalDate?): HealthReminderPage {
        val open = "state IN (${HealthReminderState.PENDING.ordinal},${HealthReminderState.SNOOZED.ordinal})"
        val filterSql = when (filter) { HealthReminderFilter.PENDING -> open; HealthReminderFilter.HANDLED -> "NOT ($open)"; HealthReminderFilter.ALL -> "1" }
        val found = rows(if (after == null) filterSql else "($filterSql) AND day<?", after?.let { arrayOf(it.toString()) } ?: emptyArray(), 31)
        val visible = found.take(30)
        return HealthReminderPage(visible, if (found.size > 30) visible.last().day else null)
    }
    override fun close() = helper.close()
    private inner class Database(context: Context) : SQLiteOpenHelper(context, name, null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE settings(id INTEGER PRIMARY KEY CHECK(id=1),payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE reminders(day TEXT PRIMARY KEY,state INTEGER NOT NULL,delivery INTEGER NOT NULL,due INTEGER NOT NULL,resume INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX reminder_snooze ON reminders(state,resume)")
            db.execSQL("CREATE INDEX reminder_delivery ON reminders(state,delivery,due)")
            db.insertOrThrow("settings", null, ContentValues().apply {
                put("id", 1); put("payload", pack("settings", HealthReminderSettings(revision = UUID.randomUUID().toString()).json()))
            })
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { error("Unsupported health reminder schema") }
    }
    companion object {
        const val DEFAULT_DB = "health_reminders_v1.db"
        fun changes(context: Context, name: String) = Uri.parse("content://${context.packageName}.health-originals/changes/reminder/${Uri.encode(name)}")
    }
}
