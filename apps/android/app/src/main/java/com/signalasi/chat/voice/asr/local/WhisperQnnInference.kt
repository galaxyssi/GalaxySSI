package com.signalasi.chat.voice.asr.local

import java.nio.FloatBuffer

internal enum class WhisperDecoderSelection {
    UNRESTRICTED,
    FIRST_TEXT_TOKEN,
    TEXT_TOKEN
}

internal data class WhisperQnnDecoderStep(
    val nextToken: Int,
    val elapsedNanos: Long
)

internal interface WhisperQnnNetwork : AutoCloseable {
    fun encode(melFeatures: FloatBuffer): Long
    fun resetDecoder()
    fun decode(inputToken: Int, position: Int, selection: WhisperDecoderSelection): WhisperQnnDecoderStep
}

internal data class WhisperQnnTranscription(
    val text: String,
    val tokenIds: List<Int>,
    val encoderNanos: Long,
    val decoderNanos: Long,
    val decoderSteps: Int,
    val detectedLanguage: String?,
    val qnnExecution: QnnExecutionAttestation? = null
) {
    val inferenceMs: Long
        get() = (encoderNanos + decoderNanos) / 1_000_000L

    val decoderMsPerToken: Double
        get() = if (decoderSteps == 0) 0.0 else decoderNanos / 1_000_000.0 / decoderSteps
}

internal class WhisperGreedyTranscriber(
    private val network: WhisperQnnNetwork,
    private val tokenizer: WhisperTiktokenTokenizer
) {
    fun transcribe(melFeatures: FloatArray, language: String, maxTokens: Int): WhisperQnnTranscription {
        return transcribe(FloatBuffer.wrap(melFeatures), language, maxTokens)
    }

    fun transcribe(melFeatures: FloatBuffer, language: String, maxTokens: Int): WhisperQnnTranscription {
        require(melFeatures.remaining() ==
            WhisperLargeTurboQnnContract.MEL_BINS * WhisperLargeTurboQnnContract.MEL_FRAMES)
        require(language == "auto" || language in tokenizer.generation.languageTokens)
        require(maxTokens in 1..160)

        val encoderNanos = network.encode(melFeatures)
        network.resetDecoder()
        var decoderNanos = 0L
        var decoderSteps = 0
        var position = 0

        fun step(token: Int, selection: WhisperDecoderSelection): Int {
            check(position < WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS)
            val result = network.decode(token, position, selection)
            position += 1
            decoderSteps += 1
            decoderNanos += result.elapsedNanos.coerceAtLeast(0L)
            return result.nextToken
        }

        val generation = tokenizer.generation
        val detectedLanguage: String?
        val firstTextToken: Int
        if (language == "auto") {
            val predictedLanguage = step(generation.startOfTranscript, WhisperDecoderSelection.UNRESTRICTED)
            val languageToken = predictedLanguage.takeIf(generation::isLanguageToken)
                ?: requireNotNull(generation.languageTokens["zh"])
            detectedLanguage = generation.languageTokens.entries.firstOrNull { it.value == languageToken }?.key
            step(languageToken, WhisperDecoderSelection.UNRESTRICTED)
            step(generation.transcribe, WhisperDecoderSelection.UNRESTRICTED)
            firstTextToken = step(generation.noTimestamps, WhisperDecoderSelection.FIRST_TEXT_TOKEN)
        } else {
            detectedLanguage = language
            val prompt = generation.prompt(language)
            var predicted = generation.endOfText
            prompt.forEachIndexed { index, token ->
                predicted = step(
                    token,
                    if (index == prompt.lastIndex) {
                        WhisperDecoderSelection.FIRST_TEXT_TOKEN
                    } else {
                        WhisperDecoderSelection.UNRESTRICTED
                    }
                )
            }
            firstTextToken = predicted
        }

        val output = ArrayList<Int>(maxTokens)
        var next = firstTextToken
        while (next != generation.endOfText && output.size < maxTokens &&
            position < WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS
        ) {
            output += next
            if (output.size < maxTokens && position < WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS) {
                next = step(next, WhisperDecoderSelection.TEXT_TOKEN)
            }
        }

        return WhisperQnnTranscription(
            text = tokenizer.decode(output).trim(),
            tokenIds = output,
            encoderNanos = encoderNanos,
            decoderNanos = decoderNanos,
            decoderSteps = decoderSteps,
            detectedLanguage = detectedLanguage
        )
    }
}
