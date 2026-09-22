package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchPeerAudioTest {
    @Test fun chunkedVoiceIsBoundAndSurvivesReload() {
        val context = InstrumentationRegistry.getInstrumentation().context
        assertTrue(context.packageName.endsWith(".test"))
        GalaxySSICrypto.initialize(context)
        val local = GalaxySSICrypto.localGalaxySSIId()
        val remote = "voice-test-${System.nanoTime()}"
        val route = "0123456789abcdef0123456789abcdef"
        val packets = mutableListOf<JSONObject>()
        val sender = WatchPeerAudio(context) { _, packet -> packets += packet }
        val original = ByteArray(300_123) { (it % 251).toByte() }
        val payload = WatchPeerProtocol.outgoing(remote, local, route, "")
        val descriptor = sender.prepare(local, payload, original, 12_000)
        val receipts = mutableListOf<JSONObject>()
        val receiver = WatchPeerAudio(context) { _, packet -> receipts += packet }
        val id = descriptor.getString("transfer_id")
        receiver.accept(remote, route, packets[0])
        assertNull(receiver.read(remote, id))
        val corrupt = JSONObject(packets[1].toString()).put("chunk_sha256", "0".repeat(64))
        assertTrue(runCatching { receiver.accept(remote, route, corrupt) }.isFailure)
        assertTrue(runCatching { receiver.accept("wrong-peer", route, packets[1]) }.isFailure)
        packets.drop(1).reversed().forEach { receiver.accept(remote, route, it) }
        assertEquals("stored", receipts.last().getString("status"))
        assertArrayEquals(original, WatchPeerAudio(context) { _, _ -> }.read(remote, id))
        assertNull(receiver.read("wrong-peer", id))
        assertTrue(runCatching { sender.prepare(local, payload, ByteArray(WatchPeerAudio.LIMIT + 1), 1000) }.isFailure)
    }
}
