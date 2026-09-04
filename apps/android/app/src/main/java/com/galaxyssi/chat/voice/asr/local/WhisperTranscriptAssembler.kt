package com.galaxyssi.chat.voice.asr.local

internal class WhisperTranscriptAssembler {
    private var text = ""

    fun append(segment: String): String {
        text = merge(text, segment)
        return text
    }

    fun preview(stable: String): String = merge(text, stable)

    fun value(): String = text

    fun reset() {
        text = ""
    }

    companion object {
        internal fun merge(prefix: String, suffix: String): String {
            val left = prefix.trim()
            val right = suffix.trim()
            if (left.isEmpty()) return right
            if (right.isEmpty()) return left
            val leftPoints = left.codePoints().toArray()
            val rightPoints = right.codePoints().toArray()
            val maximum = minOf(leftPoints.size, rightPoints.size, MAX_OVERLAP_CODE_POINTS)
            var overlap = 0
            for (candidate in maximum downTo 1) {
                var matches = true
                for (index in 0 until candidate) {
                    if (leftPoints[leftPoints.size - candidate + index] != rightPoints[index]) {
                        matches = false
                        break
                    }
                }
                if (matches && acceptableOverlap(leftPoints, rightPoints, candidate)) {
                    overlap = candidate
                    break
                }
            }
            val remainder = String(rightPoints, overlap, rightPoints.size - overlap)
            if (remainder.isEmpty()) return left
            return left + separator(leftPoints.last(), remainder.codePointAt(0)) + remainder
        }

        private fun acceptableOverlap(left: IntArray, right: IntArray, count: Int): Boolean {
            if (count >= 2) return true
            val point = right.first()
            return isCjk(point) || !Character.isLetterOrDigit(point) ||
                left.size == right.size && left.contentEquals(right)
        }

        private fun separator(left: Int, right: Int): String = if (
            Character.isLetterOrDigit(left) && Character.isLetterOrDigit(right) &&
            !isCjk(left) && !isCjk(right)
        ) " " else ""

        private fun isCjk(point: Int): Boolean = point in 0x3400..0x9fff

        private const val MAX_OVERLAP_CODE_POINTS = 96
    }
}
