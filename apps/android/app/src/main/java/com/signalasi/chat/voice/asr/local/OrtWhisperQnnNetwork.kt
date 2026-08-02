package com.signalasi.chat.voice.asr.local

import ai.onnxruntime.NodeInfo
import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtLoggingLevel
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicBoolean

internal class OrtWhisperQnnNetwork private constructor(
    private val environment: OrtEnvironment,
    private val encoderSession: OrtSession,
    private val decoderSession: OrtSession,
    private val generation: WhisperGenerationTokens,
    private val nanoTime: () -> Long
) : WhisperQnnNetwork {
    private val closed = AtomicBoolean(false)
    private val arena = OrtTensorArena(environment)
    private val encoderInput = arena.create(WhisperLargeTurboQnnContract.encoder.inputs.single())
    private val crossCache = WhisperLargeTurboQnnContract.encoder.outputs.associateWith(arena::create)
    private val inputId = arena.create(WhisperLargeTurboQnnContract.decoder.inputs.first { it.name == "input_ids" })
    private val positionId = arena.create(WhisperLargeTurboQnnContract.decoder.inputs.first { it.name == "position_ids" })
    private val attentionMask = arena.create(
        WhisperLargeTurboQnnContract.decoder.inputs.first { it.name == "attention_mask" }
    )
    private val logits = arena.create(WhisperLargeTurboQnnContract.decoder.outputs.first { it.name == "logits" })
    private val selfCacheSlots = (0 until WhisperLargeTurboQnnContract.DECODER_LAYERS).flatMap { layer ->
        listOf(
            SelfCacheSlot(
                "k_cache_self_${layer}_in",
                "k_cache_self_${layer}_out",
                arena.create(WhisperLargeTurboQnnContract.decoder.inputs.first { it.name == "k_cache_self_${layer}_in" }),
                arena.create(WhisperLargeTurboQnnContract.decoder.outputs.first { it.name == "k_cache_self_${layer}_out" })
            ),
            SelfCacheSlot(
                "v_cache_self_${layer}_in",
                "v_cache_self_${layer}_out",
                arena.create(WhisperLargeTurboQnnContract.decoder.inputs.first { it.name == "v_cache_self_${layer}_in" }),
                arena.create(WhisperLargeTurboQnnContract.decoder.outputs.first { it.name == "v_cache_self_${layer}_out" })
            )
        )
    }
    private val encoderInputs = linkedMapOf("input_features" to encoderInput.tensor)
    private val encoderOutputs = LinkedHashMap<String, OnnxTensor>()
    private val decoderInputs = LinkedHashMap<String, OnnxTensor>()
    private val decoderOutputs = LinkedHashMap<String, OnnxTensor>()

    init {
        WhisperLargeTurboQnnContract.encoder.validate(encoderSession.inputMetadata(), encoderSession.outputMetadata())
        WhisperLargeTurboQnnContract.decoder.validate(decoderSession.inputMetadata(), decoderSession.outputMetadata())
        crossCache.forEach { (contract, tensor) -> encoderOutputs[contract.name] = tensor.tensor }
        bindDecoderTensors()
        resetDecoder()
    }

    override fun encode(melFeatures: FloatArray): Long = synchronized(this) {
        checkOpen()
        require(melFeatures.size == encoderInput.contract.elementCount)
        val target = encoderInput.buffer.asShortBuffer()
        melFeatures.forEachIndexed { index, value -> target.put(index, Float16Codec.encode(value)) }
        val started = nanoTime()
        encoderSession.run(encoderInputs, encoderOutputs).use { }
        (nanoTime() - started).coerceAtLeast(0L)
    }

    override fun resetDecoder() = synchronized(this) {
        checkOpen()
        selfCacheSlots.forEach(SelfCacheSlot::clear)
        attentionMask.clear(Float16Codec.encode(ATTENTION_MASK_NEGATIVE))
        inputId.clear()
        positionId.clear()
        logits.clear()
        bindDecoderTensors()
    }

    override fun decode(
        inputToken: Int,
        position: Int,
        selection: WhisperDecoderSelection
    ): WhisperQnnDecoderStep = synchronized(this) {
        checkOpen()
        require(inputToken in 0 until WhisperLargeTurboQnnContract.VOCABULARY_SIZE)
        require(position in 0 until WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS)
        inputId.buffer.asIntBuffer().put(0, inputToken)
        positionId.buffer.asIntBuffer().put(0, position)
        attentionMask.buffer.asShortBuffer().put(
            WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS - position - 1,
            Float16Codec.encode(0.0F)
        )
        val started = nanoTime()
        decoderSession.run(decoderInputs, decoderOutputs).use { }
        val elapsed = (nanoTime() - started).coerceAtLeast(0L)
        val suppressed = when (selection) {
            WhisperDecoderSelection.UNRESTRICTED -> emptySet()
            WhisperDecoderSelection.FIRST_TEXT_TOKEN -> generation.suppressTokens + generation.beginSuppressTokens
            WhisperDecoderSelection.TEXT_TOKEN -> generation.suppressTokens
        }
        val nextToken = Float16Codec.argmax(
            logits.buffer.asShortBuffer(),
            WhisperLargeTurboQnnContract.VOCABULARY_SIZE,
            suppressed,
            if (selection == WhisperDecoderSelection.UNRESTRICTED) null else generation.timestampStart
        )
        selfCacheSlots.forEach(SelfCacheSlot::swap)
        bindDecoderTensors()
        WhisperQnnDecoderStep(nextToken, elapsed)
    }

    override fun close() = synchronized(this) {
        if (!closed.compareAndSet(false, true)) return
        runCatching { decoderSession.close() }
        runCatching { encoderSession.close() }
        arena.close()
    }

    private fun bindDecoderTensors() {
        decoderInputs.clear()
        decoderInputs["input_ids"] = inputId.tensor
        decoderInputs["attention_mask"] = attentionMask.tensor
        selfCacheSlots.forEach { decoderInputs[it.inputName] = it.read.tensor }
        crossCache.forEach { (contract, tensor) -> decoderInputs[contract.name] = tensor.tensor }
        decoderInputs["position_ids"] = positionId.tensor

        decoderOutputs.clear()
        decoderOutputs["logits"] = logits.tensor
        selfCacheSlots.forEach { decoderOutputs[it.outputName] = it.write.tensor }
    }

    private fun checkOpen() = check(!closed.get()) { "QNN Whisper network is closed" }

    private data class SelfCacheSlot(
        val inputName: String,
        val outputName: String,
        var read: OrtPersistentTensor,
        var write: OrtPersistentTensor
    ) {
        fun clear() {
            read.clear()
            write.clear()
        }

        fun swap() {
            val previousRead = read
            read = write
            write = previousRead
        }
    }

    companion object {
        private const val ATTENTION_MASK_NEGATIVE = -100.0F
        private const val EP_NAME = "QNNExecutionProvider"
        private const val EP_LIBRARY = "libonnxruntime_providers_qnn.so"

        fun open(
            modelDirectory: File,
            wrapperFiles: Map<String, File>,
            generation: WhisperGenerationTokens,
            nanoTime: () -> Long = System::nanoTime
        ): OrtWhisperQnnNetwork {
            val environment = QnnOrtEnvironment.environment()
            val encoderModel = requireNotNull(wrapperFiles[WhisperLargeTurboQnnContract.encoder.wrapperModelName])
            val decoderModel = requireNotNull(wrapperFiles[WhisperLargeTurboQnnContract.decoder.wrapperModelName])
            require(encoderModel.parentFile?.canonicalFile == modelDirectory.canonicalFile)
            require(decoderModel.parentFile?.canonicalFile == modelDirectory.canonicalFile)
            val encoder = createSession(environment, encoderModel)
            try {
                val decoder = createSession(environment, decoderModel)
                return OrtWhisperQnnNetwork(environment, encoder, decoder, generation, nanoTime)
            } catch (error: Throwable) {
                encoder.close()
                throw error
            }
        }

        private fun createSession(environment: OrtEnvironment, model: File): OrtSession {
            val options = OrtSession.SessionOptions()
            try {
                options.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
                options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                options.setInterOpNumThreads(1)
                options.setIntraOpNumThreads(1)
                options.setSessionLogLevel(OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING)
                options.addConfigEntry("session.disable_cpu_ep_fallback", "1")
                options.addConfigEntry("ep.context_file_path", model.canonicalPath)
                val devices = environment.epDevices.filter { it.epName == EP_NAME }
                check(devices.isNotEmpty()) { "QNN HTP execution provider is unavailable" }
                options.addExecutionProvider(
                    devices,
                    mapOf(
                        "backend_type" to "htp",
                        "offload_graph_io_quantization" to "0"
                    )
                )
                return environment.createSession(model.canonicalPath, options)
            } finally {
                options.close()
            }
        }

        private object QnnOrtEnvironment {
            @Volatile
            private var registered = false

            @Synchronized
            fun environment(): OrtEnvironment {
                val environment = OrtEnvironment.getEnvironment(
                    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
                    "SignalASI-QNN-ASR"
                )
                if (!registered) {
                    environment.registerExecutionProviderLibrary(EP_NAME, EP_LIBRARY)
                    registered = true
                }
                return environment
            }
        }
    }
}

private data class OrtPersistentTensor(
    val contract: QnnTensorContract,
    val buffer: ByteBuffer,
    val tensor: OnnxTensor
) {
    fun clear(value: Short = 0) {
        when (contract.dataType) {
            QnnTensorDataType.FLOAT16 -> {
                val values = buffer.asShortBuffer()
                for (index in 0 until values.capacity()) values.put(index, value)
            }
            QnnTensorDataType.INT32 -> {
                val values = buffer.asIntBuffer()
                for (index in 0 until values.capacity()) values.put(index, 0)
            }
        }
    }
}

private class OrtTensorArena(private val environment: OrtEnvironment) : AutoCloseable {
    private val tensors = ArrayList<OrtPersistentTensor>()

    fun create(contract: QnnTensorContract): OrtPersistentTensor {
        val buffer = ByteBuffer.allocateDirect(contract.byteCount).order(ByteOrder.nativeOrder())
        val tensor = OnnxTensor.createTensor(
            environment,
            buffer,
            contract.shape,
            when (contract.dataType) {
                QnnTensorDataType.FLOAT16 -> OnnxJavaType.FLOAT16
                QnnTensorDataType.INT32 -> OnnxJavaType.INT32
            }
        )
        return OrtPersistentTensor(contract, buffer, tensor).also(tensors::add)
    }

    override fun close() {
        tensors.asReversed().forEach { runCatching { it.tensor.close() } }
        tensors.clear()
    }
}

private fun OrtSession.inputMetadata(): Map<String, QnnTensorMetadata> = inputInfo.toTensorMetadata()

private fun OrtSession.outputMetadata(): Map<String, QnnTensorMetadata> = outputInfo.toTensorMetadata()

private fun Map<String, NodeInfo>.toTensorMetadata(): Map<String, QnnTensorMetadata> = mapValues { (_, node) ->
    val info = node.info as? TensorInfo ?: error("QNN Whisper graph contains a non-tensor value")
    QnnTensorMetadata(
        dataType = when (info.type) {
            OnnxJavaType.FLOAT16 -> QnnTensorDataType.FLOAT16
            OnnxJavaType.INT32 -> QnnTensorDataType.INT32
            else -> error("QNN Whisper graph contains an unsupported tensor type: ${info.type}")
        },
        shape = info.shape
    )
}
