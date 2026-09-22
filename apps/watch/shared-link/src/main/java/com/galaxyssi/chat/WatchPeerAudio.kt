package com.galaxyssi.chat

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** Bounded voice adapter for Android's input_attachment manifest/chunk/receipt protocol.
 * All records, including audio bytes, remain in encrypted app storage. Serial-worker only. */
internal class WatchPeerAudio(context: Context, private val queue: (String, JSONObject) -> Unit) {
    private val incoming = AgentEncryptedDatabase(context, "watch_voice_incoming")
    private val outgoing = AgentEncryptedDatabase(context, "watch_voice_outgoing")
    companion object {
        const val LIMIT = 1024 * 1024
        const val CHUNK = 256 * 1024
        fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        private val digest = Regex("[a-f0-9]{64}")
    }
    fun prepare(peer: String, payload: JSONObject, bytes: ByteArray, duration: Long): JSONObject {
        require(bytes.size in 1..LIMIT && duration in 1..60_000)
        val attachment = "voice-${payload.getLong("client_message_id")}"
        val sha = hash(bytes)
        val transfer = hash(listOf(payload.getString("client_route_id"), payload.getString("conversation_id"),
            payload.getString("task_id"), payload.getString("turn_id"), attachment, sha).joinToString("\u0000").toByteArray())
        val count = (bytes.size + CHUNK - 1) / CHUNK
        val manifest = JSONObject(payload.toString()).put("type", "input_attachment_manifest")
            .put("contact_id", peer).put("desktop_id", peer).put("transfer_id", transfer).put("attachment_id", attachment)
            .put("attachment_ordinal", 0).put("name", "$attachment.opus").put("original_name", "$attachment.opus")
            .put("mime_type", "audio/ogg").put("size_bytes", bytes.size).put("original_size_bytes", bytes.size)
            .put("sha256", sha).put("chunk_size_bytes", CHUNK).put("chunk_count", count)
            .put("duration_ms", duration).put("transport_profile", "original").put("eager_chunks", true).put("resume", false)
        val record = JSONObject().put("peer", peer).put("manifest", manifest).put("data", Base64.encodeToString(bytes, Base64.NO_WRAP))
        outgoing.writeString(transfer, record.toString())
        queue(peer, manifest)
        repeat(count) { sendChunk(record, it) }
        return JSONObject().put("id", attachment).put("transfer_id", transfer).put("name", "$attachment.opus")
            .put("mime_type", "audio/ogg").put("size", bytes.size).put("sha256", sha)
            .put("chunk_count", count).put("chunk_size_bytes", CHUNK).put("transport_status", "chunked").put("duration_ms", duration)
    }
    private fun sendChunk(record: JSONObject, index: Int) {
        val manifest = record.getJSONObject("manifest")
        val bytes = Base64.decode(record.getString("data"), Base64.NO_WRAP)
        try {
            val part = bytes.copyOfRange(index * CHUNK, minOf(bytes.size, (index + 1) * CHUNK))
            try { queue(record.getString("peer"), JSONObject(manifest.toString()).put("type", "input_attachment_chunk")
                .put("chunk_index", index).put("chunk_size", part.size).put("chunk_sha256", hash(part))
                .put("data_b64", Base64.encodeToString(part, Base64.NO_WRAP))) } finally { part.fill(0) }
        } finally { bytes.fill(0) }
    }
    fun accept(peer: String, route: String, payload: JSONObject) {
        val id = payload.getString("transfer_id")
        require(id.matches(digest) && payload.optString("client_route_id") == route)
        require(payload.optString("conversation_id") == WatchPeerProtocol.conversation(peer, GalaxySSICrypto.localGalaxySSIId()))
        if (payload.optString("type") == "input_attachment_receipt") {
            val raw = outgoing.readString(id, "").takeIf { it.isNotBlank() } ?: return
            val record = JSONObject(raw); val m = record.getJSONObject("manifest")
            require(record.getString("peer") == peer && payload.optString("sha256") == m.getString("sha256") &&
                payload.optString("task_id") == m.getString("task_id") && payload.optString("turn_id") == m.getString("turn_id"))
            if (payload.optString("status") == "missing") {
                val ranges = payload.optJSONArray("missing_ranges") ?: return
                require(ranges.length() <= 4)
                for (i in 0 until ranges.length()) {
                    val range = ranges.getJSONArray(i); val first = range.getInt(0); val last = range.getInt(1)
                    require(first in 0 until m.getInt("chunk_count") && last in first until m.getInt("chunk_count"))
                    for (index in first..last) sendChunk(record, index)
                }
            }
            return
        }
        require(payload.optString("contact_id") == GalaxySSICrypto.localGalaxySSIId())
        val size = payload.getInt("size_bytes"); val count = payload.getInt("chunk_count")
        require(size in 1..LIMIT && payload.getInt("chunk_size_bytes") == CHUNK && count == (size + CHUNK - 1) / CHUNK)
        require(payload.getString("sha256").matches(digest) && payload.optString("mime_type") in setOf("audio/ogg", "audio/mp4", "audio/wav"))
        val previous = incoming.readString(id, "")
        val record = if (previous.isBlank()) {
            require(payload.getString("type") == "input_attachment_manifest")
            JSONObject().put("peer", peer).put("manifest", payload).put("parts", JSONObject())
        } else JSONObject(previous)
        val manifest = record.getJSONObject("manifest")
        require(record.getString("peer") == peer && manifest.getString("sha256") == payload.getString("sha256") &&
            manifest.getInt("size_bytes") == size && manifest.getString("task_id") == payload.getString("task_id") &&
            manifest.getString("turn_id") == payload.getString("turn_id"))
        val parts = record.getJSONObject("parts")
        if (payload.getString("type") == "input_attachment_chunk") {
            val index = payload.getInt("chunk_index"); require(index in 0 until count)
            val encoded = payload.getString("data_b64"); require(encoded.length <= CHUNK * 2)
            val bytes = Base64.decode(encoded, Base64.DEFAULT)
            try {
                require(bytes.size == minOf(CHUNK, size - index * CHUNK) && payload.getInt("chunk_size") == bytes.size && hash(bytes) == payload.getString("chunk_sha256"))
                parts.put(index.toString(), encoded)
            } finally { bytes.fill(0) }
        }
        val missing = (0 until count).filter { !parts.has(it.toString()) }
        if (missing.isEmpty() && !record.optBoolean("complete")) {
            val bytes = assemble(record)
            try { require(hash(bytes) == manifest.getString("sha256")); record.put("complete", true) } finally { bytes.fill(0) }
        }
        incoming.writeString(id, record.toString())
        val receipt = JSONObject(manifest.toString()).put("type", "input_attachment_receipt")
            .put("contact_id", GalaxySSICrypto.localGalaxySSIId()).put("source_message_id", manifest.optString("client_message_id"))
            .put("status", if (missing.isEmpty()) "stored" else "missing")
            .put("received_bytes", size - missing.sumOf { minOf(CHUNK, size - it * CHUNK) })
            .put("missing_ranges", JSONArray(missing.map { JSONArray().put(it).put(it) }))
        receipt.remove("data_b64")
        queue(peer, receipt)
    }
    private fun assemble(record: JSONObject): ByteArray {
        val m = record.getJSONObject("manifest"); val result = ByteArray(m.getInt("size_bytes"))
        repeat(m.getInt("chunk_count")) { index ->
            val part = Base64.decode(record.getJSONObject("parts").getString(index.toString()), Base64.DEFAULT)
            try { part.copyInto(result, index * CHUNK) } finally { part.fill(0) }
        }
        return result
    }
    fun read(peer: String, id: String): ByteArray? {
        if (!id.matches(digest)) return null
        val sent = outgoing.readString(id, "")
        if (sent.isNotBlank()) JSONObject(sent).takeIf { it.optString("peer") == peer }?.let { return Base64.decode(it.getString("data"), Base64.DEFAULT) }
        val raw = incoming.readString(id, "").takeIf { it.isNotBlank() } ?: return null
        return JSONObject(raw).takeIf { it.optString("peer") == peer && it.optBoolean("complete") }?.let(::assemble)
    }
    fun clear(peer: String) {
        for (store in listOf(incoming, outgoing)) store.removeAll(store.entries().filter { JSONObject(it.second).optString("peer") == peer }.map { it.first })
    }
}
