package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ShortBuffer

class Float16CodecTest {
    @Test
    fun finiteValuesRoundTripWithinHalfPrecision() {
        listOf(0.0F, -0.0F, 1.0F, -1.5F, -100.0F, 0.3333F, 65_504.0F).forEach { value ->
            val decoded = Float16Codec.decode(Float16Codec.encode(value))
            val tolerance = maxOf(0.0005F, kotlin.math.abs(value) * 0.001F)
            assertEquals(value, decoded, tolerance)
        }
    }

    @Test
    fun subnormalInfinityAndNanAreHandled() {
        assertEquals(5.9604645e-8F, Float16Codec.decode(0x0001.toShort()), 1.0e-12F)
        assertEquals(Float.POSITIVE_INFINITY, Float16Codec.decode(0x7c00.toShort()))
        assertTrue(Float16Codec.decode(0x7e00.toShort()).isNaN())
    }

    @Test
    fun argmaxHonorsTokenAndTimestampSuppression() {
        val logits = ShortBuffer.allocate(7)
        listOf(-2F, 4F, 3F, 8F, 12F, 11F, 10F).forEachIndexed { index, value ->
            logits.put(index, Float16Codec.encode(value))
        }

        assertEquals(4, Float16Codec.argmax(logits, 7))
        assertEquals(3, Float16Codec.argmax(logits, 7, setOf(4, 5, 6)))
        assertEquals(3, Float16Codec.argmax(logits, 7, timestampStartToken = 4))
        assertEquals(2, Float16Codec.argmax(logits, 7, setOf(1, 3), timestampStartToken = 4))
    }
}
