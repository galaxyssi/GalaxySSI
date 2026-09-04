package com.galaxyssi.chat.voice.asr.local

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

internal object CompactWhisperQnnContractParser {
    fun parse(modelDirectory: File, manifest: LargeTurboQnnModelManifest): QnnWhisperModelContract {
        val root = JSONObject(File(modelDirectory, "whisper_metadata.json").readText(Charsets.UTF_8))
        require(root.getString("model_id") == manifest.metadataModelId)
        require(root.getString("runtime") == "qnn_context_binary")
        require(root.getString("precision") == manifest.precision)
        val files = root.getJSONObject("model_files")
        val encoderMetadata = files.getJSONObject("encoder.bin")
        val decoderMetadata = files.getJSONObject("decoder.bin")
        val encoderInputs = encoderMetadata.getJSONObject("inputs")
        val encoderOutputs = encoderMetadata.getJSONObject("outputs")
        val decoderInputs = decoderMetadata.getJSONObject("inputs")
        val decoderOutputs = decoderMetadata.getJSONObject("outputs")

        val encoder = QnnGraphContract(
            graphName = "hf_whisper_encoder",
            contextBinaryName = "encoder.bin",
            wrapperModelName = "encoder_context.onnx",
            inputs = listOf(tensor("input_features", encoderInputs)),
            outputs = buildList {
                repeat(manifest.decoderLayers) { layer ->
                    add(tensor("k_cache_cross_$layer", encoderOutputs))
                    add(tensor("v_cache_cross_$layer", encoderOutputs))
                }
            }
        )
        val decoder = QnnGraphContract(
            graphName = "hf_whisper_decoder",
            contextBinaryName = "decoder.bin",
            wrapperModelName = "decoder_context.onnx",
            inputs = buildList {
                add(tensor("input_ids", decoderInputs))
                add(tensor("attention_mask", decoderInputs))
                repeat(manifest.decoderLayers) { layer ->
                    add(tensor("k_cache_self_${layer}_in", decoderInputs))
                    add(tensor("v_cache_self_${layer}_in", decoderInputs))
                }
                repeat(manifest.decoderLayers) { layer ->
                    add(tensor("k_cache_cross_$layer", decoderInputs))
                    add(tensor("v_cache_cross_$layer", decoderInputs))
                }
                add(tensor("position_ids", decoderInputs))
            },
            outputs = buildList {
                add(tensor("logits", decoderOutputs))
                repeat(manifest.decoderLayers) { layer ->
                    add(tensor("k_cache_self_${layer}_out", decoderOutputs))
                    add(tensor("v_cache_self_${layer}_out", decoderOutputs))
                }
            }
        )
        val contract = QnnWhisperModelContract(
            melBins = manifest.melBins,
            melFrames = manifest.melFrames,
            decoderLayers = manifest.decoderLayers,
            decoderContextTokens = decoder.inputs.first { it.name == "attention_mask" }.shape.last().toInt(),
            vocabularySize = manifest.vocabularySize,
            encoder = encoder,
            decoder = decoder
        )
        require(encoder.inputs.single().shape.contentEquals(longArrayOf(1, manifest.melBins.toLong(), 3_000)))
        require(decoder.outputs.first { it.name == "logits" }.shape.contentEquals(
            longArrayOf(1, manifest.vocabularySize.toLong(), 1, 1)
        ))
        return contract
    }

    private fun tensor(name: String, values: JSONObject): QnnTensorContract {
        val value = values.getJSONObject(name)
        val type = when (value.getString("dtype")) {
            "float16" -> QnnTensorDataType.FLOAT16
            "int32" -> QnnTensorDataType.INT32
            "uint8" -> QnnTensorDataType.UINT8
            "uint16" -> QnnTensorDataType.UINT16
            else -> error("Unsupported QNN tensor type for $name")
        }
        val quantization = value.optJSONObject("quantization_parameters")?.let {
            QnnQuantizationParameters(
                scale = it.getDouble("scale").toFloat(),
                zeroPoint = it.getInt("zero_point")
            )
        }
        if (type == QnnTensorDataType.UINT8 || type == QnnTensorDataType.UINT16) {
            requireNotNull(quantization) { "Quantized QNN tensor $name has no scale" }
        }
        return QnnTensorContract(name, type, value.getJSONArray("shape").toLongArray(), quantization)
    }

    private fun JSONArray.toLongArray(): LongArray = LongArray(length()) { index -> getLong(index) }
}
