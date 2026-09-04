package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class GalaxySSIMqttWireChunkingTest {
    private fun wirePayload(size: Int = 180_000): String =
        JSONObject()
            .put("scheme", "signal")
            .put("from", "galaxyssi:phone")
            .put("to", "desktop_test")
            .put("body", "x".repeat(size))
            .toString()

    @Test
    fun smallEncryptedWirePayloadRemainsDirect() {
        val wire = wirePayload(100)
        assertEquals(listOf(wire), GalaxySSIMqttWireChunking.encode(wire))
        assertNull(GalaxySSIMqttWireChunking.permanentRejectionReason(wire))
    }

    @Test
    fun payloadBelowLargestWireBucketRemainsDirect() {
        val wire = wirePayload(50_000)

        val packets = GalaxySSIMqttWireChunking.encode(wire)

        assertEquals(1, packets.size)
        assertEquals(wire, packets.single())
        assertNull(GalaxySSIMqttWireChunking.permanentRejectionReason(wire))
    }

    @Test
    fun fourHundredEightyThreeKibPayloadUsesOneMqttPacket() {
        val wire = wirePayload(483 * 1024)

        val packets = GalaxySSIMqttWireChunking.encode(wire)

        assertEquals(1, packets.size)
        assertEquals(wire, packets.single())
    }

    @Test
    fun oversizedPayloadIsClassifiedAsPermanentBeforeRetry() {
        val wire = wirePayload(GalaxySSIMqttWireChunking.MAX_REASSEMBLED_BYTES + 1)

        assertEquals(
            "MQTT wire payload exceeds reassembly limit",
            GalaxySSIMqttWireChunking.permanentRejectionReason(wire)
        )
    }

    @Test
    fun excessiveChunkCountIsClassifiedAsPermanentBeforeRetry() {
        val wire = wirePayload(2_000)

        assertEquals(
            "MQTT wire payload requires too many chunks",
            GalaxySSIMqttWireChunking.permanentRejectionReason(
                wire,
                directLimitBytes = 1,
                chunkDataBytes = 1
            )
        )
    }

    @Test
    fun largePayloadRoundTripsOutOfOrderWithDuplicates() {
        val wire = wirePayload(700_000)
        val packets = GalaxySSIMqttWireChunking.encode(wire)
        assertEquals(6, packets.size)
        assertEquals(
            GalaxySSIMqttWireChunking.DEFAULT_CHUNK_DATA_BYTES,
            Base64.getDecoder().decode(JSONObject(packets.first()).getString("data")).size
        )
        assertTrue(
            packets.all {
                it.toByteArray(Charsets.UTF_8).size <= GalaxySSIMqttWireChunking.MAX_PACKET_BYTES
            }
        )
        val assembler = GalaxySSIMqttChunkAssembler()
        val decoded = packets.map(::JSONObject)
        assertNull(assembler.accept("route", decoded.last()))
        assertNull(assembler.accept("route", decoded.last()))
        var result: String? = null
        decoded.dropLast(1).forEach { result = assembler.accept("route", it) }
        assertEquals(wire, result)
    }

    @Test
    fun receiverStillAcceptsLegacy24KibChunks() {
        val wire = wirePayload()
        val packets = GalaxySSIMqttWireChunking.encode(
            wire,
            directLimitBytes = 1,
            chunkDataBytes = 24 * 1024
        )
        val assembler = GalaxySSIMqttChunkAssembler()
        var result: String? = null

        packets.forEach { result = assembler.accept("route", JSONObject(it)) }

        assertEquals(wire, result)
    }

    @Test(expected = IllegalArgumentException::class)
    fun modifiedChunkIsRejectedBeforeReassembly() {
        val packet = JSONObject(GalaxySSIMqttWireChunking.encode(wirePayload(700_000)).first())
        val chunk = Base64.getDecoder().decode(packet.getString("data"))
        chunk[0] = (chunk[0].toInt() xor 1).toByte()
        packet.put("data", Base64.getEncoder().encodeToString(chunk))
        GalaxySSIMqttChunkAssembler().accept("route", packet)
    }

    @Test(expected = IllegalArgumentException::class)
    fun modifiedTransferIsRejectedByWholePayloadHash() {
        val packets = GalaxySSIMqttWireChunking.encode(wirePayload(700_000)).map(::JSONObject)
        val last = packets.last()
        val chunk = Base64.getDecoder().decode(last.getString("data"))
        chunk[chunk.lastIndex] = (chunk.last().toInt() xor 1).toByte()
        last.put("data", Base64.getEncoder().encodeToString(chunk))
        last.put("chunk_sha256", GalaxySSIMqttWireChunking.sha256(chunk))
        val assembler = GalaxySSIMqttChunkAssembler()
        packets.forEach { assembler.accept("route", it) }
    }
}
