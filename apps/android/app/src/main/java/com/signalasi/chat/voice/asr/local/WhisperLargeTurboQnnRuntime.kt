package com.signalasi.chat.voice.asr.local

import android.content.Context
import java.io.File
import java.nio.FloatBuffer
import java.util.concurrent.atomic.AtomicBoolean

internal class WhisperLargeTurboQnnRuntime private constructor(
    private val network: WhisperQnnNetwork,
    private val transcriber: WhisperGreedyTranscriber
) : WhisperQnnTranscriberRuntime {
    private val closed = AtomicBoolean(false)
    private val inferenceLock = Any()
    @Volatile private var warmupCompleted = false

    fun transcribe(melFeatures: FloatArray, language: String = "zh", maxTokens: Int = 160): WhisperQnnTranscription =
        synchronized(inferenceLock) {
            check(!closed.get()) { "QNN Whisper runtime is closed" }
            attachExecutionAttestation(transcriber.transcribe(melFeatures, language, maxTokens))
        }

    override fun transcribe(
        melFeatures: FloatBuffer,
        language: String,
        maxTokens: Int
    ): WhisperQnnTranscription =
        synchronized(inferenceLock) {
            check(!closed.get()) { "QNN Whisper runtime is closed" }
            attachExecutionAttestation(transcriber.transcribe(melFeatures, language, maxTokens))
        }

    override fun close() {
        if (closed.compareAndSet(false, true)) network.close()
    }

    companion object {
        fun open(
            context: Context,
            modelDirectory: File,
            nanoTime: () -> Long = System::nanoTime
        ): WhisperLargeTurboQnnRuntime {
            val directory = File(
                WhisperLargeTurboAsrEngine.FileModelDirectoryValidator().validate(modelDirectory.path)
            ).canonicalFile
            val wrappers = WhisperQnnContextAssetInstaller(
                AndroidQnnContextAssetSource(context.assets)
            ).ensureInstalled(directory)
            val tokenizer = WhisperTiktokenTokenizer.load(
                File(directory, "tokenizer.tiktoken"),
                File(directory, "generation_config.json")
            )
            val network = OrtWhisperQnnNetwork.open(directory, wrappers, tokenizer.generation, nanoTime)
            try {
                val runtime = WhisperLargeTurboQnnRuntime(network, WhisperGreedyTranscriber(network, tokenizer))
                runtime.warmUp()
                return runtime
            } catch (error: Throwable) {
                network.close()
                throw error
            }
        }
    }

    private fun warmUp() {
        val silence = FloatArray(
            WhisperLargeTurboQnnContract.MEL_BINS * WhisperLargeTurboQnnContract.MEL_FRAMES
        ) { -1.5F }
        transcriber.transcribe(silence, "zh", 1)
        warmupCompleted = true
    }

    private fun attachExecutionAttestation(transcription: WhisperQnnTranscription): WhisperQnnTranscription {
        val source = network as? QnnExecutionAttestationSource ?: return transcription
        return transcription.copy(qnnExecution = source.executionAttestation(warmupCompleted))
    }
}
