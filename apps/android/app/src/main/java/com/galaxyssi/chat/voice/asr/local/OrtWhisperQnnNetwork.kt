package com.galaxyssi.chat.voice.asr.local

import ai.onnxruntime.NodeInfo
import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtLoggingLevel
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import ai.onnxruntime.UnsignedOnnxTensorFactory
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal class OrtWhisperQnnNetwork private constructor(
    private val environment: OrtEnvironment,
    private val encoderSession: OrtSession,
    private val decoderSession: OrtSession,
    private val contract: QnnWhisperModelContract,
    private val generation: WhisperGenerationTokens,
    private val executionTracker: QnnExecutionAttestationTracker,
    private val nanoTime: () -> Long
) : WhisperQnnNetwork, QnnExecutionAttestationSource {
    private val closed = AtomicBoolean(false)
    private val activeRunOptions = AtomicReference<OrtSession.RunOptions?>()
    private val arena = OrtTensorArena(environment)
    private val encoderInput = arena.create(contract.encoder.inputs.single())
    private val crossCache = contract.encoder.outputs.associateWith(arena::create)
    private val inputId = arena.create(contract.decoder.inputs.first { it.name == "input_ids" })
    private val positionId = arena.create(contract.decoder.inputs.first { it.name == "position_ids" })
    private val attentionMask = arena.create(
        contract.decoder.inputs.first { it.name == "attention_mask" }
    )
    private val logits = arena.create(contract.decoder.outputs.first { it.name == "logits" })
    private val selfCacheSlots = (0 until contract.decoderLayers).flatMap { layer ->
        listOf(
            SelfCacheSlot(
                "k_cache_self_${layer}_in",
                "k_cache_self_${layer}_out",
                arena.create(contract.decoder.inputs.first { it.name == "k_cache_self_${layer}_in" }),
                arena.create(contract.decoder.outputs.first { it.name == "k_cache_self_${layer}_out" })
            ),
            SelfCacheSlot(
                "v_cache_self_${layer}_in",
                "v_cache_self_${layer}_out",
                arena.create(contract.decoder.inputs.first { it.name == "v_cache_self_${layer}_in" }),
                arena.create(contract.decoder.outputs.first { it.name == "v_cache_self_${layer}_out" })
            )
        )
    }
    private val encoderInputs = linkedMapOf("input_features" to encoderInput.tensor)
    private val encoderOutputs = LinkedHashMap<String, OnnxTensor>()
    private val decoderInputs = LinkedHashMap<String, OnnxTensor>()
    private val decoderOutputs = LinkedHashMap<String, OnnxTensor>()

    init {
        contract.encoder.validate(encoderSession.inputMetadata(), encoderSession.outputMetadata())
        contract.decoder.validate(decoderSession.inputMetadata(), decoderSession.outputMetadata())
        executionTracker.markContextBinariesRestored()
        crossCache.forEach { (contract, tensor) -> encoderOutputs[contract.name] = tensor.tensor }
        bindDecoderTensors()
        resetDecoder()
    }

    override fun encode(melFeatures: FloatBuffer): Long = synchronized(this) {
        checkOpen()
        require(melFeatures.remaining() == encoderInput.contract.elementCount)
        encoderInput.writeFloats(melFeatures.duplicate())
        val started = nanoTime()
        runSession(encoderSession, encoderInputs, encoderOutputs)
        executionTracker.recordEncoderExecution()
        (nanoTime() - started).coerceAtLeast(0L)
    }

    override fun resetDecoder() = synchronized(this) {
        checkOpen()
        selfCacheSlots.forEach(SelfCacheSlot::clear)
        attentionMask.fillFloat(ATTENTION_MASK_NEGATIVE)
        inputId.clear()
        positionId.clear()
        logits.clear()
        bindDecoderTensors()
    }

    override fun decode(
        inputToken: Int,
        position: Int,
        selection: WhisperDecoderSelection,
        additionalSuppressedTokens: Set<Int>
    ): WhisperQnnDecoderStep = synchronized(this) {
        checkOpen()
        require(inputToken in 0 until contract.vocabularySize)
        require(position in 0 until contract.decoderContextTokens)
        inputId.putInt(0, inputToken)
        positionId.putInt(0, position)
        attentionMask.putFloat(contract.decoderContextTokens - position - 1, 0.0F)
        val started = nanoTime()
        runSession(decoderSession, decoderInputs, decoderOutputs)
        executionTracker.recordDecoderExecution()
        val elapsed = (nanoTime() - started).coerceAtLeast(0L)
        val suppressed = when (selection) {
            WhisperDecoderSelection.UNRESTRICTED -> emptySet()
            WhisperDecoderSelection.FIRST_TEXT_TOKEN -> generation.suppressTokens + generation.beginSuppressTokens
            WhisperDecoderSelection.TEXT_TOKEN -> generation.suppressTokens
        }
        val effectiveSuppression = if (additionalSuppressedTokens.isEmpty()) {
            suppressed
        } else {
            suppressed + additionalSuppressedTokens
        }
        val nextToken = logits.argmax(
            contract.vocabularySize,
            effectiveSuppression,
            if (selection == WhisperDecoderSelection.UNRESTRICTED) null else generation.timestampStart
        )
        selfCacheSlots.forEach(SelfCacheSlot::swap)
        bindDecoderTensors()
        WhisperQnnDecoderStep(nextToken, elapsed)
    }

    override fun close() = synchronized(this) {
        if (!closed.compareAndSet(false, true)) return
        cancelActiveRun()
        runCatching { decoderSession.close() }
        runCatching { encoderSession.close() }
        arena.close()
    }

    override fun executionAttestation(warmupCompleted: Boolean): QnnExecutionAttestation =
        executionTracker.executionAttestation(warmupCompleted)

    override fun cancelActiveRun() {
        activeRunOptions.get()?.let { options -> runCatching { options.setTerminate(true) } }
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

    private fun runSession(
        session: OrtSession,
        inputs: Map<String, OnnxTensor>,
        outputs: Map<String, OnnxTensor>
    ) {
        OrtSession.RunOptions().use { options ->
            QnnHtpSessionPolicy.runConfigEntries.forEach { (key, value) ->
                options.addRunConfigEntry(key, value)
            }
            check(activeRunOptions.compareAndSet(null, options)) { "A QNN run is already active" }
            try {
                // Every model output is pre-bound to a persistent tensor. Requested outputs must
                // therefore stay empty; listing the same names twice makes ORT count them twice.
                session.run(inputs, emptySet(), outputs, options).use { }
            } finally {
                activeRunOptions.compareAndSet(options, null)
            }
        }
    }

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

        fun open(
            modelDirectory: File,
            wrapperFiles: Map<String, File>,
            generation: WhisperGenerationTokens,
            providerLibrary: File,
            htpBackendLibrary: File,
            nanoTime: () -> Long = System::nanoTime
        ): OrtWhisperQnnNetwork = open(
            modelDirectory,
            wrapperFiles,
            WhisperLargeTurboQnnContract.model,
            generation,
            providerLibrary,
            htpBackendLibrary,
            nanoTime
        )

        fun open(
            modelDirectory: File,
            wrapperFiles: Map<String, File>,
            contract: QnnWhisperModelContract,
            generation: WhisperGenerationTokens,
            providerLibrary: File,
            htpBackendLibrary: File,
            nanoTime: () -> Long = System::nanoTime
        ): OrtWhisperQnnNetwork {
            val environment = QnnOrtEnvironment.environment(providerLibrary)
            val encoderModel = requireNotNull(wrapperFiles[contract.encoder.wrapperModelName])
            val decoderModel = requireNotNull(wrapperFiles[contract.decoder.wrapperModelName])
            require(encoderModel.parentFile?.canonicalFile == modelDirectory.canonicalFile)
            require(decoderModel.parentFile?.canonicalFile == modelDirectory.canonicalFile)
            val sharedMemoryEnabled = QnnHtpSharedMemoryAvailability.android.isAvailable()
            val executionTracker = QnnExecutionAttestationTracker(sharedMemoryEnabled)
            val encoder = createSession(environment, encoderModel, htpBackendLibrary, sharedMemoryEnabled)
            try {
                val decoder = createSession(environment, decoderModel, htpBackendLibrary, sharedMemoryEnabled)
                try {
                    return OrtWhisperQnnNetwork(
                        environment,
                        encoder,
                        decoder,
                        contract,
                        generation,
                        executionTracker,
                        nanoTime
                    )
                } catch (error: Throwable) {
                    decoder.close()
                    throw error
                }
            } catch (error: Throwable) {
                encoder.close()
                throw error
            }
        }

        private fun createSession(
            environment: OrtEnvironment,
            model: File,
            htpBackendLibrary: File,
            sharedMemoryEnabled: Boolean
        ): OrtSession {
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
                    QnnHtpSessionPolicy.providerOptions(
                        backendPath = htpBackendLibrary.canonicalPath,
                        sharedMemoryAvailable = sharedMemoryEnabled
                    )
                )
                return environment.createSession(model.canonicalPath, options)
            } finally {
                options.close()
            }
        }

        private object QnnOrtEnvironment {
            @Volatile
            private var registeredPath = ""

            @Synchronized
            fun environment(providerLibrary: File): OrtEnvironment {
                val canonicalLibrary = providerLibrary.canonicalFile
                require(canonicalLibrary.isFile && canonicalLibrary.canRead()) {
                    "QNN execution provider library is unavailable"
                }
                val environment = OrtEnvironment.getEnvironment(
                    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
                    "GalaxySSI-QNN-ASR"
                )
                if (registeredPath.isBlank()) {
                    environment.registerExecutionProviderLibrary(EP_NAME, canonicalLibrary.path)
                    registeredPath = canonicalLibrary.path
                } else {
                    check(registeredPath == canonicalLibrary.path) {
                        "QNN execution provider was registered from a different library"
                    }
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
    fun clear() {
        when (contract.dataType) {
            QnnTensorDataType.FLOAT16 -> {
                val values = buffer.asShortBuffer()
                for (index in 0 until values.capacity()) values.put(index, 0)
            }
            QnnTensorDataType.INT32 -> {
                val values = buffer.asIntBuffer()
                for (index in 0 until values.capacity()) values.put(index, 0)
            }
            QnnTensorDataType.UINT8 -> {
                val value = requireNotNull(contract.quantization).zeroPoint.toByte()
                for (index in 0 until buffer.capacity()) buffer.put(index, value)
            }
            QnnTensorDataType.UINT16 -> {
                val values = buffer.asShortBuffer()
                val value = requireNotNull(contract.quantization).zeroPoint.toShort()
                for (index in 0 until values.capacity()) values.put(index, value)
            }
        }
    }

    fun writeFloats(source: FloatBuffer) {
        require(source.remaining() == contract.elementCount)
        repeat(contract.elementCount) { index -> putFloat(index, source.get()) }
    }

    fun fillFloat(value: Float) {
        repeat(contract.elementCount) { index -> putFloat(index, value) }
    }

    fun putFloat(index: Int, value: Float) {
        when (contract.dataType) {
            QnnTensorDataType.FLOAT16 -> buffer.asShortBuffer().put(index, Float16Codec.encode(value))
            QnnTensorDataType.UINT8 -> {
                val q = requireNotNull(contract.quantization)
                val encoded = (value / q.scale + q.zeroPoint).toInt().coerceIn(0, 255)
                buffer.put(index, encoded.toByte())
            }
            QnnTensorDataType.UINT16 -> {
                val q = requireNotNull(contract.quantization)
                val encoded = (value / q.scale + q.zeroPoint).toInt().coerceIn(0, 65_535)
                buffer.asShortBuffer().put(index, encoded.toShort())
            }
            QnnTensorDataType.INT32 -> error("INT32 tensor does not accept floating-point values")
        }
    }

    fun putInt(index: Int, value: Int) {
        require(contract.dataType == QnnTensorDataType.INT32)
        buffer.asIntBuffer().put(index, value)
    }

    fun argmax(count: Int, suppressed: Set<Int>, maximumExclusive: Int?): Int = when (contract.dataType) {
        QnnTensorDataType.FLOAT16 -> Float16Codec.argmax(
            buffer.asShortBuffer(),
            count,
            suppressed,
            maximumExclusive
        )
        QnnTensorDataType.UINT16 -> unsignedArgmax(
            count,
            suppressed,
            maximumExclusive
        ) { index -> buffer.asShortBuffer().get(index).toInt() and 0xffff }
        QnnTensorDataType.UINT8 -> unsignedArgmax(
            count,
            suppressed,
            maximumExclusive
        ) { index -> buffer.get(index).toInt() and 0xff }
        QnnTensorDataType.INT32 -> error("INT32 logits are unsupported")
    }

    private inline fun unsignedArgmax(
        count: Int,
        suppressed: Set<Int>,
        maximumExclusive: Int?,
        valueAt: (Int) -> Int
    ): Int {
        var bestToken = -1
        var bestValue = Int.MIN_VALUE
        repeat(count) { token ->
            if (token !in suppressed && (maximumExclusive == null || token < maximumExclusive)) {
                val value = valueAt(token)
                if (bestToken < 0 || value > bestValue) {
                    bestToken = token
                    bestValue = value
                }
            }
        }
        check(bestToken >= 0) { "All Whisper tokens were suppressed" }
        return bestToken
    }
}

private class OrtTensorArena(private val environment: OrtEnvironment) : AutoCloseable {
    private val tensors = ArrayList<OrtPersistentTensor>()

    fun create(contract: QnnTensorContract): OrtPersistentTensor {
        val buffer = ByteBuffer.allocateDirect(contract.byteCount).order(ByteOrder.nativeOrder())
        val tensor = if (contract.dataType == QnnTensorDataType.UINT16) {
            UnsignedOnnxTensorFactory.createUInt16Tensor(environment, buffer, contract.shape)
        } else {
            OnnxTensor.createTensor(
                environment,
                buffer,
                contract.shape,
                when (contract.dataType) {
                    QnnTensorDataType.FLOAT16 -> OnnxJavaType.FLOAT16
                    QnnTensorDataType.INT32 -> OnnxJavaType.INT32
                    QnnTensorDataType.UINT8 -> OnnxJavaType.UINT8
                    QnnTensorDataType.UINT16 -> error("UINT16 tensor must use the unsigned bridge")
                }
            )
        }
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
            OnnxJavaType.UINT8 -> QnnTensorDataType.UINT8
            OnnxJavaType.INT16 -> when (info.onnxType) {
                TensorInfo.OnnxTensorType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16 -> QnnTensorDataType.UINT16
                else -> error("QNN Whisper graph contains an unsupported INT16 tensor")
            }
            else -> error("QNN Whisper graph contains an unsupported tensor type: ${info.type}")
        },
        shape = info.shape
    )
}
