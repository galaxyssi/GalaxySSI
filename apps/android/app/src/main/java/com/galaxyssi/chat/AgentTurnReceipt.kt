package com.galaxyssi.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject

/** Only observations about this turn. Never store message text, endpoint names or tool arguments. */
internal object AgentTurnReceipt {
    private val io = Executors.newSingleThreadExecutor { r -> Thread(r, "turn-receipts").apply { isDaemon = true } }
    private val sequence = AtomicLong()
    private data class Key(val chat: String, val turn: String)
    private data class Live(val start: Long, var painted: Boolean = false)
    private val live = LinkedHashMap<Key, Live>()
    private val identifier = Regex("[A-Za-z0-9][A-Za-z0-9_./:+@-]{0,119}")
    private fun id(value: Any?) = (value as? String)?.takeIf(identifier::matches).orEmpty()
    private fun prefix(chat: String) = AgentNativeJsonCodec.sha256(chat) + ":"
    private fun database(c: Context) = AgentEncryptedDatabase(c, "agent_turn_receipts_v1")
    private fun later(block: () -> Unit) = io.execute { runCatching(block) }

    private fun change(context: Context, chat: String, turn: String, create: Boolean = false,
        block: (JSONObject) -> Unit) {
        if (chat.isBlank() || turn.isBlank()) return
        val c = context.applicationContext
        later {
            val db = database(c)
            val prefix = prefix(chat)
            val key = prefix + AgentNativeJsonCodec.sha256(turn)
            val before = db.readString(key, "")
            if (before.isEmpty() && (!create || db.contains(prefix + "deleted"))) return@later
            val value = if (before.isEmpty()) JSONObject() else JSONObject(before)
            block(value)
            val after = value.toString()
            if (after != before) db.writeString(key, after)
        }
    }

    fun begin(c: Context, chat: String, turn: String, choice: AgentModelSelection) {
        val key = Key(chat, turn)
        val wall = System.currentTimeMillis()
        synchronized(live) {
            if (key in live) return
            if (live.size >= 256) live.remove(live.keys.first())
            live[key] = Live(SystemClock.elapsedRealtime())
        }
        change(c, chat, turn, create = true) { row ->
            if (!row.has("sent")) row.put("sent", wall).put("mode", choice.mode.name)
                .put("request", id(choice.modelId)).put("effort", choice.reasoningEffort.wireValue)
        }
    }

    fun observeBody(chat: String, turn: String): Boolean =
        synchronized(live) { live[Key(chat, turn)]?.painted == false }

    fun painted(c: Context, chat: String, turn: String) {
        val elapsed = synchronized(live) {
            val state = live[Key(chat, turn)] ?: return
            if (state.painted) return
            state.painted = true
            SystemClock.elapsedRealtime() - state.start
        }
        val wall = System.currentTimeMillis()
        change(c, chat, turn) { if (!it.has("body")) it.put("body", wall).put("body_ms", elapsed) }
    }

    fun outbound(c: Context, chat: String, turn: String, task: String, model: String, effort: AgentModelReasoningEffort) =
        change(c, chat, turn) {
            val key = AgentNativeJsonCodec.sha256(task)
            if (key != it.optString("task")) {
                for (k in listOf("attempt", "generation", "provider", "submitted", "submitted_effort", "result")) it.remove(k)
                it.put("task", key)
            }
            it.put("wire", id(model)).put("wire_effort", effort.wireValue)
        }

    data class Desktop(val received: Long, val generation: Long, val attempt: Int, val provider: String,
        val model: String, val effort: String, val terminal: Boolean)

    fun desktopEvidence(payload: JSONObject): Desktop {
        val trace = payload.optJSONArray("delivery_trace")
        val received = (0 until minOf(trace?.length() ?: 0, 128)).mapNotNull { index ->
            trace?.optJSONObject(index)?.takeIf { it.optString("stage") == "desktop_mqtt_received" }
                ?.optLong("at")?.takeIf { it > 0 }
        }.minOrNull() ?: 0L
        val task = payload.optString("task_id")
        val generation = payload.optLong("execution_generation", 1)
        val receipt = payload.optJSONObject("turn_receipt")?.takeIf { it.optLong("generation") == generation }
        val candidates = buildList {
            payload.optJSONObject("progress_event")?.let(::add)
            val events = payload.optJSONArray("events")
            for (i in 0 until minOf(events?.length() ?: 0, 256)) events?.optJSONObject(i)?.let(::add)
        }
        val meta = candidates.mapNotNull { event ->
            val m = event.optJSONObject("metadata") ?: return@mapNotNull null
            val a = m.optInt("attempt")
            m.takeIf { a > 0 && event.optString("kind") in setOf("agent", "model") &&
                event.optString("event_id") == "provider:$task:${a - 1}" &&
                m.optLong("execution_generation", 1) == generation && id(m.opt("provider")).isNotBlank() }
        }.maxByOrNull { it.optInt("attempt") }
        val at = received.takeIf { it > 0 } ?: receipt?.optLong("desktop_received_at")?.coerceAtLeast(0) ?: 0L
        val replay = receipt?.optJSONObject("submission")
        if (replay != null && replay.optInt("attempt") > 0 && replay.optInt("attempt") >= (meta?.optInt("attempt") ?: 0) &&
            id(replay.opt("provider")).isNotEmpty())
            return Desktop(at, generation, replay.getInt("attempt"), id(replay.opt("provider")),
                id(replay.opt("model")), id(replay.opt("effort")), payload.optString("type") == "text")
        return Desktop(at, generation, meta?.optInt("attempt") ?: 0, id(meta?.opt("provider")),
            id(meta?.opt("model")), id(meta?.opt("reasoning_effort")), payload.optString("type") == "text")
    }

    fun authenticated(c: Context, payload: JSONObject) {
        val d = desktopEvidence(payload)
        if (d.received == 0L && d.attempt == 0 && !d.terminal && d.generation <= 1) return
        val task = AgentNativeJsonCodec.sha256(payload.optString("task_id"))
        val at = System.currentTimeMillis()
        change(c, payload.optString("conversation_id"), payload.optString("turn_id")) { row ->
            if (row.has("task") && row.optString("task") != task) return@change
            if (d.received > 0 && !row.has("desktop_received")) row.put("desktop_received", d.received)
            if (row.optLong("generation") < d.generation) {
                row.put("task", task).put("generation", d.generation)
                for (k in listOf("attempt", "provider", "submitted", "submitted_effort", "result")) row.remove(k)
            }
            if (row.optLong("generation") != d.generation) return@change
            if (d.attempt > 0 && d.attempt >= row.optInt("attempt")) {
                row.put("attempt", d.attempt).put("provider", d.provider)
                    .put("submitted", d.model).put("submitted_effort", d.effort)
            }
            if (d.terminal && !row.has("result")) row.put("result", at)
        }
    }

    fun cloudStarted(c: Context, r: AgentModelRequest, model: String): Long {
        val attempt = sequence.incrementAndGet()
        change(c, r.conversationId, r.turnId) {
            it.put("cloud_attempt", attempt).put("cloud_request", id(model)).remove("cloud_actual")
            it.remove("cloud_effort")
        }
        return attempt
    }

    fun cloudResponse(c: Context, r: AgentModelRequest, attempt: Long, actual: Any?, effort: Any?) =
        change(c, r.conversationId, r.turnId) {
            if (attempt == it.optLong("cloud_attempt")) it.put("cloud_actual", id(actual)).put("cloud_effort", id(effort))
        }

    fun localModel(c: Context, r: AgentModelRequest, profile: Any?) =
        change(c, r.conversationId, r.turnId) { it.put("local_profile", id(profile)) }

    fun toolFinished(c: Context, ctx: AgentNativeToolInvocationContext, tool: String, result: AgentNativeToolResult) {
        if (!result.isSuccess || result.receipt.status != result.status || result.receipt.replayed ||
            result.provenance.toolId != tool || result.receipt.invocationId != ctx.invocationId) return
        val key = when (result.provenance.location) {
            AgentNativeToolLocation.PHONE, AgentNativeToolLocation.ANDROID_SYSTEM,
            AgentNativeToolLocation.ACCESSIBILITY_SERVICE -> "phone_executed"
            AgentNativeToolLocation.DESKTOP -> "desktop_executed"
            else -> return
        }
        change(c, ctx.conversationId, ctx.turnId) { it.put(key, true) }
    }

    fun read(context: Context, chat: String, turn: String, result: (JSONObject) -> Unit) {
        val c = context.applicationContext
        io.execute {
            val value = runCatching { JSONObject(database(c).readString(prefix(chat) +
                AgentNativeJsonCodec.sha256(turn), "{}")) }.getOrElse { JSONObject() }
            Handler(Looper.getMainLooper()).post { result(value) }
        }
    }

    fun delete(context: Context, chat: String) {
        synchronized(live) { live.keys.removeAll { it.chat == chat } }
        val c = context.applicationContext
        later { val db = database(c); val prefix = prefix(chat)
            db.mutateStrings(mapOf(prefix + "deleted" to "true"), db.keys(prefix)) }
    }

    fun clear(context: Context) {
        synchronized(live) { live.clear() }
        val c = context.applicationContext
        later { database(c).clear() }
    }
}
