package com.galaxyssi.chat.voice.asr.local

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

internal enum class NativeFeatureWindowKind(val nativeValue: Long) {
    PARTIAL(1),
    FINAL(2),
    NO_SPEECH_FINAL(3);

    companion object {
        fun fromNative(value: Long): NativeFeatureWindowKind = entries.firstOrNull { it.nativeValue == value }
            ?: error("Native ASR frontend returned an unknown feature window")
    }
}

internal data class NativeFeatureWindow(
    val kind: NativeFeatureWindowKind,
    val startSample: Long,
    val endSample: Long,
    val segmentStartSample: Long,
    val endReason: Int
) {
    val final: Boolean
        get() = kind != NativeFeatureWindowKind.PARTIAL

    val durationMs: Long
        get() = ((endSample - segmentStartSample).coerceAtLeast(0L) * 1_000L) / SAMPLE_RATE_HZ

    private companion object {
        const val SAMPLE_RATE_HZ = 16_000L
    }
}

internal interface WhisperQnnAudioFrontend : AutoCloseable {
    fun start(): Boolean
    fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean
    fun stop()
    fun cancel()
    fun pause()
    fun resume(): Boolean
    fun updateRuntimePolicy(policy: AsrRuntimePolicy) = Unit
    fun waitForFeatures(output: ByteBuffer, timeoutMs: Int): NativeFeatureWindow?
}

internal fun interface WhisperQnnAudioFrontendFactory {
    fun open(modelDirectory: File, config: AsrConfig): WhisperQnnAudioFrontend
}

internal class NativeWhisperQnnAudioFrontend private constructor(
    private var handle: Long
) : WhisperQnnAudioFrontend {
    private val closed = AtomicBoolean(false)

    override fun start(): Boolean = withHandle(WhisperQnnNativeFrontendBridge::nativeStart)

    override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean {
        require(pcm.isDirect && sampleCount > 0 && sampleCount <= pcm.remaining() / PCM16_BYTES_PER_SAMPLE)
        val view = pcm.slice().order(ByteOrder.nativeOrder())
        return withHandle { WhisperQnnNativeFrontendBridge.nativePushPcm(it, view, sampleCount) }
    }

    override fun stop() = withHandle(WhisperQnnNativeFrontendBridge::nativeStop)

    override fun cancel() = withHandle(WhisperQnnNativeFrontendBridge::nativeCancel)

    override fun pause() = withHandle(WhisperQnnNativeFrontendBridge::nativePause)

    override fun resume(): Boolean = withHandle(WhisperQnnNativeFrontendBridge::nativeResume)

    override fun updateRuntimePolicy(policy: AsrRuntimePolicy) {
        withHandle {
            WhisperQnnNativeFrontendBridge.nativeUpdatePartialPolicy(
                it,
                policy.partialIntervalMs.toInt(),
                policy.emitIntermediateResults
            )
        }
    }

    override fun waitForFeatures(output: ByteBuffer, timeoutMs: Int): NativeFeatureWindow? {
        require(output.isDirect && output.capacity() >= MEL_BUFFER_BYTES)
        require(timeoutMs in 0..MAX_WAIT_MS)
        output.clear()
        val values = withHandle { WhisperQnnNativeFrontendBridge.nativeWaitForFeatures(it, output, timeoutMs) }
            ?: return null
        check(values.size == FEATURE_METADATA_VALUES)
        return NativeFeatureWindow(
            kind = NativeFeatureWindowKind.fromNative(values[0]),
            startSample = values[1],
            endSample = values[2],
            segmentStartSample = values[3],
            endReason = values[4].toInt()
        )
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        val current = synchronized(this) { handle.also { handle = 0L } }
        if (current != 0L) WhisperQnnNativeFrontendBridge.nativeDestroy(current)
    }

    private inline fun <T> withHandle(block: (Long) -> T): T {
        check(!closed.get()) { "Native ASR frontend is closed" }
        val current = synchronized(this) { handle }
        check(current != 0L) { "Native ASR frontend is closed" }
        return block(current)
    }

    companion object : WhisperQnnAudioFrontendFactory {
        const val MEL_BUFFER_BYTES = WhisperLargeTurboQnnContract.MEL_BINS *
            WhisperLargeTurboQnnContract.MEL_FRAMES * Float.SIZE_BYTES
        private const val PCM16_BYTES_PER_SAMPLE = 2
        private const val FEATURE_METADATA_VALUES = 5
        private const val MAX_WAIT_MS = 5_000

        override fun open(modelDirectory: File, config: AsrConfig): NativeWhisperQnnAudioFrontend {
            val melFilters = File(modelDirectory.canonicalFile, "mel_filters.bin").canonicalFile
            require(melFilters.parentFile == modelDirectory.canonicalFile && melFilters.isFile && melFilters.canRead())
            val handle = WhisperQnnNativeFrontendBridge.nativeCreate(
                melFilters.path,
                intArrayOf(
                    config.inputSampleRateHz,
                    35,
                    4,
                    config.endSilenceMs.toInt(),
                    config.minSegmentMs.toInt(),
                    config.maxSegmentMs.toInt(),
                    config.preRollMs.toInt(),
                    config.postRollMs.toInt(),
                    config.firstPartialDelayMs.toInt(),
                    config.updateIntervalMs.toInt(),
                    config.activeWindowMs.toInt(),
                    config.overlapMs.toInt(),
                    config.maxSegmentMs.toInt(),
                    if (config.emitsIntermediateResults) 1 else 0
                )
            )
            check(handle != 0L) { "Native ASR frontend could not be created" }
            return NativeWhisperQnnAudioFrontend(handle)
        }
    }
}

internal object WhisperQnnNativeFrontendBridge {
    init {
        System.loadLibrary("galaxyssi_asr")
    }

    external fun nativeCreate(melFilterPath: String, configValues: IntArray): Long
    external fun nativeStart(handle: Long): Boolean
    external fun nativePushPcm(handle: Long, pcm: ByteBuffer, sampleCount: Int): Boolean
    external fun nativeStop(handle: Long)
    external fun nativeCancel(handle: Long)
    external fun nativePause(handle: Long)
    external fun nativeResume(handle: Long): Boolean
    external fun nativeUpdatePartialPolicy(handle: Long, updateIntervalMs: Int, emitPartials: Boolean)
    external fun nativeWaitForFeatures(handle: Long, output: ByteBuffer, timeoutMs: Int): LongArray?
    external fun nativeDestroy(handle: Long)
}
