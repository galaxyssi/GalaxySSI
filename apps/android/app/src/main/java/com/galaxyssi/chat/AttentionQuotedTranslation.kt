package com.galaxyssi.chat

/** Translate foreign quotations without retranslating the surrounding Chinese facts. */
internal object AttentionQuotedTranslation {
    private val quoted = Regex("(?<=\uff08)[^\uff08\uff09\n]+(?=\uff09)|(?<=\\()[^()\n]+(?=\\))|" +
        "(?<=\u300c)[^\u300c\u300d\n]+(?=\u300d)|(?<=\u300e)[^\u300e\u300f\n]+(?=\u300f)|(?<=\u201c)[^\u201c\u201d\n]+(?=\u201d)")
    fun ranges(text: String): List<IntRange> {
        val quotes = quoted.findAll(text).filter { match -> match.value.any {
            it in '\u3040'..'\u30ff' || it in '\uac00'..'\ud7af'
        } }.map { it.range }.toList()
        if (quotes.isEmpty()) return emptyList()
        val outside = buildString {
            var start = 0
            for (range in quotes) { append(text.substring(start, range.first)); start = range.last + 1 }
            append(text.substring(start))
        }
        return if (outside.count { it in '\u3400'..'\u9fff' } >= 10 && AttentionArticlePolicy.chinese(outside)) quotes else emptyList()
    }
}
