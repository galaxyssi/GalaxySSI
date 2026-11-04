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
internal data class HealthSleepCursor(val time: Long, val id: String)
internal data class HealthSleepPage(val rows: List<HealthSleepAlert>, val next: HealthSleepCursor?)

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
        if (current.sleepChanges && !saved.sleepChanges) disableSleep(now)
        if (!saved.reportReviews || !saved.notifications) db.update("report_notifications", ContentValues().apply {
            put("delivery", HealthReminderDelivery.IN_APP_ONLY.ordinal)
        }, "delivery=?", arrayOf(HealthReminderDelivery.WAITING.ordinal.toString()))
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

    private fun readSleep(cursor: Cursor): HealthSleepAlert {
        val id = cursor.getString(0)
        return HealthSleepAlert.from(unpack("sleep:$id", cursor.getBlob(4))).also {
            check(it.id == id && it.openedAt == cursor.getLong(1) && it.state.ordinal == cursor.getInt(2) && it.endedAt == cursor.getLong(3))
        }
    }
    private fun sleepRows(where: String, args: Array<String>, limit: Int): List<HealthSleepAlert> =
        db.rawQuery("SELECT id,opened,state,ended,payload FROM sleep_alerts WHERE $where ORDER BY opened DESC,id DESC LIMIT $limit", args).use {
            buildList { while (it.moveToNext()) add(readSleep(it)) }
        }
    fun sleepAlert(id: String): HealthSleepAlert? = sleepRows("id=?", arrayOf(id), 1).singleOrNull()
    fun activeSleep(): HealthSleepAlert? = sleepRows("ended=0", emptyArray(), 1).singleOrNull()
    fun hasSleepHistory(): Boolean = db.rawQuery("SELECT 1 FROM sleep_alerts LIMIT 1", null).use { it.moveToFirst() }
    fun sleepPage(filter: HealthReminderFilter, after: HealthSleepCursor?): HealthSleepPage {
        val open = "state IN (${HealthReminderState.PENDING.ordinal},${HealthReminderState.SNOOZED.ordinal})"
        val condition = when (filter) {
            HealthReminderFilter.PENDING -> open
            HealthReminderFilter.HANDLED -> "NOT ($open)"
            HealthReminderFilter.ALL -> "1"
        }
        val rows = if (after == null) sleepRows(condition, emptyArray(), 31) else sleepRows(
            "($condition) AND (opened<? OR (opened=? AND id<?))", arrayOf(after.time.toString(), after.time.toString(), after.id), 31)
        val visible = rows.take(30)
        return HealthSleepPage(visible, if (rows.size > 30) visible.last().let { HealthSleepCursor(it.openedAt, it.id) } else null)
    }
    private fun writeSleep(alert: HealthSleepAlert) {
        val values = ContentValues().apply {
            put("id", alert.id); put("opened", alert.openedAt); put("state", alert.state.ordinal); put("ended", alert.endedAt)
            put("payload", pack("sleep:${alert.id}", alert.json()))
        }
        if (db.update("sleep_alerts", values, "id=?", arrayOf(alert.id)) == 0) db.insertOrThrow("sleep_alerts", null, values)
    }
    private fun disableSleep(now: Long) {
        activeSleep()?.let { alert -> writeSleep(alert.copy(endedAt = now, resumeAt = 0, revision = UUID.randomUUID().toString(),
            handledAt = if (alert.handledAt != 0L) alert.handledAt else now,
            state = if (alert.state == HealthReminderState.COMPLETE) alert.state else HealthReminderState.DISABLED)) }
        db.delete("sleep_eval", "id=1", null)
    }
    fun sleepEvaluated(key: String): Boolean = db.rawQuery("SELECT 1 FROM sleep_eval WHERE id=1 AND key=?", arrayOf(key)).use { it.moveToFirst() }
    fun applySleep(expected: String, key: String?, evidence: HealthSleepAlertEvidence?, now: Long) {
        val dirty = transaction {
            val settings = settings()
            if (settings.revision != expected) throw HealthReminderConflict()
            if (!settings.sleepChanges && evidence != null) throw HealthReminderConflict()
            val active = activeSleep()
            val latest = db.rawQuery("SELECT MAX(opened) FROM sleep_alerts", null).use {
                if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
            }
            val updates = HealthSleepAlertPolicy.changes(active, latest, evidence, now, settings.mergeSleepChanges)
            updates.forEach(::writeSleep)
            if (key == null) db.delete("sleep_eval", "id=1", null) else db.insertWithOnConflict("sleep_eval", null, ContentValues().apply {
                put("id", 1); put("key", key)
            }, SQLiteDatabase.CONFLICT_REPLACE)
            updates.isNotEmpty()
        }
        if (dirty) changed()
    }
    fun resumeSleep(now: Long) {
        val dirty = transaction {
            val alert = activeSleep()
            if (alert?.state != HealthReminderState.SNOOZED || alert.resumeAt > now) false
            else {
                writeSleep(alert.copy(state = HealthReminderState.PENDING, revision = UUID.randomUUID().toString()))
                true
            }
        }
        if (dirty) changed()
    }
    fun actSleep(expected: HealthSleepAlert, action: HealthReminderAction, now: Long) = transaction {
        val current = sleepAlert(expected.id)
        if (current?.revision != expected.revision || !current.actionable) throw HealthReminderConflict()
        val revision = UUID.randomUUID().toString()
        when (action) {
            HealthReminderAction.COMPLETE -> writeSleep(current.copy(state = HealthReminderState.COMPLETE, resumeAt = 0, revision = revision, handledAt = now))
            HealthReminderAction.SNOOZE -> writeSleep(current.copy(state = HealthReminderState.SNOOZED,
                resumeAt = now + HealthReminderPolicy.HOUR, delivery = HealthReminderDelivery.WAITING, revision = revision))
            HealthReminderAction.DISABLE -> {
                writeSettings(settings().copy(sleepChanges = false, revision = revision))
                disableSleep(now)
            }
        }
    }.also { changed() }
    fun sleepDelivered(expected: HealthSleepAlert, outcome: HealthReminderDelivery) {
        val dirty = transaction {
            val current = sleepAlert(expected.id)
            if (current?.revision != expected.revision || current.state != HealthReminderState.PENDING ||
                !current.open || current.delivery != HealthReminderDelivery.WAITING) false
            else { writeSleep(current.copy(delivery = outcome)); true }
        }
        if (dirty) changed()
    }
    fun reportDisposition(id: String): HealthReportReviewDisposition = db.rawQuery(
        "SELECT payload FROM report_reviews WHERE id=?", arrayOf(id)
    ).use {
        if (it.moveToFirst()) unpack("report:$id", it.getBlob(0)).let { value ->
            HealthReportReviewDisposition(value.getLong("resume"), value.getLong("handled"))
        } else HealthReportReviewDisposition()
    }

    fun actReport(id: String, expected: HealthReportReviewDisposition, action: HealthReminderAction, now: Long) {
        require(HealthProfilePolicy.uuid(id) && action != HealthReminderAction.DISABLE)
        transaction {
            val settings = settings()
            if (!settings.reportReviews || reportDisposition(id) != expected || expected.handledAt != 0L) throw HealthReminderConflict()
            val resume = if (action == HealthReminderAction.SNOOZE) now + HealthReminderPolicy.HOUR else 0L
            val payload = JSONObject().put("resume", resume)
                .put("handled", if (action == HealthReminderAction.COMPLETE) now else 0L)
            db.insertWithOnConflict("report_reviews", null, ContentValues().apply {
                put("id", id); put("payload", pack("report:$id", payload))
            }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
            if (resume > 0L) putReportNotice(id, resume, settings.notifications, replace = true)
            else db.update("report_notifications", ContentValues().apply {
                put("delivery", HealthReminderDelivery.IN_APP_ONLY.ordinal)
            }, "id=? AND delivery=?", arrayOf(id, HealthReminderDelivery.WAITING.ordinal.toString()))
        }
        changed()
    }

    fun admitReportNotice(id: String, now: Long): Boolean = transaction {
        require(HealthProfilePolicy.uuid(id) && now > 0L)
        val settings = settings()
        val disposition = reportDisposition(id)
        if (disposition.handledAt > 0) return@transaction false
        putReportNotice(id, maxOf(now, disposition.resumeAt), settings.reportReviews && settings.notifications, replace = false)
        reportNotice(id)?.delivery == HealthReminderDelivery.WAITING
    }

    private fun putReportNotice(id: String, due: Long, enabled: Boolean, replace: Boolean) {
        val delivery = if (enabled) HealthReminderDelivery.WAITING else HealthReminderDelivery.IN_APP_ONLY
        val values = ContentValues().apply { put("id", id); put("due", due); put("delivery", delivery.ordinal) }
        val mode = if (replace) SQLiteDatabase.CONFLICT_REPLACE else SQLiteDatabase.CONFLICT_IGNORE
        val row = db.insertWithOnConflict("report_notifications", null, values, mode)
        if (replace) check(row != -1L)
    }

    fun reportNotice(id: String): HealthReportNotice? = db.rawQuery(
        "SELECT id,due,delivery FROM report_notifications WHERE id=?", arrayOf(id)
    ).use { if (it.moveToFirst()) HealthReportNotice(it.getString(0), it.getLong(1), HealthReminderDelivery.entries[it.getInt(2)]) else null }

    fun dueReportNotices(now: Long): List<HealthReportNotice> = db.rawQuery(
        "SELECT id,due FROM report_notifications WHERE delivery=? AND due<=? ORDER BY due,id LIMIT 30",
        arrayOf(HealthReminderDelivery.WAITING.ordinal.toString(), now.toString())
    ).use { rows -> buildList {
        while (rows.moveToNext()) add(HealthReportNotice(rows.getString(0), rows.getLong(1), HealthReminderDelivery.WAITING))
    } }

    fun nextReportNotice(): Long? = db.rawQuery("SELECT MIN(due) FROM report_notifications WHERE delivery=?",
        arrayOf(HealthReminderDelivery.WAITING.ordinal.toString())).use {
        if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
    }

    fun finishReportNotice(notice: HealthReportNotice, delivery: HealthReminderDelivery): Boolean {
        require(delivery != HealthReminderDelivery.WAITING)
        val changed = db.update("report_notifications", ContentValues().apply { put("delivery", delivery.ordinal) },
            "id=? AND due=? AND delivery=?", arrayOf(notice.id, notice.dueAt.toString(), HealthReminderDelivery.WAITING.ordinal.toString())) == 1
        if (changed) changed()
        return changed
    }

    override fun close() = helper.close()
    private inner class Database(context: Context) : SQLiteOpenHelper(context, name, null, 4) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE settings(id INTEGER PRIMARY KEY CHECK(id=1),payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE reminders(day TEXT PRIMARY KEY,state INTEGER NOT NULL,delivery INTEGER NOT NULL,due INTEGER NOT NULL,resume INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX reminder_snooze ON reminders(state,resume)")
            db.execSQL("CREATE INDEX reminder_delivery ON reminders(state,delivery,due)")
            db.insertOrThrow("settings", null, ContentValues().apply {
                put("id", 1); put("payload", pack("settings", HealthReminderSettings(revision = UUID.randomUUID().toString()).json()))
            })
            addSleepTables(db)
            addReportTable(db)
            addReportNotifications(db)
        }
        private fun addSleepTables(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE sleep_alerts(id TEXT PRIMARY KEY,opened INTEGER NOT NULL,state INTEGER NOT NULL,ended INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE UNIQUE INDEX sleep_active ON sleep_alerts(ended) WHERE ended=0")
            db.execSQL("CREATE INDEX sleep_alert_pages ON sleep_alerts(opened DESC,id DESC)")
            db.execSQL("CREATE TABLE sleep_eval(id INTEGER PRIMARY KEY CHECK(id=1),key TEXT NOT NULL)")
        }
        private fun addReportTable(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE report_reviews(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        }
        private fun addReportNotifications(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE report_notifications(id TEXT PRIMARY KEY,due INTEGER NOT NULL,delivery INTEGER NOT NULL)")
            db.execSQL("CREATE INDEX report_notifications_due ON report_notifications(delivery,due,id)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            check(oldVersion in 1..3 && newVersion == 4)
            if (oldVersion == 1) addSleepTables(db)
            if (oldVersion < 3) addReportTable(db)
            addReportNotifications(db)
        }
    }
    companion object {
        const val DEFAULT_DB = "health_reminders_v1.db"
        fun changes(context: Context, name: String) = Uri.parse("content://${context.packageName}.health-originals/changes/reminder/${Uri.encode(name)}")
    }
}
