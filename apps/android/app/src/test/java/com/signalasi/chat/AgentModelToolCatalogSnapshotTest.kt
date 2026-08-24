package com.signalasi.chat

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
        val source = mutableListOf(descriptor("signalasi.test.read"))
        val snapshot = AgentModelToolCatalogSnapshot(CountingProtocol(), source)

        source.clear()

        assertEquals(listOf("signalasi.test.read"), snapshot.descriptors.map(AgentNativeToolDescriptor::id))
        assertEquals(1, snapshot.encoded.getJSONObject(0).getInt("count"))
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
