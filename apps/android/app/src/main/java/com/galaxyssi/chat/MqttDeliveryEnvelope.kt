package com.galaxyssi.chat

import org.json.JSONObject
import java.security.MessageDigest

/** Metadata lives inside existing pair AEAD. Parsing alone never authenticates or stores a message. */
internal object MqttDeliveryEnvelope {
    const val FIELD = "_mqtt_delivery"
    const val ALGORITHM = "signal-wire-sha256-v1"
    const val RECEIPT_TYPE = "link_rx_stored"
    const val MAX_SAFE_INTEGER = 9_007_199_254_740_991L
    private const val MAX_WIRE_BODY = 4 * 1024 * 1024
    private val hash = Regex("[a-f0-9]{64}")
    private val token = Regex("[a-f0-9]{32}")
    private val traffic = setOf("control", "message", "final", "progress", "chunk", "receipt")
    private val textFields = listOf("scheme", "from", "to", "signal_type", "type", "body", "protocol")
    private val numberFields = listOf("message_type", "messageType", "device_id", "version")

    data class Message(val messageId: String, val contentHash: String, val sender: String,
                       val receiver: String, val traffic: String) {
        init {
            checkedString(messageId)
            require(hash.matches(contentHash) && hash.matches(sender) && hash.matches(receiver))
            require(sender != receiver && traffic in MqttDeliveryEnvelope.traffic)
        }
    }

    data class Attempt(val attemptId: String, val brokerId: String, val generation: Long) {
        init {
            require(token.matches(attemptId) && brokerId in MqttBrokerCatalog.brokers)
            require(generation in 1..MAX_SAFE_INTEGER)
        }
    }

    data class Frame(val message: Message, val attempt: Attempt) {
        fun metadata(): JSONObject = JSONObject().put("version", 1).put("content_hash_algorithm", ALGORITHM)
            .put("message_id", message.messageId).put("content_hash", message.contentHash)
            .put("sender", message.sender).put("receiver", message.receiver).put("traffic", message.traffic)
            .put("attempt_id", attempt.attemptId).put("broker_id", attempt.brokerId).put("generation", attempt.generation)

        fun attach(wire: JSONObject): JSONObject {
            require(!wire.has(FIELD) && contentHash(wire) == message.contentHash)
            return JSONObject(wire.toString()).put(FIELD, metadata())
        }

        fun receiptAfterStore(storedMessageId: String, storedContentHash: String): JSONObject {
            validateApplication(storedMessageId, storedContentHash)
            require(message.traffic != "receipt") { "Receipts cannot request receipts" }
            return metadata().put("type", RECEIPT_TYPE).put("status", "RX_STORED")
        }

        fun validateApplication(messageId: String, wireHash: String) {
            require(message.messageId == messageId && message.contentHash == wireHash) {
                "Delivery frame does not match Signal application message"
            }
        }
    }

    /** UTF-8 length-prefixed Signal fields, independent of JSON order, numbers, or UTF-16 length. */
    fun contentHash(wire: JSONObject): String {
        require(wire.opt("scheme") == "signal")
        for (key in listOf("from", "to", "body")) {
            checkedString(wire.opt(key), if (key == "body") MAX_WIRE_BODY else 512)
        }
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("GalaxySSI/SignalWireReceipt/v1\u0000".toByteArray(Charsets.UTF_8))
        for (key in textFields + numberFields) {
            if (!wire.has(key)) continue
            val value = wire.get(key)
            val kind: String
            val encoded: ByteArray
            if (key in textFields) {
                kind = "s"
                encoded = checkedString(value, if (key == "body") MAX_WIRE_BODY else 512).toByteArray(Charsets.UTF_8)
            } else {
                kind = "i"
                encoded = checkedInteger(value).toString().toByteArray(Charsets.US_ASCII)
            }
            digest.update("${key.length}:$key$kind${encoded.size}:".toByteArray(Charsets.US_ASCII))
            digest.update(encoded)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun parseVerifiedFrame(wire: JSONObject, sender: String, receiver: String, ingressBroker: String): Frame {
        val frame = parseMetadata(wire.getJSONObject(FIELD))
        require(frame.message.sender == sender && frame.message.receiver == receiver && frame.attempt.brokerId == ingressBroker)
        require(frame.message.contentHash == contentHash(wire)) { "Delivery ciphertext digest mismatch" }
        return frame
    }

    /** The authenticated actor is originalReceiver; the ACK may return on another path. */
    fun parseVerifiedReceipt(payload: JSONObject, originalSender: String, originalReceiver: String): Frame {
        require(payload.opt("type") == RECEIPT_TYPE && payload.opt("status") == "RX_STORED")
        return parseMetadata(payload).also {
            require(it.message.sender == originalSender && it.message.receiver == originalReceiver)
            require(it.message.traffic != "receipt")
        }
    }

    fun receiptBinding(scope: String, sender: String, receiver: String, secret: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("GalaxySSI/OutboundReceiptBinding/v1\u0000".toByteArray(Charsets.UTF_8))
        for (value in listOf(scope, sender, receiver, secret)) {
            val encoded = checkedString(value, 512).toByteArray(Charsets.UTF_8)
            digest.update("${encoded.size}:".toByteArray(Charsets.US_ASCII))
            digest.update(encoded)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun storedReceipt(messageId: String, wireHash: String): JSONObject {
        checkedString(messageId)
        require(hash.matches(wireHash))
        return JSONObject().put("type", "delivery_ack").put("delivery_status", "RX_STORED")
            .put("transport_message_id", messageId).put("content_hash", wireHash).put("content_hash_algorithm", ALGORITHM)
    }

    fun parseStoredReceipt(payload: JSONObject): Pair<String, String> {
        require(payload.opt("type") == "delivery_ack" && payload.opt("delivery_status") == "RX_STORED" &&
            payload.opt("content_hash_algorithm") == ALGORITHM)
        val message = checkedString(payload.opt("transport_message_id"))
        val digest = checkedString(payload.opt("content_hash"))
        require(hash.matches(digest))
        return message to digest
    }

    private fun parseMetadata(value: JSONObject): Frame {
        require(checkedInteger(value.opt("version")) == 1L && value.opt("content_hash_algorithm") == ALGORITHM)
        return Frame(Message(checkedString(value.opt("message_id")), checkedString(value.opt("content_hash")),
            checkedString(value.opt("sender")), checkedString(value.opt("receiver")), checkedString(value.opt("traffic"))),
            Attempt(checkedString(value.opt("attempt_id")), checkedString(value.opt("broker_id")),
                checkedInteger(value.opt("generation"))))
    }

    private fun checkedString(value: Any?, maximum: Int = 256): String {
        require(value is String && value.isNotEmpty() && value.toByteArray(Charsets.UTF_8).size <= maximum)
        require(value.none { it.code < 32 || it.code == 127 })
        require(value.indices.none { index ->
            val char = value[index]
            (char.isHighSurrogate() && (index == value.lastIndex || !value[index + 1].isLowSurrogate())) ||
                (char.isLowSurrogate() && (index == 0 || !value[index - 1].isHighSurrogate()))
        })
        return value
    }

    private fun checkedInteger(value: Any?): Long {
        require(value is Byte || value is Short || value is Int || value is Long)
        return (value as Number).toLong().also { require(it in 1..MAX_SAFE_INTEGER) }
    }
}
