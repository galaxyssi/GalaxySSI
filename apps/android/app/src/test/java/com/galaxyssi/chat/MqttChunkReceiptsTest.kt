package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MqttChunkReceiptsTest {
    private fun query(count: Int = 9) = MqttChunkReceipts.Query("a".repeat(64), "b".repeat(64), count, "c".repeat(32))

    @Test fun manifestMatchesDesktopGoldenIncludingUtf8Endpoints() {
        val part = JSONObject().put("scheme", "signal-chunk").put("transfer_id", "a".repeat(64)).put("sha256", "a".repeat(64))
            .put("chunk_count", 2).put("total_bytes", 7).put("chunk_index", 0).put("from", "\u624b\u673a\ud83d\ude00").put("to", "desktop")
            .put("chunk_sha256", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad").put("data", "YWJj")
        val chunk = MqttChunkManifest.parse(part)
        assertEquals("eee0631bb0d8524c203df7990e983fbfdfabfaddf73c6fb4febf67a06ee30a28", chunk.manifestHash)
        val request = MqttChunkReceipts.Query(chunk.transfer, chunk.manifestHash, 2, "c".repeat(32))
        assertEquals(request, MqttChunkReceipts.fromChunk(part.put(MqttChunkReceipts.FIELD, request.wire())))
        assertThrows(IllegalArgumentException::class.java) {
            MqttChunkReceipts.fromChunk(part.put("to", "another"))
        }
    }

    @Test fun bitmapMatchesDesktopLittleEndianGolden() {
        val state = query().response("d".repeat(32), 3, listOf(0, 7, 8))
        assertEquals("gQE=", state.getString("stored_bitmap"))
        assertArrayEquals(byteArrayOf(0x81.toByte(), 1), MqttChunkReceipts.parseState(state).bitmap)
        assertEquals("////////////////", query(96).response("d".repeat(32), 1, (0 until 96).toList()).getString("stored_bitmap"))
    }

    @Test fun rejectsWrongSizeNonCanonicalPaddingAndSpareBits() {
        for (encoded in listOf("AQ==", "AQE", "AQE=\n", "AQI=", "AQF=", "!!!!", "AQEA")) {
            assertThrows(IllegalArgumentException::class.java) {
                MqttChunkReceipts.parseState(query().response("d".repeat(32), 1, listOf(0)).put("stored_bitmap", encoded))
            }
        }
    }

    @Test fun onlyEmptyUnknownStoreCanUseZeroEpoch() {
        assertArrayEquals(ByteArray(2), MqttChunkReceipts.parseState(query().response("0".repeat(32), 0, emptyList())).bitmap)
        assertThrows(IllegalArgumentException::class.java) { query().response("0".repeat(32), 1, emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { query().response("0".repeat(32), 0, listOf(0)) }
    }

    @Test fun countersAndIdentitiesAreStrict() {
        for ((key, value) in listOf("chunk_count" to "9", "chunk_count" to false, "chunk_count" to 97,
            "version" to 1.0, "request_id" to "z".repeat(32), "transfer_id" to "A".repeat(64))) {
            assertThrows(IllegalArgumentException::class.java) { MqttChunkReceipts.parse(query().wire().put(key, value)) }
        }
        for (value in listOf(-1L, Long.MAX_VALUE, "1", 1.0, false)) {
            assertThrows(IllegalArgumentException::class.java) {
                MqttChunkReceipts.parseState(query().response("d".repeat(32), 1, listOf(0)).put("revision", value))
            }
        }
    }

    @Test fun queryIsNotAReceiptAndBitsCannotEscapeManifest() {
        assertThrows(IllegalArgumentException::class.java) { MqttChunkReceipts.parseState(query().wire()) }
        assertThrows(IllegalArgumentException::class.java) { query().response("d".repeat(32), 1, listOf(-1)) }
        assertThrows(IllegalArgumentException::class.java) { query().response("d".repeat(32), 1, listOf(9)) }
        assertNotEquals(MqttChunkReceipts.newRequest(), MqttChunkReceipts.newRequest())
    }
}
