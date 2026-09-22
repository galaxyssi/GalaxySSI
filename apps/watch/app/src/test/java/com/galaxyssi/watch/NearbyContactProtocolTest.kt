package com.galaxyssi.watch

import com.galaxyssi.chat.NearbyContactProtocol as P
import org.junit.Assert.*
import org.junit.Test

class NearbyContactProtocolTest {
    @Test fun reassemblesBleAndNfcChunksIncludingUnicode() {
        val source = "{邀请:Galaxy Watch5 Pro · EV1W}".repeat(35)
        for (size in listOf(14, 160)) {
            val reader = P.Reader(); var result: String? = null
            while (result == null) result = reader.accept(P.chunk(source.toByteArray(Charsets.UTF_8), reader.offset, size))
            assertEquals(source, result)
            assertEquals(6, P.code(result).length)
            assertEquals(P.code(source), P.code(result))
        }
    }
    @Test fun rejectsReplayReorderingAndOversize() {
        val reader = P.Reader(); val payload = ByteArray(100)
        reader.accept(P.chunk(payload, 0, 14))
        assertTrue(runCatching { reader.accept(P.chunk(payload, 0, 14)) }.isFailure)
        assertTrue(runCatching { reader.accept(P.chunk(payload, 30, 14)) }.isFailure)
        assertTrue(runCatching { P.chunk(ByteArray(P.MAX_BYTES + 1), 0) }.isFailure)
        assertTrue(runCatching { reader.accept(P.offset(Int.MAX_VALUE) + P.offset(14) + byteArrayOf(1)) }.isFailure)
        assertTrue(runCatching { P.chunk(payload, -1) }.isFailure)
    }
}
