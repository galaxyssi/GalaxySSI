package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MqttDeliveryEnvelopeTest {
    private fun wire() = JSONObject().put("scheme", "signal").put("from", "phone-A").put("to", "desktop-B")
        .put("signal_type", "prekey").put("message_type", 3).put("body", "AQIDBA==").put("version", 1)
    private fun frame() = MqttDeliveryEnvelope.Frame(
        MqttDeliveryEnvelope.Message("message-1", MqttDeliveryEnvelope.contentHash(wire()), "a".repeat(64), "b".repeat(64), "message"),
        MqttDeliveryEnvelope.Attempt("c".repeat(32), "hivemq", 7))
    private fun parse(wire: JSONObject) = MqttDeliveryEnvelope.parseVerifiedFrame(wire, "a".repeat(64), "b".repeat(64), "hivemq")

    @Test fun sharedPythonGoldenDigests() {
        assertEquals("d8d7f88a7543d8bd82fc4d7c364283923a15752ba6d1f23af4903d19a544d581", MqttDeliveryEnvelope.contentHash(wire()))
        val unicode = JSONObject().put("scheme", "signal").put("from", "\u624b\u673a-A").put("to", "\u7535\u8111-B")
            .put("signal_type", "signal").put("message_type", 2).put("body", "AA==").put("device_id", 1).put("version", 1)
        assertEquals("94c78f615ab4f6d1e8120091f1d0e25f57eeb4b2beb94833b1b6507f957f2d3c", MqttDeliveryEnvelope.contentHash(unicode))
    }

    @Test fun mutableTimeAndAttemptMetadataDoNotChangeCiphertextHash() {
        assertEquals(MqttDeliveryEnvelope.contentHash(wire()),
            MqttDeliveryEnvelope.contentHash(wire().put("time", 1.25).put(MqttDeliveryEnvelope.FIELD, JSONObject().put("unknown", true))))
    }

    @Test fun everySignalFieldIsBound() {
        val original = wire()
        original.keys().forEach { key ->
            val value = original.get(key)
            if (key == "scheme") assertThrows(IllegalArgumentException::class.java) {
                MqttDeliveryEnvelope.contentHash(wire().put(key, "other"))
            } else {
                val changed = if (value is Int) value + 1 else "$value-x"
                assertNotEquals(MqttDeliveryEnvelope.contentHash(original), MqttDeliveryEnvelope.contentHash(wire().put(key, changed)))
            }
        }
    }

    @Test fun attemptAndReceiptRoundTripWithoutMutatingOriginalCiphertext() {
        val original = wire()
        val frame = frame()
        assertEquals(frame, parse(frame.attach(original)))
        assertFalse(original.has(MqttDeliveryEnvelope.FIELD))
        val receipt = frame.receiptAfterStore(frame.message.messageId, frame.message.contentHash)
        assertEquals(frame, MqttDeliveryEnvelope.parseVerifiedReceipt(receipt, "a".repeat(64), "b".repeat(64)))
    }

    @Test fun authenticatedPairAndActualIngressCannotBeOverriddenByMetadata() {
        val wire = frame().attach(wire())
        for ((sender, receiver, broker) in listOf(Triple("d".repeat(64), "b".repeat(64), "hivemq"),
                Triple("a".repeat(64), "d".repeat(64), "hivemq"), Triple("a".repeat(64), "b".repeat(64), "emqx"))) {
            assertThrows(IllegalArgumentException::class.java) { MqttDeliveryEnvelope.parseVerifiedFrame(wire, sender, receiver, broker) }
        }
    }

    @Test fun tamperedCiphertextAndDoubleWrappingAreRejected() {
        val frame = frame()
        val wire = frame.attach(wire())
        assertThrows(IllegalArgumentException::class.java) { frame.attach(wire) }
        assertThrows(IllegalArgumentException::class.java) { parse(wire.put("body", "AA==")) }
    }

    @Test fun onlyMatchingStoredRecordCanProduceReceipt() {
        val frame = frame()
        assertThrows(IllegalArgumentException::class.java) { frame.receiptAfterStore("other", frame.message.contentHash) }
        assertThrows(IllegalArgumentException::class.java) { frame.receiptAfterStore("message-1", "d".repeat(64)) }
    }

    @Test fun ackOfAckCannotBeProduced() {
        val original = frame()
        val receipt = original.copy(message = original.message.copy(traffic = "receipt"))
        assertThrows(IllegalArgumentException::class.java) { receipt.receiptAfterStore("message-1", receipt.message.contentHash) }
    }

    @Test fun strictNumbersAndKnownProtocolValuesAreRequired() {
        val invalid = mapOf("generation" to listOf(true, 1.0, "7", 0, -1, 9_007_199_254_740_992L),
            "version" to listOf(true, 1.0, "1", 2), "broker_id" to listOf("unknown", JSONObject.NULL),
            "traffic" to listOf("unknown", JSONObject.NULL), "attempt_id" to listOf("", "C".repeat(32)),
            "content_hash_algorithm" to listOf("sha256", JSONObject.NULL))
        invalid.forEach { (key, values) -> values.forEach { value ->
            val wire = frame().attach(wire())
            wire.getJSONObject(MqttDeliveryEnvelope.FIELD).put(key, value)
            assertThrows(IllegalArgumentException::class.java) { parse(wire) }
        } }
    }

    @Test fun brokerOrTaskStatusCannotMasqueradeAsStoredReceipt() {
        val receipt = MqttDeliveryEnvelope.storedReceipt("message-1", frame().message.contentHash)
        assertEquals("message-1" to frame().message.contentHash, MqttDeliveryEnvelope.parseStoredReceipt(receipt))
        for (status in listOf("accepted", "BROKER_ACKED", "CHUNK_STORED", "TASK_ACCEPTED", "RUN_FINISHED", "")) {
            assertThrows(IllegalArgumentException::class.java) {
                MqttDeliveryEnvelope.parseStoredReceipt(JSONObject(receipt.toString()).put("delivery_status", status))
            }
        }
    }

    @Test fun allRelationshipComponentsFenceReceipts() {
        val values = listOf("pair", "a".repeat(64), "b".repeat(64), "secret")
        fun binding(v: List<String>) = MqttDeliveryEnvelope.receiptBinding(v[0], v[1], v[2], v[3])
        values.indices.forEach { index ->
            val changed = values.toMutableList().also { it[index] += "x" }
            assertNotEquals(binding(values), binding(changed))
        }
        assertNotEquals(MqttDeliveryEnvelope.receiptBinding("ab", "c", "d", "e"),
            MqttDeliveryEnvelope.receiptBinding("a", "bc", "d", "e"))
    }

    @Test fun invalidUnicodeCannotAliasValidUtf8Identity() {
        assertThrows(IllegalArgumentException::class.java) { MqttDeliveryEnvelope.contentHash(wire().put("from", "bad\uD800")) }
    }
}
