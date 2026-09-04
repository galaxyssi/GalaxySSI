package com.galaxyssi.chat.voice.asr.local

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

internal object CompactWhisperQnnFeatureExtractor {
    fun extract(modelDirectory: File, melBins: Int, pcm16: ShortArray, offset: Int, length: Int): FloatBuffer {
        require(melBins == 80)
        require(offset >= 0 && length > 0 && offset <= pcm16.size - length)
        val pcm = ByteBuffer.allocateDirect(length * Short.SIZE_BYTES).order(ByteOrder.nativeOrder())
        pcm.asShortBuffer().put(pcm16, offset, length)
        val output = ByteBuffer.allocateDirect(melBins * MEL_FRAMES * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
        val filters = File(modelDirectory.canonicalFile, "mel_filters.bin").canonicalFile
        require(filters.parentFile == modelDirectory.canonicalFile && filters.isFile && filters.canRead())
        check(nativeExtract(filters.path, pcm, length, output)) { "QNN Whisper Log-Mel extraction failed" }
        return output.asFloatBuffer().apply { position(0) }
    }

    private external fun nativeExtract(
        melFilterPath: String,
        pcm16: ByteBuffer,
        sampleCount: Int,
        output: ByteBuffer
    ): Boolean

    private const val MEL_FRAMES = 3_000

    init {
        System.loadLibrary("galaxyssi_asr")
    }
}
