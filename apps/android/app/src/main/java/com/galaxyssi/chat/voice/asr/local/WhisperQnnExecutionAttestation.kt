package com.galaxyssi.chat.voice.asr.local

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

enum class QnnExecutionVerification {
    CONFIGURED,
    ENCODER_EXECUTED,
    ENCODER_AND_DECODER_EXECUTED
}

enum class QnnLayerCountSource {
    QUALCOMM_TARGET_DEVICE_PROFILE
}

data class QnnExecutionAttestation(
    val executionProvider: String,
    val backendType: String,
    val verification: QnnExecutionVerification,
    val cpuFallbackDisabled: Boolean,
    val htpSharedMemoryEnabled: Boolean,
    val contextBinariesRestored: Boolean,
    val warmupCompleted: Boolean,
    val encoderExecutionCount: Long,
    val decoderExecutionCount: Long,
    val expectedEncoderNpuLayers: Int,
    val expectedDecoderNpuLayers: Int,
    val layerCountSource: QnnLayerCountSource
) {
    val fullHtpExecutionVerified: Boolean
        get() = verification == QnnExecutionVerification.ENCODER_AND_DECODER_EXECUTED &&
            cpuFallbackDisabled && contextBinariesRestored
}

internal interface QnnExecutionAttestationSource {
    fun executionAttestation(warmupCompleted: Boolean = false): QnnExecutionAttestation
}

internal class QnnExecutionAttestationTracker(
    private val htpSharedMemoryEnabled: Boolean
) : QnnExecutionAttestationSource {
    private val contextBinariesRestored = AtomicBoolean(false)
    private val encoderExecutionCount = AtomicLong(0L)
    private val decoderExecutionCount = AtomicLong(0L)

    fun markContextBinariesRestored() {
        contextBinariesRestored.set(true)
    }

    fun recordEncoderExecution() {
        encoderExecutionCount.incrementAndGet()
    }

    fun recordDecoderExecution() {
        decoderExecutionCount.incrementAndGet()
    }

    override fun executionAttestation(warmupCompleted: Boolean): QnnExecutionAttestation {
        val encoderCount = encoderExecutionCount.get()
        val decoderCount = decoderExecutionCount.get()
        val verification = when {
            encoderCount > 0L && decoderCount > 0L -> QnnExecutionVerification.ENCODER_AND_DECODER_EXECUTED
            encoderCount > 0L -> QnnExecutionVerification.ENCODER_EXECUTED
            else -> QnnExecutionVerification.CONFIGURED
        }
        return QnnExecutionAttestation(
            executionProvider = EXECUTION_PROVIDER,
            backendType = BACKEND_TYPE,
            verification = verification,
            cpuFallbackDisabled = true,
            htpSharedMemoryEnabled = htpSharedMemoryEnabled,
            contextBinariesRestored = contextBinariesRestored.get(),
            warmupCompleted = warmupCompleted,
            encoderExecutionCount = encoderCount,
            decoderExecutionCount = decoderCount,
            expectedEncoderNpuLayers = WhisperLargeTurboQnnContract.ENCODER_NPU_LAYERS,
            expectedDecoderNpuLayers = WhisperLargeTurboQnnContract.DECODER_NPU_LAYERS,
            layerCountSource = QnnLayerCountSource.QUALCOMM_TARGET_DEVICE_PROFILE
        )
    }

    private companion object {
        const val EXECUTION_PROVIDER = "QNNExecutionProvider"
        const val BACKEND_TYPE = "htp"
    }
}
