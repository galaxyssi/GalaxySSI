package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WhisperLargeTurboQnnContractTest {
    @Test
    fun officialS26ContractsExposeEveryPinnedTensor() {
        val encoder = WhisperLargeTurboQnnContract.encoder
        val decoder = WhisperLargeTurboQnnContract.decoder

        assertEquals(listOf("input_features"), encoder.inputs.map(QnnTensorContract::name))
        assertEquals(8, encoder.outputs.size)
        assertEquals(19, decoder.inputs.size)
        assertEquals(9, decoder.outputs.size)
        assertEquals(768_000, encoder.inputs.single().byteCount)
        assertEquals(30_720_000, encoder.outputs.sumOf(QnnTensorContract::byteCount))
        assertEquals(103_732, decoder.outputs.first { it.name == "logits" }.byteCount)
        assertEquals(
            listOf("input_ids", "attention_mask") +
                (0 until 4).flatMap { listOf("k_cache_self_${it}_in", "v_cache_self_${it}_in") } +
                (0 until 4).flatMap { listOf("k_cache_cross_$it", "v_cache_cross_$it") } +
                "position_ids",
            decoder.inputs.map(QnnTensorContract::name)
        )
    }

    @Test
    fun exactMetadataPassesAndAnyShapeDriftFails() {
        val contract = WhisperLargeTurboQnnContract.decoder
        val inputs = contract.inputs.associate { it.name to QnnTensorMetadata(it.dataType, it.shape.copyOf()) }
        val outputs = contract.outputs.associate { it.name to QnnTensorMetadata(it.dataType, it.shape.copyOf()) }

        contract.validate(inputs, outputs)

        val drifted = inputs.toMutableMap().apply {
            this["attention_mask"] = QnnTensorMetadata(QnnTensorDataType.FLOAT16, longArrayOf(1, 1, 1, 199))
        }
        assertThrows(IllegalArgumentException::class.java) { contract.validate(drifted, outputs) }
    }

    @Test
    fun missingOrUnexpectedTensorFailsClosed() {
        val contract = WhisperLargeTurboQnnContract.encoder
        val inputs = contract.inputs.associate { it.name to QnnTensorMetadata(it.dataType, it.shape.copyOf()) }
        val outputs = contract.outputs.associate { it.name to QnnTensorMetadata(it.dataType, it.shape.copyOf()) }
            .toMutableMap()
            .apply { remove("k_cache_cross_0") }

        assertThrows(IllegalArgumentException::class.java) { contract.validate(inputs, outputs) }
    }
}
