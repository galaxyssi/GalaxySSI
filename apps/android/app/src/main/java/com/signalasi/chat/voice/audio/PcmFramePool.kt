package com.signalasi.chat.voice.audio

import java.util.concurrent.ArrayBlockingQueue

internal class PcmFramePool(
    frameSamples: Int,
    poolSize: Int
) {
    private val buffers = ArrayBlockingQueue<ShortArray>(poolSize).apply {
        repeat(poolSize) { offer(ShortArray(frameSamples)) }
    }

    fun acquire(): ShortArray? = buffers.poll()

    fun release(buffer: ShortArray) {
        buffer.fill(0)
        buffers.offer(buffer)
    }
}
