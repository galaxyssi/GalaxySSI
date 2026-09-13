package com.galaxyssi.chat

import org.json.JSONObject
import java.util.Base64
import java.util.UUID

/** Pair-AEAD control state, never a business/task completion receipt. */
internal object MqttChunkReceipts {
    const val FIELD = "_mqtt_chunks"
    const val PROBE = "link_chunk_probe"
    const val STATE = "link_chunk_state"
    val brokers = MqttBrokerCatalog.brokers.keys.sorted()
    private val hash = Regex("[a-f0-9]{64}")
    private val nonce = Regex("[a-f0-9]{32}")
    fun newRequest() = UUID.randomUUID().toString().replace("-", "")

    data class Query(val transfer: String, val manifest: String, val count: Int, val request: String) {
        fun wire() = JSONObject().put("type", PROBE).put("version", 1).put("transfer_id", transfer)
            .put("manifest_hash", manifest).put("chunk_count", count).put("request_id", request)
        fun response(epoch: String, revision: Long, indices: Collection<Int>): JSONObject {
            val bytes = ByteArray((count + 7) / 8)
            indices.forEach { index ->
                require(index in 0 until count)
                bytes[index / 8] = (bytes[index / 8].toInt() or (1 shl (index % 8))).toByte()
            }
            return wire().put("type", STATE).put("store_epoch", epoch).put("revision", revision)
                .put("stored_bitmap", Base64.getEncoder().encodeToString(bytes)).also { parseState(it) }
        }
    }
    data class State(val query: Query, val epoch: String, val revision: Long, val bitmap: ByteArray)

    fun parse(raw: JSONObject): Query {
        require(raw.optString("type") in setOf(PROBE, STATE) && number(raw.opt("version"), 1, 1) == 1L)
        return Query(text(raw.opt("transfer_id"), hash), text(raw.opt("manifest_hash"), hash),
            number(raw.opt("chunk_count"), 1, MqttChunkManifest.MAX_COUNT.toLong()).toInt(),
            text(raw.opt("request_id"), nonce))
    }

    fun fromChunk(raw: JSONObject): Query? {
        if (!raw.has(FIELD)) return null
        val query = parse(raw.getJSONObject(FIELD))
        val chunk = MqttChunkManifest.parse(raw)
        require(query.transfer == chunk.transfer && query.manifest == chunk.manifestHash && query.count == chunk.count) {
            "Chunk request does not match its manifest"
        }
        return query
    }

    fun parseState(raw: JSONObject): State {
        val query = parse(raw)
        require(raw.optString("type") == STATE)
        val epoch = text(raw.opt("store_epoch"), nonce)
        val revision = number(raw.opt("revision"), 0, MqttDeliveryEnvelope.MAX_SAFE_INTEGER)
        val encoded = raw.opt("stored_bitmap")
        val size = (query.count + 7) / 8
        require(encoded is String && encoded.length == 4 * ((size + 2) / 3)) { "Invalid chunk bitmap size" }
        val data = Base64.getDecoder().decode(encoded)
        require(data.size == size && Base64.getEncoder().encodeToString(data) == encoded &&
            (query.count % 8 == 0 || (data.last().toInt() and 255) ushr (query.count % 8) == 0) &&
            (epoch != "0".repeat(32) || (revision == 0L && data.all { it == 0.toByte() }))) { "Invalid chunk state bitmap" }
        return State(query, epoch, revision, data)
    }

    private fun text(value: Any?, format: Regex): String {
        require(value is String && format.matches(value)) { "Invalid chunk control identity" }
        return value
    }
    private fun number(value: Any?, minimum: Long, maximum: Long): Long {
        require(value is Int || value is Long) { "Invalid chunk state counter" }
        return (value as Number).toLong().also { require(it in minimum..maximum) }
    }
}
