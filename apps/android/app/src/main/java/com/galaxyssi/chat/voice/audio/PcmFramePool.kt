package com.galaxyssi.chat.voice.audio

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue

internal data class PcmFrameStorage(
    val samples: ShortArray,
    val pcm16: ByteBuffer
)

internal class PcmFramePool(
    frameSamples: Int,
    poolSize: Int
) {
    private val buffers = ArrayBlockingQueue<PcmFrameStorage>(poolSize).apply {
        repeat(poolSize) {
            offer(PcmFrameStorage(
                samples = ShortArray(frameSamples),
                pcm16 = ByteBuffer.allocateDirect(frameSamples * PCM16_BYTES_PER_SAMPLE)
                    .order(ByteOrder.LITTLE_ENDIAN)
            ))
        }
    }

    fun acquire(): PcmFrameStorage? = buffers.poll()

    fun release(buffer: PcmFrameStorage) {
        buffer.samples.fill(0)
        buffer.pcm16.clear()
        while (buffer.pcm16.hasRemaining()) buffer.pcm16.put(0)
        buffer.pcm16.clear()
        buffers.offer(buffer)
    }

    private companion object {
        const val PCM16_BYTES_PER_SAMPLE = 2
    }
}
