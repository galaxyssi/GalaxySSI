package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import java.io.Closeable
import java.util.UUID
import java.util.concurrent.CancellationException
import org.json.JSONObject

/** Policies and access metadata are separate from health records and conversation storage. */
internal class HealthPrivacyStore(private val context: Context, private val name: String = DEFAULT_DB) : Closeable {
    private val helper = Database(context); private val db get() = helper.writableDatabase
    private fun aad(row: String) = "$name|health-privacy-v1|$row".toByteArray(Charsets.UTF_8)
    private fun pack(row: String, value: JSONObject, createKey: Boolean = false): ByteArray {
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        return try { HealthPrivacyCipher.encrypt(bytes, aad(row), createKey) } finally { bytes.fill(0) }
    }
    private fun unpack(row: String, payload: ByteArray): JSONObject {
        val bytes = HealthPrivacyCipher.decrypt(payload, aad(row))
        return try { JSONObject(String(bytes, Charsets.UTF_8)) } finally { bytes.fill(0) }
    }
    @Synchronized private fun <T> transaction(block: () -> T): T {
        val database = db; database.beginTransactionNonExclusive()
        return try { block().also { database.setTransactionSuccessful() } } finally { database.endTransaction() }
    }
    fun policy(): HealthPrivacyPolicy = db.rawQuery("SELECT payload FROM policy WHERE id=1", null).use {
        check(it.moveToFirst()) { "Health privacy policy missing" }
        HealthPrivacyPolicy.from(unpack("policy", it.getBlob(0)))
    }
    fun change(option: HealthPrivacyOption, enabled: Boolean, expected: String): HealthPrivacyPolicy {
        val next = transaction {
            val current = policy()
            if (current.version != expected) throw HealthPrivacyConflict()
            val candidate = current.change(option, enabled)
            if (candidate == current) current else candidate.copy(version = UUID.randomUUID().toString()).also { value ->
                check(db.update("policy", ContentValues().apply { put("payload", pack("policy", value.json())) }, "id=1", null) == 1)
            }
        }
        if (next.version != expected) context.contentResolver.notifyChange(changes(context, name), null)
        return next
    }
    private fun begin(scope: HealthAccessScope): HealthAccessEvent = transaction {
        val policy = policy()
        val allowed = scope.purpose.permission?.let(policy::enabled) != false
        val event = HealthAccessEvent(UUID.randomUUID().toString(), System.currentTimeMillis(), scope,
            if (allowed) HealthAccessOutcome.STARTED else HealthAccessOutcome.BLOCKED, policy.version)
        db.insertOrThrow("access_log", null, ContentValues().apply {
            put("id", event.id); put("time", event.time); put("payload", pack("event:${event.id}:${event.time}", event.json()))
        })
        event
    }
    private fun finish(event: HealthAccessEvent, outcome: HealthAccessOutcome): HealthAccessOutcome = transaction {
        val effective = if (outcome == HealthAccessOutcome.COMPLETE && event.scope.purpose.permission != null &&
            policy().version != event.policyVersion) HealthAccessOutcome.BLOCKED else outcome
        val updated = event.copy(outcome = effective)
        check(db.update("access_log", ContentValues().apply { put("payload", pack("event:${event.id}:${event.time}", updated.json())) }, "id=?", arrayOf(event.id)) == 1)
        effective
    }
    fun <T> track(scope: HealthAccessScope, operation: () -> T): T {
        val event = begin(scope)
        if (event.outcome == HealthAccessOutcome.BLOCKED) throw HealthAccessBlocked()
        val result = try { operation() } catch (failure: Exception) {
            val outcome = when (failure) {
                is HealthAccessBlocked -> HealthAccessOutcome.BLOCKED
                is CancellationException, is android.os.OperationCanceledException -> HealthAccessOutcome.CANCELLED
                else -> HealthAccessOutcome.FAILED
            }
            runCatching { finish(event, outcome) }.exceptionOrNull()?.let(failure::addSuppressed)
            throw failure
        }
        // Check the revision and record the outcome in one transaction, including off/on ABA.
        if (finish(event, HealthAccessOutcome.COMPLETE) == HealthAccessOutcome.BLOCKED) throw HealthAccessBlocked()
        return result
    }
    fun page(after: HealthAccessCursor? = null): HealthAccessPage {
        val where = if (after == null) "" else "WHERE time<? OR (time=? AND id<?)"
        val args = after?.let { arrayOf(it.time.toString(), it.time.toString(), it.id) }
        val rows = db.rawQuery("SELECT id,time,payload FROM access_log $where ORDER BY time DESC,id DESC LIMIT 31", args).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0); val time = cursor.getLong(1)
                    add(HealthAccessEvent.from(unpack("event:$id:$time", cursor.getBlob(2))).also { check(it.id == id && it.time == time) })
                }
            }
        }
        val visible = rows.take(30)
        return HealthAccessPage(visible, if (rows.size > 30) visible.last().let { HealthAccessCursor(it.time, it.id) } else null)
    }
    override fun close() = helper.close()
    private inner class Database(context: Context) : SQLiteOpenHelper(context, name, null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE policy(id INTEGER PRIMARY KEY CHECK(id=1),payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE access_log(id TEXT PRIMARY KEY,time INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX access_log_pages ON access_log(time DESC,id DESC)")
            db.insertOrThrow("policy", null, ContentValues().apply {
                put("id", 1); put("payload", pack("policy", HealthPrivacyPolicy(version = UUID.randomUUID().toString()).json(), true))
            })
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { error("Unsupported health privacy schema") }
    }
    companion object {
        const val DEFAULT_DB = "health_privacy_v1.db"
        fun changes(context: Context, name: String = DEFAULT_DB) = Uri.parse("content://${context.packageName}.health-originals/changes/privacy/" + Uri.encode(name))
        fun <T> track(context: Context, scope: HealthAccessScope, name: String = DEFAULT_DB, operation: () -> T): T =
            HealthPrivacyStore(context.applicationContext, name).use { it.track(scope, operation) }
    }
}
