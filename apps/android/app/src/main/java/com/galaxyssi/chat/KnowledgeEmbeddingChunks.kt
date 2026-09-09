package com.galaxyssi.chat

internal data class KnowledgeEmbeddingChunk(val start: Int, val end: Int, val next: Int, val text: String)

/** Bounded token-aware chunks with UTF-16 provenance and code-point-safe overlap. */
internal object KnowledgeEmbeddingChunks {
    fun next(text: String, offset: Int, maxTokens: Int, countTokens: (String) -> Int): KnowledgeEmbeddingChunk? {
        require(offset in 0..text.length && maxTokens in 8..8192)
        require(offset == 0 || offset == text.length || !text[offset].isLowSurrogate() || !text[offset - 1].isHighSurrogate())
        var start = offset
        while (start < text.length && text[start].isWhitespace()) start++
        if (start == text.length) return null
        var cap = minOf(text.length, start + maxTokens * 4)
        if (cap < text.length && text[cap].isLowSurrogate() && text[cap - 1].isHighSurrogate()) cap--
        val points = text.codePointCount(start, cap)
        var low = 1
        var high = points
        var best = 0
        while (low <= high) {
            val middle = low + (high - low) / 2
            val end = text.offsetByCodePoints(start, middle)
            if (countTokens(text.substring(start, end)) <= maxTokens) { best = middle; low = middle + 1 }
            else high = middle - 1
        }
        require(best > 0) { "A Unicode code point exceeds the embedding token window" }
        val end = text.offsetByCodePoints(start, best)
        val chunk = text.substring(start, end)
        check(countTokens(chunk) <= maxTokens) { "Embedding chunk token count changed" }
        val overlap = minOf(32, best / 4)
        val next = if (end == text.length) end else text.offsetByCodePoints(start, best - overlap)
        check(next > offset)
        return KnowledgeEmbeddingChunk(start, end, next, chunk)
    }
}
