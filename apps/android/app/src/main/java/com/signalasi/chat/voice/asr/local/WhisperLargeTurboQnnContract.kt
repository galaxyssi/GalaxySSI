package com.signalasi.chat.voice.asr.local

internal enum class QnnTensorDataType {
    FLOAT16,
    INT32
}

internal data class QnnTensorContract(
    val name: String,
    val dataType: QnnTensorDataType,
    val shape: LongArray
) {
    val elementCount: Int = shape.fold(1L, Long::times).also {
        require(it in 1L..Int.MAX_VALUE)
    }.toInt()

    val byteCount: Int = Math.multiplyExact(
        elementCount,
        when (dataType) {
            QnnTensorDataType.FLOAT16 -> Short.SIZE_BYTES
            QnnTensorDataType.INT32 -> Int.SIZE_BYTES
        }
    )
}

internal data class QnnTensorMetadata(
    val dataType: QnnTensorDataType,
    val shape: LongArray
)

internal data class QnnGraphContract(
    val graphName: String,
    val contextBinaryName: String,
    val wrapperModelName: String,
    val inputs: List<QnnTensorContract>,
    val outputs: List<QnnTensorContract>
) {
    init {
        require(inputs.isNotEmpty() && outputs.isNotEmpty())
        require((inputs + outputs).map(QnnTensorContract::name).distinct().size == inputs.size + outputs.size)
    }

    fun validate(
        actualInputs: Map<String, QnnTensorMetadata>,
        actualOutputs: Map<String, QnnTensorMetadata>
    ) {
        validateSide("input", inputs, actualInputs)
        validateSide("output", outputs, actualOutputs)
    }

    private fun validateSide(
        side: String,
        expected: List<QnnTensorContract>,
        actual: Map<String, QnnTensorMetadata>
    ) {
        val expectedNames = expected.map(QnnTensorContract::name).toSet()
        require(actual.keys == expectedNames) {
            "$graphName $side names do not match the signed model contract"
        }
        expected.forEach { tensor ->
            val metadata = requireNotNull(actual[tensor.name])
            require(metadata.dataType == tensor.dataType) {
                "$graphName ${tensor.name} has an unexpected data type"
            }
            require(metadata.shape.contentEquals(tensor.shape)) {
                "$graphName ${tensor.name} has an unexpected shape"
            }
        }
    }
}

internal object WhisperLargeTurboQnnContract {
    const val SAMPLE_RATE_HZ = 16_000
    const val MEL_BINS = 128
    const val MEL_FRAMES = 3_000
    const val DECODER_LAYERS = 4
    const val DECODER_HEADS = 20
    const val DECODER_HEAD_SIZE = 64
    const val DECODER_CONTEXT_TOKENS = 200
    const val SELF_CACHE_TOKENS = DECODER_CONTEXT_TOKENS - 1
    const val AUDIO_EMBEDDING_TOKENS = 1_500
    const val VOCABULARY_SIZE = 51_866
    const val ENCODER_NPU_LAYERS = 5_026
    const val DECODER_NPU_LAYERS = 1_213

    val encoder = QnnGraphContract(
        graphName = "hf_whisper_encoder",
        contextBinaryName = "encoder.bin",
        wrapperModelName = "encoder_context.onnx",
        inputs = listOf(float16("input_features", 1, MEL_BINS, MEL_FRAMES)),
        outputs = buildList {
            repeat(DECODER_LAYERS) { layer ->
                add(float16("k_cache_cross_$layer", DECODER_HEADS, 1, DECODER_HEAD_SIZE, AUDIO_EMBEDDING_TOKENS))
                add(float16("v_cache_cross_$layer", DECODER_HEADS, 1, AUDIO_EMBEDDING_TOKENS, DECODER_HEAD_SIZE))
            }
        }
    )

    val decoder = QnnGraphContract(
        graphName = "hf_whisper_decoder",
        contextBinaryName = "decoder.bin",
        wrapperModelName = "decoder_context.onnx",
        inputs = buildList {
            add(int32("input_ids", 1, 1))
            add(float16("attention_mask", 1, 1, 1, DECODER_CONTEXT_TOKENS))
            repeat(DECODER_LAYERS) { layer ->
                add(float16("k_cache_self_${layer}_in", DECODER_HEADS, 1, DECODER_HEAD_SIZE, SELF_CACHE_TOKENS))
                add(float16("v_cache_self_${layer}_in", DECODER_HEADS, 1, SELF_CACHE_TOKENS, DECODER_HEAD_SIZE))
            }
            repeat(DECODER_LAYERS) { layer ->
                add(float16("k_cache_cross_$layer", DECODER_HEADS, 1, DECODER_HEAD_SIZE, AUDIO_EMBEDDING_TOKENS))
                add(float16("v_cache_cross_$layer", DECODER_HEADS, 1, AUDIO_EMBEDDING_TOKENS, DECODER_HEAD_SIZE))
            }
            add(int32("position_ids", 1))
        },
        outputs = buildList {
            add(float16("logits", 1, VOCABULARY_SIZE, 1, 1))
            repeat(DECODER_LAYERS) { layer ->
                add(float16("k_cache_self_${layer}_out", DECODER_HEADS, 1, DECODER_HEAD_SIZE, SELF_CACHE_TOKENS))
                add(float16("v_cache_self_${layer}_out", DECODER_HEADS, 1, SELF_CACHE_TOKENS, DECODER_HEAD_SIZE))
            }
        }
    )

    private fun float16(name: String, vararg shape: Int) = QnnTensorContract(
        name,
        QnnTensorDataType.FLOAT16,
        shape.map(Int::toLong).toLongArray()
    )

    private fun int32(name: String, vararg shape: Int) = QnnTensorContract(
        name,
        QnnTensorDataType.INT32,
        shape.map(Int::toLong).toLongArray()
    )
}
