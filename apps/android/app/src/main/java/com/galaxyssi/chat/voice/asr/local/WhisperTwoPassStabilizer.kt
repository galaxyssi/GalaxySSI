package com.galaxyssi.chat.voice.asr.local

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
        val rawNormalized = normalizeTranscriptText(hypothesis)
        val normalized = if (final) collapseRepeatedFinalPrefix(rawNormalized) else rawNormalized
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

    private fun collapseRepeatedFinalPrefix(value: String): String {
        val evidence = stableText.ifBlank { previousCandidate }
        val evidenceKey = canonicalEvidence(evidence)
        if (evidenceKey.length < MIN_DUPLICATE_EVIDENCE_CHARS) return value

        for (unitEnd in value.length / 2 downTo MIN_DUPLICATE_EVIDENCE_CHARS) {
            val first = value.take(unitEnd).trimEnd()
            val canonicalFirst = canonicalEvidence(first)
            if (canonicalFirst.length < MIN_DUPLICATE_EVIDENCE_CHARS) continue

            var secondStart = unitEnd
            while (secondStart < value.length && value[secondStart].isWhitespace()) secondStart += 1
            if (secondStart + first.length > value.length ||
                !value.regionMatches(secondStart, first, 0, first.length, ignoreCase = false)
            ) continue

            val comparableLength = minOf(canonicalFirst.length, evidenceKey.length)
            var commonLength = 0
            while (commonLength < comparableLength &&
                canonicalFirst[commonLength] == evidenceKey[commonLength]
            ) {
                commonLength += 1
            }
            if (commonLength < MIN_DUPLICATE_EVIDENCE_CHARS ||
                commonLength * 100 < comparableLength * MIN_EVIDENCE_MATCH_PERCENT
            ) continue

            return value.substring(secondStart).trimStart()
        }
        return value
    }

    private fun canonicalEvidence(value: String): String = buildString(value.length) {
        value.forEach { character ->
            if (character.isLetterOrDigit() || isCjk(character.code)) {
                append(character.lowercaseChar())
            }
        }
    }

    private fun isCjk(codePoint: Int): Boolean = codePoint in 0x3400..0x9FFF || codePoint in 0x20000..0x2FA1F

    private companion object {
        const val MIN_DUPLICATE_EVIDENCE_CHARS = 6
        const val MIN_EVIDENCE_MATCH_PERCENT = 70
        val PUNCTUATION = setOf(
            '.'.code, ','.code, '!'.code, '?'.code, ';'.code, ':'.code,
            '\u3002'.code, '\uff0c'.code, '\uff01'.code, '\uff1f'.code, '\uff1b'.code, '\uff1a'.code
        )
    }
}
