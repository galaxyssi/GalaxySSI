package com.signalasi.chat.voice.asr.local

import android.content.Context
import android.util.Log
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
            val directory = stage(QnnAsrPreparationStage.MODEL_VALIDATION) {
                File(
                    WhisperLargeTurboAsrEngine.FileModelDirectoryValidator().validate(modelDirectory.path)
                ).canonicalFile
            }
            val wrappers = stage(QnnAsrPreparationStage.CONTEXT_WRAPPERS) {
                WhisperQnnContextAssetInstaller(
                    AndroidQnnContextAssetSource(context.assets)
                ).ensureInstalled(directory)
            }
            val tokenizer = stage(QnnAsrPreparationStage.TOKENIZER) {
                WhisperTiktokenTokenizer.load(
                    File(directory, "tokenizer.tiktoken"),
                    File(directory, "generation_config.json")
                )
            }
            val nativeLibraries = stage(QnnAsrPreparationStage.PROVIDER_LIBRARY) {
                val nativeLibraryDirectory = File(context.applicationInfo.nativeLibraryDir).canonicalFile
                QnnNativeLibraries(
                    provider = requireNativeLibrary(nativeLibraryDirectory, QNN_PROVIDER_LIBRARY),
                    htpBackend = requireNativeLibrary(nativeLibraryDirectory, QNN_HTP_BACKEND_LIBRARY)
                )
            }
            val network = stage(QnnAsrPreparationStage.NETWORK) {
                OrtWhisperQnnNetwork.open(
                    directory,
                    wrappers,
                    tokenizer.generation,
                    nativeLibraries.provider,
                    nativeLibraries.htpBackend,
                    nanoTime
                )
            }
            try {
                val runtime = WhisperLargeTurboQnnRuntime(network, WhisperGreedyTranscriber(network, tokenizer))
                stage(QnnAsrPreparationStage.WARM_UP) { runtime.warmUp() }
                return runtime
            } catch (error: Throwable) {
                network.close()
                throw error
            }
        }

        private inline fun <T> stage(stage: QnnAsrPreparationStage, block: () -> T): T = try {
            block()
        } catch (error: Throwable) {
            val staged = if (error is QnnAsrPreparationException) error else {
                QnnAsrPreparationException(stage, error)
            }
            Log.e(TAG, staged.message, staged)
            throw staged
        }

        private fun requireNativeLibrary(directory: File, name: String): File =
            File(directory, name).canonicalFile.also { library ->
                require(library.isFile && library.canRead()) { "$name is unavailable" }
            }

        private const val TAG = "SignalASIQnnAsr"
        private const val QNN_PROVIDER_LIBRARY = "libonnxruntime_providers_qnn.so"
        private const val QNN_HTP_BACKEND_LIBRARY = "libQnnHtp.so"
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

private data class QnnNativeLibraries(
    val provider: File,
    val htpBackend: File
)

internal enum class QnnAsrPreparationStage(val code: String) {
    MODEL_VALIDATION("model_validation"),
    CONTEXT_WRAPPERS("context_wrappers"),
    TOKENIZER("tokenizer"),
    PROVIDER_LIBRARY("provider_library"),
    NETWORK("network"),
    WARM_UP("warm_up")
}

internal class QnnAsrPreparationException(
    val stage: QnnAsrPreparationStage,
    cause: Throwable
) : IllegalStateException(
    "QNN ASR ${stage.code} failed: ${cause.javaClass.simpleName}: " +
        cause.message.orEmpty().ifBlank { "unknown error" }.take(MAX_DETAIL_CHARS),
    cause
) {
    companion object {
        private const val MAX_DETAIL_CHARS = 320
    }
}
