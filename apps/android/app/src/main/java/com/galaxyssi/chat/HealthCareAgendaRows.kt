package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import java.util.UUID

/** Rebuildable metadata only; descriptions and outcomes remain in authenticated encrypted concerns. */
internal class HealthCareAgendaRows(private val db: SQLiteDatabase,
    private val concern: (String) -> HealthCareConcern?, private val reminders: (String) -> List<HealthCareReminder>) {
    private fun changed() {
        db.execSQL("UPDATE action_agenda_state SET generation=? WHERE id=1", arrayOf(UUID.randomUUID().toString()))
    }
    fun remove(id: String) {
        if (db.delete("action_agenda", "concern_id=?", arrayOf(id)) > 0) changed()
    }
    fun replace(issue: HealthCareConcern) {
        db.delete("action_agenda", "concern_id=?", arrayOf(issue.id))
        val notices = reminders(issue.id).associateBy { it.actionId }
        issue.actions.forEach { action ->
            val item = HealthCareAgenda.item(issue, action, notices[action.id])
            db.insertOrThrow("action_agenda", null, ContentValues().apply {
                put("concern_id", issue.id); put("action_id", action.id); put("revision", issue.revision)
                put("bucket", item.bucket); put("due", item.due)
            })
        }
        changed()
    }
    fun prepareBatch(limit: Int = 30): Boolean {
        require(limit in 1..30)
        val after = db.rawQuery("SELECT after_id,ready FROM action_agenda_state WHERE id=1", null).use {
            check(it.moveToFirst())
            if (it.getInt(1) == 1) return true
            it.getString(0)
        }
        val ids = db.rawQuery("SELECT id FROM concerns WHERE id>? ORDER BY id LIMIT $limit", arrayOf(after)).use {
            buildList { while (it.moveToNext()) add(it.getString(0)) }
        }
        ids.forEach { replace(concern(it) ?: throw HealthCareConflict()) }
        val ready = ids.size < limit
        db.execSQL("UPDATE action_agenda_state SET after_id=?,ready=? WHERE id=1", arrayOf(ids.lastOrNull() ?: after, if (ready) 1 else 0))
        return ready
    }
    fun page(filter: HealthCareAgendaFilter, dayEnd: Long, after: HealthCareAgendaCursor?, limit: Int): HealthCareAgendaPage {
        require(limit in 1..30)
        val generation = db.rawQuery("SELECT generation,ready FROM action_agenda_state WHERE id=1", null).use {
            check(it.moveToFirst() && it.getInt(1) == 1) { "Action index is not ready" }; it.getString(0)
        }
        if (after != null && (after.generation != generation || after.dayEnd != dayEnd || after.filter != filter)) throw HealthCareConflict()
        val args = arrayListOf<String>()
        val where = when (filter) {
            HealthCareAgendaFilter.TODAY -> { args += dayEnd.toString(); "bucket=0 AND due<?" }
            HealthCareAgendaFilter.LATER -> { args += dayEnd.toString(); "bucket=0 AND due>=?" }
            HealthCareAgendaFilter.REVIEW -> "bucket=1"
            HealthCareAgendaFilter.RECORDED -> "bucket=2"
        } + if (after == null) "" else {
            args += listOf(after.due.toString(), after.due.toString(), after.concernId, after.concernId, after.actionId)
            " AND (due>? OR (due=? AND (concern_id>? OR (concern_id=? AND action_id>?))))"
        }
        val issues = mutableMapOf<String, HealthCareConcern>()
        val notices = mutableMapOf<String, Map<String, HealthCareReminder>>()
        val items = db.rawQuery("SELECT concern_id,action_id,revision,bucket,due FROM action_agenda WHERE $where " +
            "ORDER BY due,concern_id,action_id LIMIT ${limit + 1}", args.toTypedArray()).use { rows -> buildList {
            while (rows.moveToNext()) {
                val id = rows.getString(0)
                val issue = issues.getOrPut(id) { concern(id) ?: throw HealthCareConflict() }
                val action = issue.actions.firstOrNull { it.id == rows.getString(1) } ?: throw HealthCareConflict()
                val reminder = notices.getOrPut(id) { reminders(id).associateBy { it.actionId } }[action.id]
                val item = HealthCareAgenda.item(issue, action, reminder)
                check(issue.revision == rows.getInt(2) && item.bucket == rows.getInt(3) && item.due == rows.getLong(4))
                add(item)
            }
        } }
        val visible = items.take(limit)
        return HealthCareAgendaPage(visible, if (items.size > limit) visible.last().let {
            HealthCareAgendaCursor(generation, filter, dayEnd, it.due, it.concern.id, it.action.id)
        } else null)
    }
    companion object {
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE action_agenda(concern_id TEXT NOT NULL,action_id TEXT NOT NULL,revision INTEGER NOT NULL," +
                "bucket INTEGER NOT NULL,due INTEGER NOT NULL,PRIMARY KEY(concern_id,action_id))")
            db.execSQL("CREATE INDEX care_action_pages ON action_agenda(bucket,due,concern_id,action_id)")
            db.execSQL("CREATE TABLE action_agenda_state(id INTEGER PRIMARY KEY,after_id TEXT NOT NULL,ready INTEGER NOT NULL,generation TEXT NOT NULL)")
            db.execSQL("INSERT INTO action_agenda_state VALUES(1,'',0,?)", arrayOf(UUID.randomUUID().toString()))
        }
    }
}
