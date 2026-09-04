package com.galaxyssi.chat.voice.asr.local

data class TimedTranscriptSegment(
    val startMs: Long,
    val endMs: Long,
    val text: String,
    val averageLogProb: Float?,
    val noSpeechProbability: Float?
)

data class DecodedWhisperWindow(
    val requestId: String,
    val windowStartMs: Long,
    val windowEndMs: Long,
    val text: String,
    val segments: List<TimedTranscriptSegment>,
    val realTimeFactor: Double,
    val final: Boolean
)

data class StabilizedTranscript(
    val stableText: String,
    val unstableText: String,
    val revision: Int,
    val final: Boolean
) {
    val displayText: String
        get() = joinTranscriptText(stableText, unstableText)
}

class WhisperSegmentDecoder {
    fun decode(request: ScheduledWhisperDecode, result: NativeWhisperResult): DecodedWhisperWindow {
        val windowStartMs = request.windowStartSample * 1_000L / request.sampleRateHz
        val windowEndMs = request.windowEndSampleExclusive * 1_000L / request.sampleRateHz
        return DecodedWhisperWindow(
            requestId = request.requestId,
            windowStartMs = windowStartMs,
            windowEndMs = windowEndMs,
            text = normalizeTranscriptText(result.text),
            segments = result.segments.map { segment ->
                TimedTranscriptSegment(
                    startMs = windowStartMs + segment.startMs,
                    endMs = windowStartMs + segment.endMs,
                    text = normalizeTranscriptText(segment.text),
                    averageLogProb = segment.averageLogProb.takeUnless(Float::isNaN),
                    noSpeechProbability = segment.noSpeechProbability.takeUnless(Float::isNaN)
                )
            },
            realTimeFactor = result.timings.realTimeFactor,
            final = request.isFinal
        )
    }
}

class WhisperTextStabilizer(
    private val stabilityLagMs: Long = 500L,
    private val minimumAverageLogProbability: Float = -1.5f,
    private val maximumNoSpeechProbability: Float = 0.60f
) {
    private var stable = ""
    private var previousCandidate = ""
    private var revision = 0

    fun accept(window: DecodedWhisperWindow): StabilizedTranscript {
        revision += 1
        if (window.final) {
            val finalText = normalizeTranscriptText(window.text)
            stable = if (finalText.isNotBlank()) finalText else stable
            previousCandidate = stable
            return StabilizedTranscript(stable, "", revision, final = true)
        }

        val candidate = mergeTranscriptOverlap(stable, window.text)
        val common = commonPrefix(previousCandidate, candidate)
        val safeText = stableEligibleText(window)
        val safeCandidate = mergeTranscriptOverlap(stable, safeText)
        val promotionLimit = minOf(common.length, safeCandidate.length)
        if (promotionLimit > stable.length && candidate.startsWith(stable)) {
            val boundary = stableBoundary(candidate, promotionLimit)
            if (boundary > stable.length) stable = candidate.take(boundary).trimEnd()
        }
        previousCandidate = candidate
        val unstable = candidate.removePrefix(stable).trimStart()
        return StabilizedTranscript(stable, unstable, revision, final = false)
    }

    fun reset() {
        stable = ""
        previousCandidate = ""
        revision = 0
    }

    private fun stableEligibleText(window: DecodedWhisperWindow): String {
        val latestStableEnd = window.windowEndMs - stabilityLagMs
        return window.segments.asSequence()
            .filter { it.endMs <= latestStableEnd }
            .filter { (it.averageLogProb ?: 0f) >= minimumAverageLogProbability }
            .filter { (it.noSpeechProbability ?: 0f) <= maximumNoSpeechProbability }
            .map(TimedTranscriptSegment::text)
            .filter(String::isNotBlank)
            .fold("") { combined, text -> joinTranscriptText(combined, text) }
            .let(::normalizeTranscriptText)
    }

    private fun stableBoundary(value: String, limit: Int): Int {
        if (limit <= 0) return 0
        val safe = limit.coerceAtMost(value.length)
        if (safe == value.length) return safe
        val next = value[safe]
        if (next.isWhitespace() || next in STABLE_PUNCTUATION || isCjk(next)) return safe
        for (index in safe downTo 1) {
            val character = value[index - 1]
            if (character.isWhitespace() || character in STABLE_PUNCTUATION || isCjk(character)) return index
        }
        return 0
    }

    private fun commonPrefix(first: String, second: String): String {
        val count = minOf(first.length, second.length)
        var index = 0
        while (index < count && first[index] == second[index]) index += 1
        return first.take(index)
    }

    private fun isCjk(character: Char): Boolean = character.code in 0x3400..0x9FFF

    private companion object {
        val STABLE_PUNCTUATION = setOf(
            '.', ',', '!', '?', ';', ':',
            '\u3002', '\uff0c', '\uff01', '\uff1f', '\uff1b', '\uff1a'
        )
    }
}

internal fun normalizeTranscriptText(value: String): String = value
    .trim()
    .replace(Regex("\\s+"), " ")

internal fun mergeTranscriptOverlap(prefix: String, incoming: String): String {
    val left = normalizeTranscriptText(prefix)
    val right = normalizeTranscriptText(incoming)
    if (left.isBlank()) return right
    if (right.isBlank()) return left
    if (right.startsWith(left)) return right
    if (left.endsWith(right)) return left
    val max = minOf(left.length, right.length)
    var overlap = 0
    for (size in 1..max) {
        if (left.regionMatches(left.length - size, right, 0, size, ignoreCase = false)) overlap = size
    }
    return joinTranscriptText(left, right.drop(overlap))
}

internal fun joinTranscriptText(first: String, second: String): String {
    if (first.isBlank()) return second.trim()
    if (second.isBlank()) return first.trim()
    val needsSpace = first.last().isLetterOrDigit() && second.first().isLetterOrDigit() &&
        first.last().code !in 0x3400..0x9FFF && second.first().code !in 0x3400..0x9FFF
    return if (needsSpace) "${first.trimEnd()} ${second.trimStart()}" else first.trimEnd() + second.trimStart()
}
