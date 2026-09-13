package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MqttDeliveryEnvelopeDeviceTest {
    private val routes = GalaxySSILinkProtocol.Routes("a".repeat(22), "A".repeat(43), "b".repeat(64), "a".repeat(64))
    private fun wire() = JSONObject().put("scheme", "signal").put("from", "alice").put("to", "bob")
        .put("signal_type", "prekey").put("message_type", 3).put("body", "AQIDBA==")
    private fun frame(broker: String = "hivemq") = MqttDeliveryEnvelope.Frame(
        MqttDeliveryEnvelope.Message("synthetic-message", MqttDeliveryEnvelope.contentHash(wire()),
            routes.remoteFingerprint, routes.localFingerprint, "message"),
        MqttDeliveryEnvelope.Attempt("c".repeat(32), broker, 1))

    @Test fun actualAndroidIngressParsesFramedCopyAfterOpeningPairAead() {
        for (broker in MqttBrokerCatalog.brokers.keys) {
            val expected = frame(broker)
            val sealed = GalaxySSILinkProtocol.sealWirePacket(expected.attach(wire()).toString(), routes.linkSecret)
            val decoded = JSONObject(GalaxySSILinkProtocol.openWirePacket(sealed.toByteArray(), routes.linkSecret))
            assertEquals(expected, AndroidMqttDelivery.frame(routes, decoded, MqttBrokerPool.Ingress(broker, 1, 1_000)))
        }
    }

    @Test fun authenticatedButWrongFrameCannotCrossIdentityIngressOrCipherHash() {
        val expected = frame()
        val ingress = MqttBrokerPool.Ingress("hivemq", 1, 1_000)
        assertThrows(IllegalArgumentException::class.java) {
            AndroidMqttDelivery.frame(routes.copy(remoteFingerprint = "d".repeat(64)), expected.attach(wire()), ingress)
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidMqttDelivery.frame(routes, expected.attach(wire()), MqttBrokerPool.Ingress("emqx", 1, 1_000))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AndroidMqttDelivery.frame(routes, expected.attach(wire()).put("body", "different"), ingress)
        }
        assertNull(AndroidMqttDelivery.frame(routes, wire(), ingress))
    }

    @Test fun alternateAeadSealsPreserveOneSignalCiphertextAndOneReceiptHash() {
        val expected = frame()
        val first = GalaxySSILinkProtocol.sealWirePacket(expected.attach(wire()).toString(), routes.linkSecret)
        val secondFrame = expected.copy(attempt = expected.attempt.copy(attemptId = "d".repeat(32), brokerId = "emqx"))
        val second = GalaxySSILinkProtocol.sealWirePacket(secondFrame.attach(wire()).toString(), routes.linkSecret)
        assertNotEquals(first, second)
        for (sealed in listOf(first, second)) {
            val decoded = JSONObject(GalaxySSILinkProtocol.openWirePacket(sealed.toByteArray(), routes.linkSecret))
            assertEquals("AQIDBA==", decoded.getString("body"))
            assertEquals(expected.message.contentHash, MqttDeliveryEnvelope.contentHash(decoded))
        }
    }

    @Test fun platformJsonProducesTheSameDigestAsDesktopPython() {
        val wire = JSONObject("""{"scheme":"signal","from":"phone-A","to":"desktop-B","signal_type":"prekey","message_type":3,"body":"AQIDBA==","version":1}""")
        assertEquals("d8d7f88a7543d8bd82fc4d7c364283923a15752ba6d1f23af4903d19a544d581", MqttDeliveryEnvelope.contentHash(wire))
        wire.put("time", 1.25)
        assertEquals("d8d7f88a7543d8bd82fc4d7c364283923a15752ba6d1f23af4903d19a544d581", MqttDeliveryEnvelope.contentHash(wire))
    }

    @Test fun utf8DigestIsNotBasedOnJavaCharacterCounts() {
        val wire = JSONObject().put("scheme", "signal").put("from", "\u624b\u673a-A").put("to", "\u7535\u8111-B")
            .put("signal_type", "signal").put("message_type", 2).put("body", "AA==").put("device_id", 1).put("version", 1)
        assertEquals("94c78f615ab4f6d1e8120091f1d0e25f57eeb4b2beb94833b1b6507f957f2d3c", MqttDeliveryEnvelope.contentHash(wire))
    }

    @Test fun existingPairAeadProtectsStoredReceiptAndRejectsWrongSecret() {
        val secret = "A".repeat(43)
        val receipt = MqttDeliveryEnvelope.storedReceipt("synthetic-message", "c".repeat(64))
        val sealed = GalaxySSILinkProtocol.sealWirePacket(receipt.toString(), secret)
        assertFalse(sealed.contains("synthetic-message"))
        val decoded = JSONObject(GalaxySSILinkProtocol.openWirePacket(sealed.toByteArray(), secret))
        assertEquals("synthetic-message" to "c".repeat(64), MqttDeliveryEnvelope.parseStoredReceipt(decoded))
        assertThrows(Exception::class.java) { GalaxySSILinkProtocol.openWirePacket(sealed.toByteArray(), "B".repeat(43)) }
    }
}
