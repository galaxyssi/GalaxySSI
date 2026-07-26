package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object SignalASILinkDeliveryStore {
    private const val PREFS = "signalasi_link_delivery_v1"
    private const val INBOUND_DATABASE = "signalasi_link_inbound_v1"
    private const val KEY_OUTBOX = "outbox"
    private const val KEY_INBOX = "inbox"
    private const val PENDING_INBOUND_PREFIX = "pending:"
    private const val MAX_INBOX_IDS = 4096
    private const val MAX_PENDING_INBOUND = 256
    private const val MAX_PENDING_INBOUND_AGE_MILLIS = 7L * 24L * 60L * 60L * 1_000L

    enum class IncomingStageResult { STAGED, PENDING, COMPLETED, INVALID }

    data class PendingMessage(
        val messageId: String,
        val topic: String,
        val wirePayload: String,
        val attempts: Int,
        val createdAt: Long
    )

    data class PendingIncoming(
        val messageId: String,
        val payload: String,
        val createdAt: Long
    )

    @Synchronized
    fun enqueue(context: Context, messageId: String, topic: String, wirePayload: String) {
        val values = outboxArray(context)
        for (index in 0 until values.length()) {
            if (values.optJSONObject(index)?.optString("message_id") == messageId) return
        }
        values.put(
            JSONObject()
                .put("message_id", messageId)
                .put("topic", topic)
                .put("wire_payload", wirePayload)
                .put("status", "queued")
                .put("attempts", 0)
                .put("next_attempt_at", System.currentTimeMillis())
                .put("created_at", System.currentTimeMillis())
                .put("updated_at", System.currentTimeMillis())
        )
        writeArray(context, KEY_OUTBOX, values)
    }

    @Synchronized
    fun markPublished(context: Context, messageId: String) {
        updateOutbox(context, messageId) { item ->
            item.put("status", "published")
                .put("next_attempt_at", System.currentTimeMillis() + 30_000L)
                .put("updated_at", System.currentTimeMillis())
        }
    }

    @Synchronized
    fun markAttempt(context: Context, messageId: String) {
        updateOutbox(context, messageId) { item ->
            val attempts = item.optInt("attempts") + 1
            val delayMs = SignalASILinkRetryPolicy.delayMillis(attempts)
            item.put("status", "publishing")
                .put("attempts", attempts)
                .put("next_attempt_at", System.currentTimeMillis() + delayMs)
                .put("updated_at", System.currentTimeMillis())
        }
    }

    @Synchronized
    fun acknowledge(context: Context, messageId: String) {
        if (messageId.isBlank()) return
        val source = outboxArray(context)
        val kept = JSONArray()
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            if (item.optString("message_id") != messageId) kept.put(item)
        }
        writeArray(context, KEY_OUTBOX, kept)
    }

    @Synchronized
    fun discardRoutes(context: Context, routes: SignalASILinkProtocol.Routes): Int {
        val source = outboxArray(context)
        val discardedTopics = setOf(routes.up, routes.down, routes.control, routes.pairing)
        val kept = retainMessagesOutsideTopics(source, discardedTopics)
        val removed = source.length() - kept.length()
        if (removed > 0) writeArray(context, KEY_OUTBOX, kept)
        return removed
    }

    @Synchronized
    fun pending(context: Context): List<PendingMessage> =
        pendingFromArray(outboxArray(context), System.currentTimeMillis())

    @Synchronized
    fun makePendingImmediatelyRetryable(context: Context) {
        val values = outboxArray(context)
        val now = System.currentTimeMillis()
        var changed = false
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            if (item.optLong("next_attempt_at") > now) {
                item.put("status", "queued")
                    .put("next_attempt_at", now)
                    .put("updated_at", now)
                changed = true
            }
        }
        if (changed) writeArray(context, KEY_OUTBOX, values)
    }

    internal fun pendingFromArray(values: JSONArray, nowMillis: Long): List<PendingMessage> =
        buildList {
            for (index in 0 until values.length()) {
                val item = values.optJSONObject(index) ?: continue
                if (item.optLong("next_attempt_at") > nowMillis) continue
                add(
                    PendingMessage(
                        item.optString("message_id"),
                        item.optString("topic"),
                        item.optString("wire_payload"),
                        item.optInt("attempts"),
                        item.optLong("created_at")
                    )
                )
            }
        }

    @Synchronized
    fun claimIncoming(context: Context, messageId: String): Boolean {
        if (messageId.isBlank()) return false
        val values = readArray(context, KEY_INBOX)
        for (index in 0 until values.length()) {
            if (values.optString(index) == messageId) return false
        }
        values.put(messageId)
        val trimmed = JSONArray()
        val start = (values.length() - MAX_INBOX_IDS).coerceAtLeast(0)
        for (index in start until values.length()) trimmed.put(values.optString(index))
        writeArray(context, KEY_INBOX, trimmed)
        return true
    }

    @Synchronized
    fun stageIncoming(context: Context, messageId: String, payload: String): IncomingStageResult {
        if (messageId.isBlank() || payload.isBlank()) return IncomingStageResult.INVALID
        val completed = readArray(context, KEY_INBOX)
        for (index in 0 until completed.length()) {
            if (completed.optString(index) == messageId) return IncomingStageResult.COMPLETED
        }
        val database = inboundDatabase(context)
        val key = pendingInboundKey(messageId)
        if (database.contains(key)) return IncomingStageResult.PENDING
        val now = System.currentTimeMillis()
        database.writeString(
            key,
            JSONObject()
                .put("message_id", messageId)
                .put("payload", payload)
                .put("created_at", now)
                .toString()
        )
        prunePendingIncoming(database, now)
        return IncomingStageResult.STAGED
    }

    @Synchronized
    fun pendingIncoming(context: Context): List<PendingIncoming> {
        val database = inboundDatabase(context)
        val now = System.currentTimeMillis()
        prunePendingIncoming(database, now)
        return database.keys(PENDING_INBOUND_PREFIX)
            .mapNotNull { key ->
                val value = runCatching {
                    JSONObject(database.readString(key, ""))
                }.getOrNull() ?: return@mapNotNull null
                val messageId = value.optString("message_id")
                val payload = value.optString("payload")
                if (messageId.isBlank() || payload.isBlank()) return@mapNotNull null
                PendingIncoming(
                    messageId = messageId,
                    payload = payload,
                    createdAt = value.optLong("created_at", now)
                )
            }
            .sortedBy(PendingIncoming::createdAt)
    }

    @Synchronized
    fun completeIncoming(context: Context, messageId: String) {
        if (messageId.isBlank()) return
        inboundDatabase(context).remove(pendingInboundKey(messageId))
        val values = readArray(context, KEY_INBOX)
        for (index in 0 until values.length()) {
            if (values.optString(index) == messageId) return
        }
        values.put(messageId)
        val trimmed = JSONArray()
        val start = (values.length() - MAX_INBOX_IDS).coerceAtLeast(0)
        for (index in start until values.length()) trimmed.put(values.optString(index))
        writeArray(context, KEY_INBOX, trimmed)
    }

    @Synchronized
    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        inboundDatabase(context).clear()
    }

    private fun updateOutbox(context: Context, messageId: String, block: (JSONObject) -> Unit) {
        val values = outboxArray(context)
        for (index in 0 until values.length()) {
            val item = values.optJSONObject(index) ?: continue
            if (item.optString("message_id") == messageId) block(item)
        }
        writeArray(context, KEY_OUTBOX, values)
    }

    private fun outboxArray(context: Context): JSONArray = readArray(context, KEY_OUTBOX)

    private fun inboundDatabase(context: Context): AgentEncryptedDatabase =
        AgentEncryptedDatabase(context.applicationContext, INBOUND_DATABASE)

    private fun pendingInboundKey(messageId: String): String = "$PENDING_INBOUND_PREFIX$messageId"

    private fun prunePendingIncoming(database: AgentEncryptedDatabase, nowMillis: Long) {
        val pending = database.keys(PENDING_INBOUND_PREFIX)
            .mapNotNull { key ->
                val value = runCatching {
                    JSONObject(database.readString(key, ""))
                }.getOrNull()
                if (value == null) {
                    database.remove(key)
                    null
                } else {
                    key to value.optLong("created_at", nowMillis)
                }
            }
            .sortedBy { it.second }
        val cutoff = nowMillis - MAX_PENDING_INBOUND_AGE_MILLIS
        val overflow = (pending.size - MAX_PENDING_INBOUND).coerceAtLeast(0)
        pending.forEachIndexed { index, (key, createdAt) ->
            if (index < overflow || createdAt < cutoff) database.remove(key)
        }
    }

    private fun readArray(context: Context, key: String): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, "[]") ?: "[]"
        return runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
    }

    private fun writeArray(context: Context, key: String, value: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(key, value.toString()).commit()
    }

    internal fun retainMessagesOutsideTopics(source: JSONArray, discardedTopics: Set<String>): JSONArray {
        if (discardedTopics.isEmpty()) return JSONArray(source.toString())
        val kept = JSONArray()
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            if (item.optString("topic") !in discardedTopics) kept.put(JSONObject(item.toString()))
        }
        return kept
    }
}

internal object SignalASILinkRetryPolicy {
    private const val INITIAL_DELAY_MILLIS = 2_000L
    private const val MAX_DELAY_MILLIS = 300_000L

    fun delayMillis(attempt: Int): Long {
        val exponent = (attempt.coerceAtLeast(1) - 1).coerceAtMost(8)
        return (INITIAL_DELAY_MILLIS shl exponent).coerceAtMost(MAX_DELAY_MILLIS)
    }
}
