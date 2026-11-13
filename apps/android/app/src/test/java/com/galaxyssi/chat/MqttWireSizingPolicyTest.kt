package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MqttWireSizingPolicyTest {
    private fun wire(size: Int) = JSONObject().put("scheme", "signal").put("from", "phone")
        .put("to", "desktop").put("body", "x".repeat(size)).toString()

    @Test fun textRemainsDirect() {
        val value = wire(1024)
        assertEquals(listOf(value), MqttWireSizingPolicy.encode(value))
    }

    @Test fun attachmentCiphertextUsesBoundedAuthenticatedFragments() {
        val secret = GalaxySSILinkProtocol.newLinkSecret()
        for (size in listOf(61_440, 87_419, 349_563, 470_000, 699_088, 2_096_900)) {
            val value = wire(size)
            val parts = MqttWireSizingPolicy.encode(value)
            assertTrue(parts.size > 1)
            assertTrue(parts.size <= MqttChunkManifest.MAX_COUNT)
            val assembler = GalaxySSIMqttChunkAssembler()
            var restored: String? = null
            parts.reversed().forEach { part ->
                val payload = JSONObject(part)
                val chunk = MqttChunkManifest.parse(payload)
                val query = MqttChunkReceipts.Query(chunk.transfer, chunk.manifestHash, chunk.count, MqttChunkReceipts.newRequest())
                payload.put(MqttChunkReceipts.FIELD, query.wire())
                val sealed = GalaxySSILinkProtocol.sealWirePacket(payload.toString(), secret)
                assertTrue("Encoded packet grew beyond 64 KiB privacy bucket", sealed.length <= 87_419)
                restored = assembler.accept("pair", payload)
            }
            assertEquals(value, restored)
        }
    }

    @Test fun existingLargeFragmentLayoutDoesNotChangeAfterUpgrade() {
        val value = wire(700_000)
        assertEquals(GalaxySSIMqttWireChunking.encode(value),
            MqttWireSizingPolicy.encode(value, MqttChunkManifest.DATA_BYTES))
    }

    @Test fun resumedSmallLayoutHasStableTransferIdentityAndBytes() {
        val value = wire(470_000)
        assertEquals(MqttWireSizingPolicy.encode(value), MqttWireSizingPolicy.encode(value, MqttWireSizingPolicy.CHUNK_BYTES))
    }
}
