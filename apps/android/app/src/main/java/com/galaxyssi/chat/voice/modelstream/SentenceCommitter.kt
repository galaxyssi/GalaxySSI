package com.galaxyssi.chat.voice.modelstream

data class CommittedSpeechChunk(
    val requestId: String,
    val sequence: Long,
    val speechText: String,
    val isFinal: Boolean = false
)

data class SentenceCommitterConfig(
    val firstChunkMinCharacters: Int = 8,
    val firstChunkMaxWaitMs: Long = 500L,
    val commaCommitCharacters: Int = 28,
    val targetChunkCharacters: Int = 56,
    val maxChunkCharacters: Int = 96
) {
    init {
        require(firstChunkMinCharacters > 0)
        require(firstChunkMaxWaitMs > 0L)
        require(commaCommitCharacters >= firstChunkMinCharacters)
        require(targetChunkCharacters >= firstChunkMinCharacters)
        require(maxChunkCharacters >= targetChunkCharacters)
    }
}

fun interface SentenceCommitterClock {
    fun elapsedRealtimeMs(): Long
}

interface SentenceCommitter {
    fun reset(requestId: String)
    fun acceptDelta(sequence: Long, text: String): List<CommittedSpeechChunk>
    fun commitDue(): List<CommittedSpeechChunk>
    fun flush(): List<CommittedSpeechChunk>
}

class DefaultSentenceCommitter(
    private val config: SentenceCommitterConfig = SentenceCommitterConfig(),
    private val clock: SentenceCommitterClock = SentenceCommitterClock { System.nanoTime() / 1_000_000L }
) : SentenceCommitter {
    private val pending = StringBuilder()
    private var requestId = ""
    private var lastDeltaSequence = -1L
    private var nextChunkSequence = 0L
    private var pendingSinceMs = -1L
    private var hasCommitted = false

    @Synchronized
    override fun reset(requestId: String) {
        this.requestId = requestId.trim()
        pending.setLength(0)
        lastDeltaSequence = -1L
        nextChunkSequence = 0L
        pendingSinceMs = -1L
        hasCommitted = false
    }

    @Synchronized
    override fun acceptDelta(sequence: Long, text: String): List<CommittedSpeechChunk> {
        if (requestId.isBlank() || sequence <= lastDeltaSequence) return emptyList()
        lastDeltaSequence = sequence
        if (text.isBlank()) return emitAvailable(forceFirstChunk = false, flush = false)
        if (pending.isEmpty()) pendingSinceMs = clock.elapsedRealtimeMs()
        pending.append(text)
        return emitAvailable(forceFirstChunk = false, flush = false)
    }

    @Synchronized
    override fun commitDue(): List<CommittedSpeechChunk> {
        val due = !hasCommitted && pendingSinceMs >= 0L &&
            clock.elapsedRealtimeMs() - pendingSinceMs >= config.firstChunkMaxWaitMs
        return emitAvailable(forceFirstChunk = due, flush = false)
    }

    @Synchronized
    override fun flush(): List<CommittedSpeechChunk> {
        val emitted = emitAvailable(forceFirstChunk = true, flush = true).toMutableList()
        if (pending.isNotEmpty()) {
            val normalized = SpeechTextNormalizer.normalize(pending.toString())
            pending.setLength(0)
            pendingSinceMs = -1L
            if (normalized.isNotBlank()) emitted += chunk(normalized, isFinal = true)
        }
        if (emitted.isNotEmpty()) {
            val lastIndex = emitted.lastIndex
            emitted[lastIndex] = emitted[lastIndex].copy(isFinal = true)
        }
        return emitted
    }

    private fun emitAvailable(forceFirstChunk: Boolean, flush: Boolean): List<CommittedSpeechChunk> {
        if (pending.isEmpty()) return emptyList()
        val emitted = mutableListOf<CommittedSpeechChunk>()
        while (pending.isNotEmpty()) {
            val boundary = findBoundary(
                pending.toString(),
                forceFirstChunk = forceFirstChunk && !hasCommitted,
                flush = flush
            ) ?: break
            val raw = pending.substring(0, boundary)
            pending.delete(0, boundary)
            val normalized = SpeechTextNormalizer.normalize(raw)
            if (normalized.isNotBlank()) {
                emitted += chunk(normalized, isFinal = false)
                hasCommitted = true
            }
            pendingSinceMs = if (pending.isEmpty()) -1L else clock.elapsedRealtimeMs()
        }
        return emitted
    }

    private fun chunk(text: String, isFinal: Boolean): CommittedSpeechChunk = CommittedSpeechChunk(
        requestId = requestId,
        sequence = nextChunkSequence++,
        speechText = text,
        isFinal = isFinal
    )

    private fun findBoundary(text: String, forceFirstChunk: Boolean, flush: Boolean): Int? {
        var index = 0
        var speakableCharacters = 0
        var lastSoftBoundary = -1
        var lastWordBoundary = -1
        var hardBoundary = -1
        var safeScanLimit = text.length
        while (index < text.length) {
            when {
                startsPrivateReasoning(text, index) -> {
                    val end = privateReasoningEnd(text, index)
                    if (end < 0) {
                        safeScanLimit = index
                        break
                    }
                    index = end
                    continue
                }
                text.startsWith("```", index) || text.startsWith("~~~", index) -> {
                    val marker = text.substring(index, index + 3)
                    val end = text.indexOf(marker, index + 3)
                    if (end < 0) {
                        safeScanLimit = index
                        break
                    }
                    index = end + marker.length
                    continue
                }
                text[index] == '`' -> {
                    val end = text.indexOf('`', index + 1)
                    if (end < 0) {
                        safeScanLimit = index
                        break
                    }
                    index = end + 1
                    continue
                }
                startsUrl(text, index) -> {
                    val end = text.indexOfFirstFrom(index) { it.isWhitespace() }
                    if (end < 0) {
                        if (flush) return text.length
                        safeScanLimit = index
                        break
                    }
                    index = end
                    continue
                }
                startsStructuredValue(text, index) -> {
                    val end = structuredValueEnd(text, index)
                    if (end < 0) {
                        safeScanLimit = index
                        break
                    }
                    index = end
                    continue
                }
                startsMarkdownTableLine(text, index) -> {
                    val end = text.indexOf('\n', index)
                    if (end < 0) {
                        if (flush) return text.length
                        safeScanLimit = index
                        break
                    }
                    index = end + 1
                    continue
                }
            }

            val character = text[index]
            if (!character.isWhitespace() && !character.isMarkdownSyntax()) speakableCharacters += 1
            if (character.isWhitespace()) lastWordBoundary = index + 1

            val strongBoundary = when (character) {
                '。', '！', '？', '；', '!', '?', ';' -> true
                '.' -> isEnglishSentencePeriod(text, index)
                '\n' -> speakableCharacters >= config.firstChunkMinCharacters
                else -> false
            }
            if (strongBoundary && speakableCharacters >= 2) return index + 1
            if (character == ',' || character == '，' || character == ':' || character == '：') {
                lastSoftBoundary = index + 1
                if (speakableCharacters >= config.commaCommitCharacters) return lastSoftBoundary
            }
            if (speakableCharacters >= config.targetChunkCharacters && lastSoftBoundary > 0) {
                return lastSoftBoundary
            }
            if (speakableCharacters >= config.maxChunkCharacters) {
                hardBoundary = when {
                    lastWordBoundary > 0 -> lastWordBoundary
                    lastSoftBoundary > 0 -> lastSoftBoundary
                    else -> index + 1
                }
                break
            }
            index += 1
        }

        if (hardBoundary > 0) return hardBoundary
        if (forceFirstChunk && speakableCharacters >= config.firstChunkMinCharacters) {
            return when {
                lastSoftBoundary > 0 -> lastSoftBoundary
                lastWordBoundary > 0 -> lastWordBoundary
                safeScanLimit > 0 -> safeCharacterBoundary(
                    text.substring(0, safeScanLimit),
                    config.targetChunkCharacters
                )
                else -> null
            }
        }
        if (flush) return text.length
        return null
    }

    private fun safeCharacterBoundary(text: String, desiredCharacters: Int): Int {
        var count = 0
        text.forEachIndexed { index, character ->
            if (!character.isWhitespace() && !character.isMarkdownSyntax()) count += 1
            if (count >= desiredCharacters) return index + 1
        }
        return text.length
    }

    private fun startsUrl(text: String, index: Int): Boolean =
        text.regionMatches(index, "https://", 0, 8, ignoreCase = true) ||
            text.regionMatches(index, "http://", 0, 7, ignoreCase = true) ||
            text.regionMatches(index, "www.", 0, 4, ignoreCase = true)

    private fun startsPrivateReasoning(text: String, index: Int): Boolean = PRIVATE_REASONING_TAGS.any { tag ->
        text.regionMatches(index, "<$tag>", 0, tag.length + 2, ignoreCase = true)
    }

    private fun privateReasoningEnd(text: String, start: Int): Int {
        val tag = PRIVATE_REASONING_TAGS.firstOrNull { candidate ->
            text.regionMatches(start, "<$candidate>", 0, candidate.length + 2, ignoreCase = true)
        } ?: return -1
        val closing = "</$tag>"
        val end = text.indexOf(closing, start + tag.length + 2, ignoreCase = true)
        return if (end < 0) -1 else end + closing.length
    }

    private fun startsStructuredValue(text: String, index: Int): Boolean {
        if (text[index] == '{') return true
        if (text[index] != '[') return false
        val next = text.drop(index + 1).firstOrNull { !it.isWhitespace() } ?: return false
        return next == '{' || next == '[' || next == '"' || next == '-' || next.isDigit()
    }

    private fun structuredValueEnd(text: String, start: Int): Int {
        val stack = ArrayDeque<Char>()
        var inString = false
        var escaped = false
        for (index in start until text.length) {
            val character = text[index]
            if (inString) {
                when {
                    escaped -> escaped = false
                    character == '\\' -> escaped = true
                    character == '"' -> inString = false
                }
                continue
            }
            when (character) {
                '"' -> inString = true
                '{' -> stack.addLast('}')
                '[' -> stack.addLast(']')
                '}', ']' -> {
                    if (stack.isEmpty() || stack.removeLast() != character) return -1
                    if (stack.isEmpty()) return index + 1
                }
            }
        }
        return -1
    }

    private fun startsMarkdownTableLine(text: String, index: Int): Boolean {
        if (index > 0 && text[index - 1] != '\n') return false
        val end = text.indexOf('\n', index).takeIf { it >= 0 } ?: text.length
        val line = text.substring(index, end).trim()
        return line.count { it == '|' } >= 2 ||
            (line.contains('|') && line.replace("|", "").all { it == '-' || it == ':' || it.isWhitespace() })
    }

    private fun isEnglishSentencePeriod(text: String, index: Int): Boolean {
        val previous = text.getOrNull(index - 1)
        val next = text.getOrNull(index + 1)
        if (previous?.isDigit() == true && next?.isDigit() == true) return false
        if (next == '.') return false
        val tokenStart = (index - 1 downTo 0)
            .firstOrNull { !text[it].isLetter() }
            ?.plus(1)
            ?: 0
        val token = text.substring(tokenStart, index).lowercase()
        if (token in ENGLISH_ABBREVIATIONS) return false
        if (token.length == 1 && previous?.isUpperCase() == true && next?.isLetter() == true) return false
        return next == null || next.isWhitespace() || next == '\n' || next == '"' || next == '\''
    }

    private fun String.indexOfFirstFrom(start: Int, predicate: (Char) -> Boolean): Int {
        for (index in start until length) if (predicate(this[index])) return index
        return -1
    }

    private fun Char.isMarkdownSyntax(): Boolean = this in setOf('#', '*', '_', '`', '>', '|', '~')

    private companion object {
        val ENGLISH_ABBREVIATIONS = setOf(
            "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e"
        )
        val PRIVATE_REASONING_TAGS = listOf("think", "analysis", "reasoning")
    }
}

object SpeechTextNormalizer {
    private val fencedBlock = Regex("(?s)(```|~~~).*?(?:\\1|$)")
    private val privateReasoning = Regex("(?is)<(?:think|analysis|reasoning)>.*?(?:</(?:think|analysis|reasoning)>|$)")
    private val inlineCode = Regex("`[^`]*(?:`|$)")
    private val markdownImage = Regex("!\\[[^]]*]\\([^)]*(?:\\)|$)")
    private val markdownLink = Regex("\\[([^]]+)]\\([^)]*(?:\\)|$)")
    private val url = Regex("(?i)\\b(?:https?://|www\\.)\\S+")
    private val windowsPath = Regex("(?i)\\b[A-Z]:\\\\(?:[^\\s\\\\]+\\\\)*[^\\s,;:!?]+")
    private val unixPath = Regex("(?<![A-Za-z0-9])/(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+")
    private val htmlTag = Regex("<[^>]*(?:>|$)")
    private val longNumber = Regex("(?<!\\d)\\d{10,}(?!\\d)")
    private val markdownPrefix = Regex("(?m)^\\s{0,3}(?:#{1,6}\\s+|[-*+]\\s+|\\d+[.)]\\s+|>\\s*)")
    private val markdownDecoration = Regex("(?:\\*\\*|__|~~|(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_))")
    private val whitespace = Regex("\\s+")

    fun normalize(text: String): String {
        if (text.isBlank()) return ""
        var value = privateReasoning.replace(text, " ")
        value = fencedBlock.replace(value, " ")
        value = inlineCode.replace(value, " ")
        value = markdownImage.replace(value, " ")
        value = markdownLink.replace(value) { match -> match.groupValues[1] }
        value = url.replace(value, " ")
        value = windowsPath.replace(value, " ")
        value = unixPath.replace(value, " ")
        value = removeStructuredValues(value)
        value = value.lineSequence()
            .filterNot(::isMarkdownTableLine)
            .joinToString(" ")
        value = htmlTag.replace(value, " ")
        value = markdownPrefix.replace(value, "")
        value = markdownDecoration.replace(value, "")
        value = longNumber.replace(value, " ")
        return whitespace.replace(value, " ").trim(' ', '-', ':', '\uFF1A', ',', '\uFF0C')
    }

    private fun removeStructuredValues(text: String): String {
        val result = StringBuilder(text.length)
        var index = 0
        while (index < text.length) {
            val character = text[index]
            val structured = character == '{' || (character == '[' && looksLikeJsonArray(text, index))
            if (!structured) {
                result.append(character)
                index += 1
                continue
            }
            val end = findStructuredEnd(text, index)
            if (end < 0) break
            result.append(' ')
            index = end
        }
        return result.toString()
    }

    private fun looksLikeJsonArray(text: String, index: Int): Boolean {
        val next = text.drop(index + 1).firstOrNull { !it.isWhitespace() } ?: return false
        return next == '{' || next == '[' || next == '"' || next == '-' || next.isDigit()
    }

    private fun findStructuredEnd(text: String, start: Int): Int {
        val stack = ArrayDeque<Char>()
        var inString = false
        var escaped = false
        for (index in start until text.length) {
            val character = text[index]
            if (inString) {
                when {
                    escaped -> escaped = false
                    character == '\\' -> escaped = true
                    character == '"' -> inString = false
                }
                continue
            }
            when (character) {
                '"' -> inString = true
                '{' -> stack.addLast('}')
                '[' -> stack.addLast(']')
                '}', ']' -> {
                    if (stack.isEmpty() || stack.removeLast() != character) return text.length
                    if (stack.isEmpty()) return index + 1
                }
            }
        }
        return -1
    }

    private fun isMarkdownTableLine(line: String): Boolean {
        val trimmed = line.trim()
        return trimmed.count { it == '|' } >= 2 ||
            (trimmed.contains('|') && trimmed.replace("|", "").all { it == '-' || it == ':' || it.isWhitespace() })
    }
}
