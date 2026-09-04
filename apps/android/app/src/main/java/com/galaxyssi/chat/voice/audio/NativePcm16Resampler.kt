package com.galaxyssi.chat.voice.audio

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

internal class NativePcm16Resampler private constructor(
    private var handle: Long
) : AutoCloseable {
    private val closed = AtomicBoolean(false)

    fun process(
        input: ByteBuffer,
        inputSampleCount: Int,
        output: ByteBuffer,
        outputCapacitySamples: Int
    ): Int {
        require(input.isDirect && output.isDirect)
        require(inputSampleCount > 0 && inputSampleCount <= input.remaining() / PCM16_BYTES_PER_SAMPLE)
        require(outputCapacitySamples > 0 && outputCapacitySamples <= output.capacity() / PCM16_BYTES_PER_SAMPLE)
        val inputView = input.slice().order(ByteOrder.nativeOrder())
        val outputView = output.duplicate().order(ByteOrder.nativeOrder()).apply { clear() }
        return withHandle {
            NativePcm16ResamplerBridge.nativeProcess(
                it,
                inputView,
                inputSampleCount,
                outputView,
                outputCapacitySamples
            )
        }.also { produced ->
            check(produced in 0..outputCapacitySamples) { "Native ASR resampler returned an invalid sample count" }
            output.position(0)
            output.limit(produced * PCM16_BYTES_PER_SAMPLE)
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        val current = synchronized(this) { handle.also { handle = 0L } }
        if (current != 0L) NativePcm16ResamplerBridge.nativeDestroy(current)
    }

    private inline fun <T> withHandle(block: (Long) -> T): T {
        check(!closed.get()) { "Native ASR resampler is closed" }
        val current = synchronized(this) { handle }
        check(current != 0L) { "Native ASR resampler is closed" }
        return block(current)
    }

    companion object {
        private const val PCM16_BYTES_PER_SAMPLE = 2

        fun open(inputSampleRateHz: Int): NativePcm16Resampler {
            val handle = NativePcm16ResamplerBridge.nativeCreate(inputSampleRateHz)
            check(handle != 0L) { "Native ASR resampler could not be created" }
            return NativePcm16Resampler(handle)
        }
    }
}

private object NativePcm16ResamplerBridge {
    init {
        System.loadLibrary("galaxyssi_asr")
    }

    external fun nativeCreate(inputSampleRateHz: Int): Long
    external fun nativeProcess(
        handle: Long,
        input: ByteBuffer,
        inputSampleCount: Int,
        output: ByteBuffer,
        outputCapacitySamples: Int
    ): Int
    external fun nativeDestroy(handle: Long)
}
