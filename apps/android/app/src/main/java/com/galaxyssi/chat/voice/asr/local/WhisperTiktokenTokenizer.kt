package com.galaxyssi.chat.voice.asr.local

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64

internal data class WhisperGenerationTokens(
    val startOfTranscript: Int,
    val endOfText: Int,
    val noTimestamps: Int,
    val languageTokens: Map<String, Int>,
    val transcribe: Int,
    val suppressTokens: Set<Int>,
    val beginSuppressTokens: Set<Int>
) {
    init {
        require(startOfTranscript >= 0 && endOfText >= 0 && noTimestamps >= 0 && transcribe >= 0)
        require(languageTokens.isNotEmpty())
    }

    val timestampStart: Int = noTimestamps + 1

    fun prompt(language: String): IntArray {
        if (language == "auto") return intArrayOf(startOfTranscript)
        val languageToken = requireNotNull(languageTokens[language]) { "Unsupported Whisper language: $language" }
        return intArrayOf(startOfTranscript, languageToken, transcribe, noTimestamps)
    }

    fun isLanguageToken(token: Int): Boolean = token in languageTokens.values
}

internal class WhisperTiktokenTokenizer private constructor(
    private val mergeableTokenBytes: Array<ByteArray?>,
    val generation: WhisperGenerationTokens
) {
    val vocabularySize: Int
        get() = mergeableTokenBytes.size

    fun decode(tokenIds: List<Int>): String {
        val bytes = ByteArrayOutputStream(tokenIds.size * 3)
        tokenIds.forEach { token ->
            if (token in mergeableTokenBytes.indices) {
                mergeableTokenBytes[token]?.let(bytes::write)
            }
        }
        return bytes.toByteArray().toString(Charsets.UTF_8)
    }

    companion object {
        fun load(tokenizerFile: File, generationConfigFile: File): WhisperTiktokenTokenizer {
            require(tokenizerFile.isFile && tokenizerFile.canRead()) { "Whisper tokenizer is unavailable" }
            require(generationConfigFile.isFile && generationConfigFile.canRead()) {
                "Whisper generation config is unavailable"
            }
            val decodedTokens = sortedMapOf<Int, ByteArray>()
            tokenizerFile.bufferedReader(Charsets.US_ASCII).useLines { lines ->
                lines.forEachIndexed { lineIndex, rawLine ->
                    val line = rawLine.trim()
                    if (line.isEmpty()) return@forEachIndexed
                    val separator = line.lastIndexOf(' ')
                    require(separator > 0 && separator < line.lastIndex) {
                        "Invalid tiktoken entry at line ${lineIndex + 1}"
                    }
                    val rank = line.substring(separator + 1).toInt()
                    val encodedToken = line.substring(0, separator)
                    val tokenBytes = if (encodedToken == EMPTY_TOKEN_SENTINEL) {
                        ByteArray(0)
                    } else {
                        Base64.getDecoder().decode(encodedToken)
                    }
                    require(rank >= 0 && decodedTokens.put(rank, tokenBytes) == null) {
                        "Duplicate or invalid tiktoken rank at line ${lineIndex + 1}"
                    }
                }
            }
            require(decodedTokens.isNotEmpty() && decodedTokens.firstKey() == 0 &&
                decodedTokens.lastKey() + 1 == decodedTokens.size
            ) { "Whisper tiktoken ranks must be contiguous" }
            val tokenBytes = arrayOfNulls<ByteArray>(decodedTokens.size)
            decodedTokens.forEach { (rank, bytes) -> tokenBytes[rank] = bytes }
            return WhisperTiktokenTokenizer(tokenBytes, parseGenerationConfig(generationConfigFile))
        }

        private const val EMPTY_TOKEN_SENTINEL = "="

        private fun parseGenerationConfig(file: File): WhisperGenerationTokens {
            val root = JSONObject(file.readText(Charsets.UTF_8))
            val languageMap = root.getJSONObject("lang_to_id")
            val languages = buildMap {
                languageMap.keys().forEach { key ->
                    val normalized = key.removePrefix("<|").removeSuffix("|>")
                    put(normalized, languageMap.getInt(key))
                }
            }
            val tasks = root.getJSONObject("task_to_id")
            return WhisperGenerationTokens(
                startOfTranscript = root.getInt("decoder_start_token_id"),
                endOfText = root.getInt("eos_token_id"),
                noTimestamps = root.getInt("no_timestamps_token_id"),
                languageTokens = languages,
                transcribe = tasks.getInt("transcribe"),
                suppressTokens = root.getJSONArray("suppress_tokens").toIntSet(),
                beginSuppressTokens = root.getJSONArray("begin_suppress_tokens").toIntSet()
            )
        }
    }
}

private fun org.json.JSONArray.toIntSet(): Set<Int> = buildSet {
    repeat(length()) { add(getInt(it)) }
}
