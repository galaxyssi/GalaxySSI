package com.signalasi.chat.voice.asr.local

internal data class StableWhisperHypothesis(
    val stableText: String,
    val unstableText: String,
    val fullText: String,
    val final: Boolean
)

internal class WhisperTwoPassStabilizer {
    private var stableText = ""
    private var previousCandidate = ""

    @Synchronized
    fun update(hypothesis: String, final: Boolean = false): StableWhisperHypothesis {
        val normalized = normalizeTranscriptText(hypothesis)
        val candidate = when {
            stableText.isBlank() -> normalized
            normalized.isBlank() -> stableText
            else -> mergeTranscriptOverlap(stableText, normalized)
        }
        if (final) {
            stableText = candidate
            previousCandidate = candidate
            return StableWhisperHypothesis(stableText, "", stableText, true)
        }

        val common = commonCodePointPrefix(previousCandidate, candidate)
        if (candidate.startsWith(stableText) && common.length > stableText.length) {
            stableText = stableBoundary(common)
        }
        previousCandidate = candidate
        return StableWhisperHypothesis(
            stableText = stableText,
            unstableText = candidate.removePrefix(stableText).trimStart(),
            fullText = candidate,
            final = false
        )
    }

    @Synchronized
    fun reset() {
        stableText = ""
        previousCandidate = ""
    }

    private fun commonCodePointPrefix(left: String, right: String): String {
        val leftPoints = left.codePoints().toArray()
        val rightPoints = right.codePoints().toArray()
        var count = 0
        while (count < leftPoints.size && count < rightPoints.size && leftPoints[count] == rightPoints[count]) {
            count += 1
        }
        return String(leftPoints, 0, count)
    }

    private fun stableBoundary(value: String): String {
        if (value.isBlank()) return ""
        val lastCodePoint = value.codePointBefore(value.length)
        if (isCjk(lastCodePoint) || Character.isWhitespace(lastCodePoint) || lastCodePoint in PUNCTUATION) {
            return value.trimEnd()
        }
        val boundary = value.indexOfLast { character -> character.isWhitespace() || character.code in PUNCTUATION }
        return if (boundary >= 0) value.take(boundary + 1).trimEnd() else stableText
    }

    private fun isCjk(codePoint: Int): Boolean = codePoint in 0x3400..0x9FFF || codePoint in 0x20000..0x2FA1F

    private companion object {
        val PUNCTUATION = setOf(
            '.'.code, ','.code, '!'.code, '?'.code, ';'.code, ':'.code,
            '\u3002'.code, '\uff0c'.code, '\uff01'.code, '\uff1f'.code, '\uff1b'.code, '\uff1a'.code
        )
    }
}
