package com.galaxyssi.chat.voice.asr.local

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class CompactWhisperQnnContractParserTest {
    @Test
    fun `small W8A16 metadata preserves unsigned QNN quantization contracts`() {
        val compact = CompactWhisperQnnModelCatalog.smallW8A16
        val directory = Files.createTempDirectory("galaxyssi-small-w8a16-contract").toFile()
        try {
            directory.resolve("whisper_metadata.json").writeText(
                metadata(compact.manifest),
                Charsets.UTF_8
            )

            val contract = CompactWhisperQnnContractParser.parse(directory, compact.manifest)

            assertEquals(QnnTensorDataType.UINT16, contract.encoder.inputs.single().dataType)
            assertTrue(contract.encoder.inputs.single().quantization != null)
            assertTrue(contract.encoder.outputs.all { it.dataType == QnnTensorDataType.UINT8 })
            assertEquals(
                QnnTensorDataType.UINT16,
                contract.decoder.inputs.first { it.name == "attention_mask" }.dataType
            )
            assertEquals(
                QnnTensorDataType.UINT16,
                contract.decoder.outputs.first { it.name == "logits" }.dataType
            )
            assertTrue(
                contract.decoder.inputs
                    .filter { "cache" in it.name }
                    .all { it.dataType == QnnTensorDataType.UINT8 && it.quantization != null }
            )
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun metadata(manifest: LargeTurboQnnModelManifest): String {
        val encoderInputs = JSONObject().put(
            "input_features",
            tensor("uint16", listOf(1, 80, 3_000), quantized = true)
        )
        val encoderOutputs = JSONObject()
        repeat(manifest.decoderLayers) { layer ->
            encoderOutputs.put("k_cache_cross_$layer", cacheTensor())
            encoderOutputs.put("v_cache_cross_$layer", cacheTensor())
        }
        val decoderInputs = JSONObject()
            .put("input_ids", tensor("int32", listOf(1, 1)))
            .put("attention_mask", tensor("uint16", listOf(1, 1, 1, 200), quantized = true))
        repeat(manifest.decoderLayers) { layer ->
            decoderInputs.put("k_cache_self_${layer}_in", selfCacheTensor())
            decoderInputs.put("v_cache_self_${layer}_in", selfCacheTensor())
        }
        repeat(manifest.decoderLayers) { layer ->
            decoderInputs.put("k_cache_cross_$layer", cacheTensor())
            decoderInputs.put("v_cache_cross_$layer", cacheTensor())
        }
        decoderInputs.put("position_ids", tensor("int32", listOf(1, 1)))
        val decoderOutputs = JSONObject().put(
            "logits",
            tensor("uint16", listOf(1, manifest.vocabularySize, 1, 1), quantized = true)
        )
        repeat(manifest.decoderLayers) { layer ->
            decoderOutputs.put("k_cache_self_${layer}_out", selfCacheTensor())
            decoderOutputs.put("v_cache_self_${layer}_out", selfCacheTensor())
        }
        return JSONObject()
            .put("model_id", manifest.metadataModelId)
            .put("runtime", "qnn_context_binary")
            .put("precision", manifest.precision)
            .put(
                "model_files",
                JSONObject()
                    .put(
                        "encoder.bin",
                        JSONObject().put("inputs", encoderInputs).put("outputs", encoderOutputs)
                    )
                    .put(
                        "decoder.bin",
                        JSONObject().put("inputs", decoderInputs).put("outputs", decoderOutputs)
                    )
            )
            .toString()
    }

    private fun cacheTensor() = tensor("uint8", listOf(1, 12, 1_500, 64), quantized = true)

    private fun selfCacheTensor() = tensor("uint8", listOf(1, 12, 200, 64), quantized = true)

    private fun tensor(dtype: String, shape: List<Int>, quantized: Boolean = false) = JSONObject()
        .put("dtype", dtype)
        .put("shape", shape)
        .apply {
            if (quantized) {
                put(
                    "quantization_parameters",
                    JSONObject().put("scale", 0.03125).put("zero_point", 128)
                )
            }
        }
}
