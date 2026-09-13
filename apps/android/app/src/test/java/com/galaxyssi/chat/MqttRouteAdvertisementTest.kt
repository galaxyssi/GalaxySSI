package com.galaxyssi.chat

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class MqttRouteAdvertisementTest {
    private val sender = "a".repeat(64)
    private val receiver = "b".repeat(64)
    private fun advertisement() = MqttRouteAdvertisement(sender, receiver, 1, "c".repeat(32),
        1000, 301000, MqttBrokerCatalog.brokers.keys, 1048576)

    @Test fun roundtripRequiresFullyAutomaticNewProtocol() {
        val value = advertisement()
        assertEquals(value, MqttRouteAdvertisement.parseVerified(value.toWire(), sender, receiver, 1000))
        assertFalse(value.toWire().has("default_broker"))
    }

    @Test fun canonicalDigestMatchesDesktopContractVector() {
        assertEquals("37f78495c5b244fdd53a9b6441eb50bc0d34807729a52b1e72b583b23cdb4c5f", advertisement().digest())
    }

    @Test fun rejectsLegacyOrPartialCapabilities() {
        for ((key, value) in listOf("transport_version" to 0, "transport_version" to true,
                                    "multipath" to false, "chunk_acks" to false,
                                    "supported_brokers" to JSONArray(listOf("emqx")))) {
            assertThrows(IllegalArgumentException::class.java) {
                MqttRouteAdvertisement.parseVerified(advertisement().toWire().put(key, value), sender, receiver, 1000)
            }
        }
    }

    @Test fun rejectsWrongIdentityDirection() {
        assertThrows(IllegalArgumentException::class.java) {
            MqttRouteAdvertisement.parseVerified(advertisement().toWire(), receiver, sender, 1000)
        }
    }

    @Test fun rejectsAmbiguousCountersAndInvalidReceiveLists() {
        for ((key, value) in listOf("route_epoch" to true, "route_epoch" to 1.0, "route_epoch" to 0,
                                    "route_epoch" to 9_007_199_254_740_992L,
                                    "expires_at_ms" to 999, "expires_at_ms" to 1_000_000,
                                    "max_encoded_packet_bytes" to 0, "max_encoded_packet_bytes" to 1_048_577,
                                    "resume_id" to "bad", "receive_brokers" to JSONArray(listOf("emqx", "emqx")),
                                    "receive_brokers" to JSONArray(listOf("unknown")), "receive_brokers" to "emqx")) {
            assertThrows(IllegalArgumentException::class.java) {
                MqttRouteAdvertisement.parseVerified(advertisement().toWire().put(key, value), sender, receiver, 1000)
            }
        }
    }

    @Test fun emptyReceiveCollectionWithdrawsPaths() {
        val value = advertisement().copy(receiveBrokers = emptySet())
        assertEquals(emptySet<String>(), MqttRouteAdvertisement.parseVerified(value.toWire(), sender, receiver, 1000).receiveBrokers)
    }

    @Test fun brokerEnumerationOrderDoesNotChangeDigest() {
        val value = advertisement()
        val wire = value.toWire().put("receive_brokers", JSONArray(value.receiveBrokers.sortedDescending()))
            .put("supported_brokers", JSONArray(value.receiveBrokers.sortedDescending()))
        assertEquals(value.digest(), MqttRouteAdvertisement.parseVerified(wire, sender, receiver, 1000).digest())
    }

    @Test fun expiredResumeIsNeverRestoredAsCurrent() {
        assertThrows(IllegalArgumentException::class.java) {
            MqttRouteAdvertisement.parseVerified(advertisement().toWire(), sender, receiver, 301_000)
        }
    }
}
