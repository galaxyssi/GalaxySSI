package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MqttDeliveryEnvelopeDeviceTest {
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
