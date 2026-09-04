package com.galaxyssi.chat.voice.asr.local

import java.nio.FloatBuffer
import java.util.zip.Deflater
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
    fun decode(
        inputToken: Int,
        position: Int,
        selection: WhisperDecoderSelection,
        additionalSuppressedTokens: Set<Int> = emptySet()
    ): WhisperQnnDecoderStep
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
    val decodePasses: Int = 1,
    val compressionRatio: Double = 0.0,
    val repeatedNgramRatio: Double = 0.0,
    val qnnExecution: QnnExecutionAttestation? = null
) {
    val inferenceMs: Long
        get() = (encoderNanos + decoderNanos) / 1_000_000L

    val decoderMsPerToken: Double
        get() = if (decoderSteps == 0) 0.0 else decoderNanos / 1_000_000.0 / decoderSteps
}

internal class WhisperGreedyTranscriber(
    private val network: WhisperQnnNetwork,
    private val tokenizer: WhisperTiktokenTokenizer,
    private val modelContract: QnnWhisperModelContract = WhisperLargeTurboQnnContract.model
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
        require(melFeatures.remaining() == modelContract.melBins * modelContract.melFrames)
        require(language == "auto" || language in tokenizer.generation.languageTokens)
        require(maxTokens in 1..AsrConfig.MAX_FINAL_TOKENS)

        checkNotCancelled(cancellationRequested)
        val encoderNanos = network.encode(melFeatures)
        checkNotCancelled(cancellationRequested)
        val primary = decodePass(language, maxTokens, 0, cancellationRequested)
        val primaryQuality = WhisperRepetitionQualityPolicy.evaluate(primary.text, primary.tokenIds)
        var selected = primary
        var selectedQuality = primaryQuality
        var decoderNanos = primary.decoderNanos
        var decoderSteps = primary.decoderSteps
        var decodePasses = 1
        if (primaryQuality.suspicious) {
            checkNotCancelled(cancellationRequested)
            val recovery = decodePass(language, maxTokens, RECOVERY_NO_REPEAT_NGRAM, cancellationRequested)
            val recoveryQuality = WhisperRepetitionQualityPolicy.evaluate(recovery.text, recovery.tokenIds)
            decoderNanos += recovery.decoderNanos
            decoderSteps += recovery.decoderSteps
            decodePasses += 1
            if (recovery.text.isNotBlank() && recoveryQuality.score < primaryQuality.score) {
                selected = recovery
                selectedQuality = recoveryQuality
            }
        }
        val termination = if (selectedQuality.suspicious) {
            AsrTranscriptTermination.REPETITION_LIMIT
        } else {
            selected.termination
        }
        return WhisperQnnTranscription(
            text = selected.text,
            tokenIds = selected.tokenIds,
            encoderNanos = encoderNanos,
            decoderNanos = decoderNanos,
            decoderSteps = decoderSteps,
            detectedLanguage = selected.detectedLanguage,
            termination = termination,
            decodePasses = decodePasses,
            compressionRatio = selectedQuality.compressionRatio,
            repeatedNgramRatio = selectedQuality.repeatedNgramRatio
        )
    }

    private fun decodePass(
        language: String,
        maxTokens: Int,
        noRepeatNgramSize: Int,
        cancellationRequested: () -> Boolean
    ): WhisperDecodePass {
        checkNotCancelled(cancellationRequested)
        network.resetDecoder()
        var decoderNanos = 0L
        var decoderSteps = 0
        var position = 0

        fun step(
            token: Int,
            selection: WhisperDecoderSelection,
            additionalSuppressedTokens: Set<Int> = emptySet()
        ): Int {
            checkNotCancelled(cancellationRequested)
            check(position < modelContract.decoderContextTokens)
            val result = network.decode(token, position, selection, additionalSuppressedTokens)
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
            position < modelContract.decoderContextTokens
        ) {
            output += next
            if (position < modelContract.decoderContextTokens) {
                next = step(
                    next,
                    WhisperDecoderSelection.TEXT_TOKEN,
                    noRepeatSuppressedTokens(output, noRepeatNgramSize)
                )
            }
        }

        val termination = when {
            next == generation.endOfText -> AsrTranscriptTermination.END_OF_TEXT
            output.size >= maxTokens -> AsrTranscriptTermination.TOKEN_LIMIT
            position >= modelContract.decoderContextTokens ->
                AsrTranscriptTermination.CONTEXT_LIMIT
            else -> AsrTranscriptTermination.UNKNOWN
        }
        return WhisperDecodePass(
            text = tokenizer.decode(output).trim(),
            tokenIds = output,
            decoderNanos = decoderNanos,
            decoderSteps = decoderSteps,
            detectedLanguage = detectedLanguage,
            termination = termination
        )
    }

    private fun noRepeatSuppressedTokens(output: List<Int>, ngramSize: Int): Set<Int> {
        if (ngramSize < 2 || output.size < ngramSize) return emptySet()
        val prefixLength = ngramSize - 1
        val suffixStart = output.size - prefixLength
        val blocked = LinkedHashSet<Int>()
        for (start in 0 until suffixStart) {
            var matches = true
            for (offset in 0 until prefixLength) {
                if (output[start + offset] != output[suffixStart + offset]) {
                    matches = false
                    break
                }
            }
            if (matches) blocked += output[start + prefixLength]
        }
        return blocked
    }

    private fun checkNotCancelled(cancellationRequested: () -> Boolean) {
        if (cancellationRequested()) throw QnnInferenceCancelledException()
    }

    private companion object {
        const val RECOVERY_NO_REPEAT_NGRAM = 3
    }
}

internal data class WhisperDecodePass(
    val text: String,
    val tokenIds: List<Int>,
    val decoderNanos: Long,
    val decoderSteps: Int,
    val detectedLanguage: String?,
    val termination: AsrTranscriptTermination
)

internal data class WhisperRepetitionQuality(
    val compressionRatio: Double,
    val repeatedNgramRatio: Double,
    val suspicious: Boolean,
    val score: Double
)

internal object WhisperRepetitionQualityPolicy {
    private const val COMPRESSION_RATIO_THRESHOLD = 2.4
    private const val REPEATED_NGRAM_RATIO_THRESHOLD = 0.35
    private const val NGRAM_SIZE = 3
    private const val MIN_TOKENS_FOR_NGRAM_CHECK = 8

    fun evaluate(text: String, tokenIds: List<Int>): WhisperRepetitionQuality {
        val compressionRatio = compressionRatio(text)
        val repeatedNgramRatio = repeatedNgramRatio(tokenIds)
        val compressionScore = compressionRatio / COMPRESSION_RATIO_THRESHOLD
        val ngramScore = repeatedNgramRatio / REPEATED_NGRAM_RATIO_THRESHOLD
        val score = maxOf(compressionScore, ngramScore)
        return WhisperRepetitionQuality(
            compressionRatio = compressionRatio,
            repeatedNgramRatio = repeatedNgramRatio,
            suspicious = score > 1.0,
            score = score
        )
    }

    private fun compressionRatio(text: String): Double {
        val input = text.toByteArray(Charsets.UTF_8)
        if (input.isEmpty()) return 0.0
        val deflater = Deflater()
        return try {
            deflater.setInput(input)
            deflater.finish()
            val buffer = ByteArray(256)
            var compressedBytes = 0
            while (!deflater.finished()) compressedBytes += deflater.deflate(buffer)
            if (compressedBytes == 0) 0.0 else input.size.toDouble() / compressedBytes
        } finally {
            deflater.end()
        }
    }

    private fun repeatedNgramRatio(tokenIds: List<Int>): Double {
        if (tokenIds.size < MIN_TOKENS_FOR_NGRAM_CHECK) return 0.0
        val total = tokenIds.size - NGRAM_SIZE + 1
        if (total <= 0) return 0.0
        val unique = HashSet<List<Int>>(total)
        for (index in 0 until total) unique += tokenIds.subList(index, index + NGRAM_SIZE).toList()
        return (total - unique.size).toDouble() / total
    }
}
