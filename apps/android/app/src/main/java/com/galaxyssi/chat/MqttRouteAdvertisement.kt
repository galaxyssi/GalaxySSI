package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

internal data class MqttRouteAdvertisement(
    val sender: String,
    val receiver: String,
    val epoch: Long,
    val resumeId: String,
    val issuedAtMs: Long,
    val expiresAtMs: Long,
    val receiveBrokers: Set<String>,
    val packetBytes: Int
) {
    fun toWire(): JSONObject = JSONObject()
        .put("type", "link_resume")
        .put("transport_version", MqttBrokerCatalog.TRANSPORT_VERSION)
        .put("sender_fingerprint", sender)
        .put("receiver_fingerprint", receiver)
        .put("route_epoch", epoch)
        .put("resume_id", resumeId)
        .put("issued_at_ms", issuedAtMs)
        .put("expires_at_ms", expiresAtMs)
        .put("supported_brokers", JSONArray(MqttBrokerCatalog.brokers.keys.sorted()))
        .put("receive_brokers", JSONArray(receiveBrokers.sorted()))
        .put("max_encoded_packet_bytes", packetBytes)
        .put("multipath", true)
        .put("chunk_acks", true)

    fun digest(): String {
        val wire = toWire()
        val canonical = wire.keys().asSequence().sorted().joinToString(",", "{", "}") { key ->
            val value = wire.get(key)
            JSONObject.quote(key) + ":" + if (value is String) JSONObject.quote(value) else value.toString()
        }
        return sha256(canonical)
    }

    companion object {
        const val MAX_EPOCH = 9_007_199_254_740_991L
        private val fingerprint = Regex("[a-f0-9]{64}")
        private val identifier = Regex("[a-f0-9]{32}")

        /** Validation only; the caller must first authenticate the existing relationship AEAD. */
        fun parseVerified(payload: JSONObject, sender: String, receiver: String, nowMs: Long): MqttRouteAdvertisement {
            require(payload.optString("type") == "link_resume" &&
                strictLong(payload, "transport_version") == MqttBrokerCatalog.TRANSPORT_VERSION.toLong() &&
                payload.opt("multipath") == true && payload.opt("chunk_acks") == true) {
                "Unsupported multipath capabilities"
            }
            require(sender.matches(fingerprint) && receiver.matches(fingerprint) && sender != receiver &&
                payload.optString("sender_fingerprint") == sender && payload.optString("receiver_fingerprint") == receiver) {
                "Resume identity binding mismatch"
            }
            val epoch = strictLong(payload, "route_epoch")
            val issued = strictLong(payload, "issued_at_ms")
            val expires = strictLong(payload, "expires_at_ms")
            val packetBytes = strictLong(payload, "max_encoded_packet_bytes")
            require(epoch in 1..MAX_EPOCH && issued in 0..MAX_EPOCH && expires in 1..MAX_EPOCH &&
                issued <= nowMs + 300_000 && expires - issued in 1..MqttBrokerCatalog.RESUME_TTL_MS &&
                expires > nowMs && packetBytes in 1..MqttBrokerCatalog.PACKET_BYTES.toLong()) { "Invalid or expired resume" }
            val resumeId = payload.optString("resume_id")
            require(resumeId.matches(identifier)) { "Invalid resume identifier" }
            val supported = strictStrings(payload, "supported_brokers")
            val active = strictStrings(payload, "receive_brokers")
            require(supported.size == 3 && supported.toSet() == MqttBrokerCatalog.brokers.keys &&
                active.size <= 3 && active.size == active.toSet().size && MqttBrokerCatalog.brokers.keys.containsAll(active)) {
                "Invalid broker receive collection"
            }
            return MqttRouteAdvertisement(sender, receiver, epoch, resumeId, issued, expires, active.toSet(), packetBytes.toInt())
        }

        private fun strictLong(payload: JSONObject, key: String): Long {
            val value = payload.opt(key)
            require(value is Int || value is Long) { "Resume counters must be integers" }
            return (value as Number).toLong()
        }

        private fun strictStrings(payload: JSONObject, key: String): List<String> {
            val value = payload.optJSONArray(key) ?: throw IllegalArgumentException("Invalid broker list")
            require(value.length() <= 3)
            return (0 until value.length()).map { index ->
                val entry = value.get(index)
                require(entry is String) { "Broker identifiers must be strings" }
                entry
            }
        }

        internal fun sha256(value: String): String {
            val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            val digits = "0123456789abcdef"
            return buildString(64) { bytes.forEach {
                append(digits[(it.toInt() ushr 4) and 15]); append(digits[it.toInt() and 15])
            } }
        }
    }
}
