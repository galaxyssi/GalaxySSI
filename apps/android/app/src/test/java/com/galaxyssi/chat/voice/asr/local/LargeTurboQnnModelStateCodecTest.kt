package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LargeTurboQnnModelStateCodecTest {
    @Test
    fun persistedDownloadStateRoundTripsAcrossProcessRestarts() {
        val value = PersistedLargeTurboQnnModelState(
            state = LargeTurboQnnModelState(
                status = LargeTurboQnnModelStatus.DOWNLOADING,
                progress = 63,
                detail = "decoder.bin",
                resumed = true
            ),
            updatedAtMillis = 123_456L
        )

        assertEquals(value, LargeTurboQnnModelStateCodec.decode(LargeTurboQnnModelStateCodec.encode(value)))
    }

    @Test
    fun malformedOrUnknownStateIsRejected() {
        assertNull(LargeTurboQnnModelStateCodec.decode("not-json"))
        assertNull(LargeTurboQnnModelStateCodec.decode("{\"status\":\"FUTURE_STATE\",\"updated_at_ms\":1}"))
    }

    @Test
    fun untrustedPersistedFieldsAreBounded() {
        val decoded = LargeTurboQnnModelStateCodec.decode(
            "{\"status\":\"DOWNLOADING\",\"progress\":999," +
                "\"detail\":\"${"x".repeat(2_000)}\",\"resumed\":false,\"updated_at_ms\":-3}"
        )

        assertEquals(100, decoded?.state?.progress)
        assertEquals(1_024, decoded?.state?.detail?.length)
        assertEquals(0L, decoded?.updatedAtMillis)
    }
}
