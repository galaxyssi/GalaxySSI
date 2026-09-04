package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class AgentModelToolCatalogSnapshotTest {
    @Test
    fun `encodes a provider catalog once across model rounds`() {
        val protocol = CountingProtocol()
        val snapshot = AgentModelToolCatalogSnapshot(protocol, emptyList())

        val first = snapshot.encoded
        val second = snapshot.encoded

        assertSame(first, second)
        assertEquals(1, protocol.encodeCount)
    }

    @Test
    fun `freezes descriptors before the model loop starts`() {
        val source = mutableListOf(descriptor("galaxyssi.test.read"))
        val snapshot = AgentModelToolCatalogSnapshot(CountingProtocol(), source)

        source.clear()

        assertEquals(listOf("galaxyssi.test.read"), snapshot.descriptors.map(AgentNativeToolDescriptor::id))
        assertEquals(1, snapshot.encoded.getJSONObject(0).getInt("count"))
    }

    @Test
    fun `shares encoded catalogs with the same protocol and fingerprint`() {
        val protocol = CountingProtocol()
        val first = AgentModelToolCatalogSnapshot(protocol, listOf(descriptor("galaxyssi.test.read")), "digest-a")
        val second = AgentModelToolCatalogSnapshot(protocol, listOf(descriptor("galaxyssi.test.read")), "digest-a")

        assertSame(first.encoded, second.encoded)
        assertEquals(1, protocol.encodeCount)
    }

    @Test
    fun `does not share encoded catalogs across fingerprints`() {
        val protocol = CountingProtocol()
        val first = AgentModelToolCatalogSnapshot(protocol, emptyList(), "digest-b")
        val second = AgentModelToolCatalogSnapshot(protocol, emptyList(), "digest-c")

        first.encoded
        second.encoded

        assertEquals(2, protocol.encodeCount)
    }

    private fun descriptor(id: String) = AgentNativeToolDescriptor(
        id = id,
        version = "1.0.0",
        title = id,
        description = "Test read tool.",
        location = AgentNativeToolLocation.PHONE,
        inputSchema = AgentNativeJsonSchema.objectSchema(),
        outputSchema = AgentNativeJsonSchema.objectSchema(),
        risk = AgentNativeToolRisk.LOW,
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY
    )

    private class CountingProtocol : AgentModelToolProtocolAdapter {
        override val provider = AgentModelToolProvider.OPENAI_COMPATIBLE
        var encodeCount = 0

        override fun encodeToolCatalog(catalog: List<AgentNativeToolDescriptor>): JSONArray {
            encodeCount += 1
            return JSONArray().put(JSONObject().put("count", catalog.size))
        }

        override fun encodeConversation(messages: List<AgentModelMessage>) = JSONObject()

        override fun decodeResponse(
            responseJson: String,
            catalog: List<AgentNativeToolDescriptor>
        ) = error("Not used")
    }
}
