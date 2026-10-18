package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

/** Per-reminder encrypted rows also serve as replay tombstones after process death. */
internal class ContactReminderStore(context: Context, name: String = "contact-reminders.db") :
    SQLiteOpenHelper(context.applicationContext, name, null, 1) {
    private val cipher = AgentRowStorageCipher(context.applicationContext, "contact-reminders:$name")
    init { setWriteAheadLoggingEnabled(true) }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE reminders (id TEXT PRIMARY KEY, expires INTEGER NOT NULL, active INTEGER NOT NULL, payload TEXT NOT NULL)")
        db.execSQL("CREATE INDEX reminders_expiry ON reminders(expires)")
        db.execSQL("CREATE INDEX reminders_active ON reminders(active, expires)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun get(id: String): ContactReminder? = readableDatabase.query(
        "reminders", arrayOf("payload"), "id=?", arrayOf(id), null, null, null
    ).use { cursor ->
        if (!cursor.moveToFirst()) return@use null
        val json = JSONObject(cipher.decrypt(cursor.getString(0), id.toByteArray(Charsets.UTF_8))
            ?: error("Reminder row could not be decrypted"))
        ContactReminder(id, json.getString("contact"), json.getBoolean("outgoing"),
            json.getLong("created"), json.getLong("expires"), json.getString("status"), json.optLong("history"))
    }

    fun put(value: ContactReminder) {
        val json = JSONObject().put("contact", value.contactId).put("outgoing", value.outgoing)
            .put("created", value.createdAt).put("expires", value.expiresAt)
            .put("status", value.status).put("history", value.historyId)
        val values = ContentValues().apply {
            put("id", value.id); put("expires", value.expiresAt)
            put("active", if (value.terminal) 0 else 1)
            put("payload", cipher.encrypt(json.toString(), value.id.toByteArray(Charsets.UTF_8)))
        }
        check(writableDatabase.insertWithOnConflict("reminders", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }

    fun prune(now: Long) {
        // An expired request is rejected before lookup; retain tombstones for a full day as well.
        writableDatabase.delete("reminders", "expires<?", arrayOf((now - 86_400_000L).toString()))
    }

    fun activeIds(): List<String> = readableDatabase.query("reminders", arrayOf("id"),
        "active=1", null, null, null, "expires").use { cursor ->
        buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
    }
}
