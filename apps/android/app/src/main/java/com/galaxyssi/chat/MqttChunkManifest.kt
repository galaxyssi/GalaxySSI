package com.galaxyssi.chat

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.Base64

/** Immutable fragment validation shared by storage, scheduling, and receipt framing. */
internal data class MqttChunkManifest(val transfer: String, val manifestHash: String, val count: Int, val total: Int,
    val index: Int, val digest: String, val data: ByteArray, val source: String, val target: String) {
    companion object {
        const val SCHEME = "signal-chunk"
        const val DATA_BYTES = 380 * 1024
        const val MAX_BYTES = 2 * 1024 * 1024
        const val MAX_COUNT = 96
        private val HASH = Regex("[a-f0-9]{64}")
        fun parse(wire: JSONObject): MqttChunkManifest {
            require(wire.optString("scheme") == SCHEME) { "Not a GalaxySSI MQTT chunk" }
            val transfer = checkedHash(wire.opt("transfer_id"))
            require(transfer == checkedHash(wire.opt("sha256"))) { "Invalid MQTT transfer identity" }
            val digest = checkedHash(wire.opt("chunk_sha256"))
            val count = integer(wire, "chunk_count", 1, MAX_COUNT)
            val total = integer(wire, "total_bytes", count, MAX_BYTES)
            val index = integer(wire, "chunk_index", 0, count - 1)
            val source = text(wire.opt("from")); val target = text(wire.opt("to"))
            val encoded = wire.opt("data")
            require(encoded is String && encoded.length in 1..4 * ((DATA_BYTES + 2) / 3)) { "Invalid MQTT chunk encoding" }
            val data = Base64.getDecoder().decode(encoded)
            require(data.isNotEmpty() && data.size <= minOf(DATA_BYTES, total) && hash(data) == digest &&
                Base64.getEncoder().encodeToString(data) == encoded) { "MQTT chunk integrity check failed" }
            val canonical = ByteArrayOutputStream().apply {
                write("GalaxySSI/WireChunkManifest/v1\u0000".toByteArray(Charsets.US_ASCII))
                for (value in listOf(transfer, count.toString(), total.toString(), source, target)) {
                    val bytes = value.toByteArray(Charsets.UTF_8)
                    write("${bytes.size}:".toByteArray(Charsets.US_ASCII)); write(bytes)
                }
            }.toByteArray()
            return MqttChunkManifest(transfer, hash(canonical), count, total, index, digest, data, source, target)
        }
        fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        fun checkedHash(value: Any?): String {
            require(value is String && HASH.matches(value)) { "Invalid MQTT chunk hash" }
            return value
        }
        fun text(value: Any?): String {
            require(value is String && value.isNotEmpty() && value.toByteArray(Charsets.UTF_8).size <= 512 &&
                value.none { it.code < 32 || it.code == 127 }) { "Invalid MQTT chunk identity" }
            require(value.indices.none { index ->
                (value[index].isHighSurrogate() && (index == value.lastIndex || !value[index + 1].isLowSurrogate())) ||
                    (value[index].isLowSurrogate() && (index == 0 || !value[index - 1].isHighSurrogate()))
            })
            return value
        }
        private fun integer(wire: JSONObject, key: String, minimum: Int, maximum: Int): Int {
            val value = wire.opt(key)
            require(value is Int || value is Long) { "Invalid MQTT chunk counters" }
            return (value as Number).toLong().also { require(it in minimum.toLong()..maximum.toLong()) }.toInt()
        }
    }
}
