package com.signalasi.chat.voice.asr.local

import java.nio.FloatBuffer
import java.util.concurrent.CancellationException

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
    fun cancelActiveRun() = Unit
}

internal class QnnInferenceCancelledException(cause: Throwable? = null) :
    CancellationException("QNN Whisper inference was superseded") {
    init {
        if (cause != null) initCause(cause)
    }
}

internal data class WhisperQnnTranscription(
    val text: String,
    val tokenIds: List<Int>,
    val encoderNanos: Long,
    val decoderNanos: Long,
    val decoderSteps: Int,
    val detectedLanguage: String?,
    val termination: AsrTranscriptTermination = AsrTranscriptTermination.END_OF_TEXT,
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
    fun transcribe(
        melFeatures: FloatArray,
        language: String,
        maxTokens: Int,
        cancellationRequested: () -> Boolean = { false }
    ): WhisperQnnTranscription {
        return transcribe(FloatBuffer.wrap(melFeatures), language, maxTokens, cancellationRequested)
    }

    fun transcribe(
        melFeatures: FloatBuffer,
        language: String,
        maxTokens: Int,
        cancellationRequested: () -> Boolean = { false }
    ): WhisperQnnTranscription {
        require(melFeatures.remaining() ==
            WhisperLargeTurboQnnContract.MEL_BINS * WhisperLargeTurboQnnContract.MEL_FRAMES)
        require(language == "auto" || language in tokenizer.generation.languageTokens)
        require(maxTokens in 1..AsrConfig.MAX_FINAL_TOKENS)

        checkNotCancelled(cancellationRequested)
        val encoderNanos = network.encode(melFeatures)
        checkNotCancelled(cancellationRequested)
        network.resetDecoder()
        var decoderNanos = 0L
        var decoderSteps = 0
        var position = 0

        fun step(token: Int, selection: WhisperDecoderSelection): Int {
            checkNotCancelled(cancellationRequested)
            check(position < WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS)
            val result = network.decode(token, position, selection)
            checkNotCancelled(cancellationRequested)
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
            // Decode one look-ahead token even when the visible budget has just been reached.
            // Without this step an utterance ending exactly at the budget is incorrectly marked
            // as truncated even when the next token is EOT.
            if (position < WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS) {
                next = step(next, WhisperDecoderSelection.TEXT_TOKEN)
            }
        }

        val termination = when {
            next == generation.endOfText -> AsrTranscriptTermination.END_OF_TEXT
            output.size >= maxTokens -> AsrTranscriptTermination.TOKEN_LIMIT
            position >= WhisperLargeTurboQnnContract.DECODER_CONTEXT_TOKENS ->
                AsrTranscriptTermination.CONTEXT_LIMIT
            else -> AsrTranscriptTermination.UNKNOWN
        }
        return WhisperQnnTranscription(
            text = tokenizer.decode(output).trim(),
            tokenIds = output,
            encoderNanos = encoderNanos,
            decoderNanos = decoderNanos,
            decoderSteps = decoderSteps,
            detectedLanguage = detectedLanguage,
            termination = termination
        )
    }

    private fun checkNotCancelled(cancellationRequested: () -> Boolean) {
        if (cancellationRequested()) throw QnnInferenceCancelledException()
    }
}
