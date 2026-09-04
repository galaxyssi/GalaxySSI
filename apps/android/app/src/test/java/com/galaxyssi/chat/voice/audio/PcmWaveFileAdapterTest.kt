package com.galaxyssi.chat.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.ByteBuffer
import java.nio.ByteOrder

class PcmWaveFileAdapterTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun writesStandardMonoPcmWaveWithoutLeavingPartialFile() {
        val samples = shortArrayOf(-32_768, -1, 0, 1, 32_767)
        val file = PcmWaveFileAdapter.write(
            PcmSnapshot(samples, 16_000, true, 0, 5, 0, 5),
            temporaryFolder.root,
            "voice:test"
        )
        val bytes = file.readBytes()

        assertEquals("RIFF", bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII))
        assertEquals("WAVE", bytes.copyOfRange(8, 12).toString(Charsets.US_ASCII))
        assertEquals(16_000, leInt(bytes, 24))
        assertEquals(samples.size * 2, leInt(bytes, 40))
        assertFalse(temporaryFolder.root.resolve("voice_test.wav.partial").exists())
    }

    private fun leInt(bytes: ByteArray, offset: Int): Int =
        ByteBuffer.wrap(bytes, offset, 4).order(ByteOrder.LITTLE_ENDIAN).int
}
